class_name BotPolicy
extends RefCounted
## The headless bot's decision logic (analysis/bot.py), written statement for statement.
##
## The bot explores and fights while time allows, picks up and equips gear, sells junk, keeps three
## potions from the shop, opens boxes in safe rooms, rests when hurt, then heads for the nearest
## stairs (or the final boss once the exit is sealed). Each run's companion, race, class, backstory and
## gender come from run_config(seed); every sponsor contract is accepted or declined by a coin flip
## (PyRandom(seed ^ 0xB07)), so the runs form a randomised experiment on deals.
##
## Python hangs two private attributes on the World (`_bot_route`, `_bot_fleeing`); here they live in a
## BotState passed alongside. A move is a Vector2i (Python: a (dx, dy) tuple) or null.

const FLEE_FRAC := 0.4          ## in a fight below this HP with no potion to hand: run
const MAX_STEPS := 200000       ## safety cap on choose() calls; a real run needs far fewer

## Attribute targets per class: the bot raises whichever attribute is furthest below its target.
const FIGHT_ATTR := {"duellist": "dex", "demolitionist": "dex"}
const CLASS_ATTR := {"arcanist": "int", "alchemist": "int", "beastmaster": "cha", "hype_man": "cha",
		"quartermaster": "cha"}


## The bot's per-run state (Python: `w._bot_route`, `w._bot_fleeing`).
class BotState extends RefCounted:
	## Route cache: the floor, target and distance map of the last step_towards (floor null = none).
	var route_floor: DungeonFloor = null
	var route_target: Vector2i = Vector2i.ZERO
	var route_dist: PackedInt32Array = PackedInt32Array()
	var fleeing: bool = false


## Chebyshev distance between two points.
static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## One step downhill on a distance map from the target (cached until the target moves): a Vector2i
## or null.
static func step_towards(w: World, st: BotState, tx: int, ty: int) -> Variant:
	var f := w.floor
	var p := w.player
	var dist: PackedInt32Array
	if st.route_floor != null and st.route_floor == f and st.route_target == Vector2i(tx, ty):
		dist = st.route_dist
	else:
		dist = f.distance_map(tx, ty)
		st.route_floor = f
		st.route_target = Vector2i(tx, ty)
		st.route_dist = dist
	var best: int = dist[p.y * f.width + p.x]
	var move: Variant = null
	for n in DungeonFloor.NEIGHBOURS_8:
		var nx := p.x + n.x
		var ny := p.y + n.y
		if f.walkable(nx, ny):
			var d: int = dist[ny * f.width + nx]
			if d != -1 and d < best:
				best = d
				move = n
	return move


## Worth of a weapon or armour for the equip choice (float for weapons, int for armour).
static func score(key: String) -> Variant:
	var it: Dictionary = Content.item(key)
	if it["kind"] == "weapon":
		var dice: Array = it["dice"]
		return Dice.average(dice[0], dice[1]) * 2 + it.get("hit", 0) + it.get("dmg", 0) * 2
	return it.get("ac", 0) * 2


## Spend stat points on whichever attribute is furthest below its class target.
static func spend_points(w: World, cls: Variant) -> void:
	var fight: String = FIGHT_ATTR.get(cls, "str")
	var targets := {}
	targets[fight] = 18             # a repeated key keeps its first position and takes the last value
	targets["con"] = 16
	targets[CLASS_ATTR.get(cls, "dex")] = 14
	while w.player.stat_points != 0:
		var gaps := {}
		for a in targets:
			gaps[a] = targets[a] - w.score(a)
		var top_attr: String = ""
		var top_gap: int = 0
		var first := true
		for a in gaps:
			if first or gaps[a] > top_gap:
				top_gap = gaps[a]
				top_attr = a
				first = false
		var attr: String = top_attr if top_gap > 0 else fight
		if not w.spend_point(attr):
			break


## Free actions: wear the best gear; in safe rooms open boxes, sell junk, buy potions.
static func manage_items(w: World) -> void:
	if w.in_safe_room:
		while not w.boxes.is_empty() and w.open_box(w.boxes[0]):
			pass
		for i in range(w.inventory.size() - 1, -1, -1):
			if Content.item(w.inventory[i])["kind"] == "junk":
				w.shop_sell(i)
		var potions := 0
		for k in w.inventory:
			if Content.item(k)["kind"] == "potion":
				potions += 1
		for key in ["elixir", "brew", "tonic"]:
			while potions < 3 and w.shop.stock[key].on_hand != 0 and w.gold >= w.buy_price(key) + 10:
				if not w.shop_buy(key):
					break
				potions += 1
	for slot in ["weapon", "armour"]:
		var cur: Variant = w.equipment[slot]
		var best: Variant = null
		var best_score: Variant = null
		for k in w.inventory:
			if Content.item(k)["kind"] == slot:
				var s: Variant = score(k)
				if best == null or s > best_score:
					best = k
					best_score = s
		if best != null and (cur == null or score(best) > score(cur)):
			w.equip(w.inventory.find(best))


static func worth_taking(w: World, xy: Vector2i) -> bool:
	if w.inventory.size() >= 16:
		return false
	for k in w.floor_items[xy]:
		if Content.item(k)["kind"] != "junk":
			return true
	return false


## Out of combat anything goes; in combat only the parts of the turn not yet spent.
static func can(w: World, part: String) -> bool:
	return w.combat == null or w.combat.has(part)


## Index of the first inventory item of that kind, or -1.
static func best_of(w: World, kind: String) -> int:
	for i in range(w.inventory.size()):
		if Content.item(w.inventory[i])["kind"] == kind:
			return i
	return -1


## One act per call, as [act, arg]. In combat a move or attack that's already spent becomes a wait,
## which ends the turn. A "move" arg is a Vector2i.
static func choose(w: World, st: BotState) -> Array:
	var r := _choose(w, st)
	var act: String = r[0]
	var arg: Variant = r[1]
	if act == "move" and w.combat != null:
		var p := w.player
		var part := "action" if w.monster_at(p.x + arg.x, p.y + arg.y) != null else "move"
		if not can(w, part):
			return ["wait", null]
		# Don't walk out of a monster's reach (a free swing at you) unless fleeing hurt,
		# to a safe room or the stairs.
		if part == "move" and not w.provokers(arg.x, arg.y).is_empty() and not st.fleeing:
			return ["wait", null]
	return [act, arg]


## The nearer of the safe room and an open stairwell.
static func flee_goal(w: World) -> Vector2i:
	var p := w.player
	var f := w.floor
	var goals: Array = [f.safe_room.centre()]
	if not w.stairs_locked and not w.exit_sealed:
		goals.append_array(f.stairs)
	var pos := Vector2i(p.x, p.y)
	var best: Vector2i = goals[0]
	var best_d := cheb(best, pos)
	for g in goals:
		var d := cheb(g, pos)
		if d < best_d:
			best_d = d
			best = g
	return best


static func _choose(w: World, st: BotState) -> Array:
	var p := w.player
	var f := w.floor
	var pos := Vector2i(p.x, p.y)
	st.fleeing = false
	var adj_n := 0
	for m in w.monsters:
		if cheb(Vector2i(m.x, m.y), pos) == 1:
			adj_n += 1
	if w.floor_items.has(pos) and worth_taking(w, pos) and can(w, "action") \
			and not (w.combat != null and adj_n != 0):
		return ["pickup", null]
	if p.hp < p.max_hp * 0.45 and not w.in_safe_room and can(w, "bonus"):
		var potion := best_of(w, "potion")
		if potion != -1:
			return ["use", potion]
	var golem_seen := false
	for m in w.monsters:
		if w.visible.has(Vector2i(m.x, m.y)) and (m.key == "golem" or m.key == "brute"):
			golem_seen = true
			break
	if adj_n >= 2 or golem_seen:
		var bomb := best_of(w, "bomb")
		if bomb != -1 and can(w, "action"):
			var near_seen := false
			for m in w.monsters:
				if w.visible.has(Vector2i(m.x, m.y)) and cheb(Vector2i(m.x, m.y), pos) <= 3:
					near_seen = true
					break
			if near_seen:
				return ["use", bomb]
	var adj: Array = []
	for m in w.monsters:
		if cheb(Vector2i(m.x, m.y), pos) == 1:
			adj.append(m)
	if PyMath.truthy(w.cls) and w.skill_cooldown == 0 and not w.in_safe_room and can(w, "action"):
		var seen_near: Array = []
		for m in w.monsters:
			if w.visible.has(Vector2i(m.x, m.y)) and cheb(Vector2i(m.x, m.y), pos) <= 6:
				seen_near.append(m)
		var kinds: Array = []
		for k in w.inventory:
			kinds.append(Content.item(k)["kind"])
		var sk: Variant = w.skill
		var pet_fighting := false
		if w.active_pet != null:
			for m in w.monsters:
				if cheb(Vector2i(m.x, m.y), Vector2i(w.pet.x, w.pet.y)) == 1:
					pet_fighting = true
					break
		var potions: int = kinds.count("potion")
		var seen_any := not seen_near.is_empty()
		var has_adj := not adj.is_empty()
		if (sk == "haymaker" and has_adj) or ((sk == "arc_bolt" or sk == "pocket_popper") and seen_any) \
				or (sk == "scout_report" and seen_any and w.scout_turns == 0) \
				or (sk == "field_brew" and kinds.has("junk") and potions < 4) \
				or (sk == "rile_up" and pet_fighting) \
				or (sk == "crowd_work" and seen_any and w.hype_turns == 0) \
				or (sk == "riposte" and has_adj and w.riposte == 0) \
				or (sk == "supply_drop" and potions < 2):
			return ["skill", null]
	if not adj.is_empty() and not w.in_safe_room and w.combat != null and can(w, "move") \
			and p.hp < p.max_hp * FLEE_FRAC and (best_of(w, "potion") == -1 or not can(w, "bonus")):
		var goal := flee_goal(w)
		var mv: Variant = step_towards(w, st, goal.x, goal.y)         # hurt and out of potions: run for it,
		if mv != null and w.monster_at(p.x + mv.x, p.y + mv.y) == null:   # free swings and all
			st.fleeing = true
			return ["move", mv]
	if not adj.is_empty() and not w.in_safe_room:
		return ["move", Vector2i(adj[0].x - p.x, adj[0].y - p.y)]
	if w.on_stairs and not w.stairs_locked and not w.exit_sealed and can(w, "action"):
		var descend := w.timer < w.timer_max * 0.4
		if not descend:
			descend = true
			for r in f.rooms:
				var c := r.centre()
				if f.explored[c.y][c.x] == 0:
					descend = false
					break
		if descend:
			return ["descend", null]
	var hurt: bool = p.hp < p.max_hp * 0.5
	var loot: Array = []
	for xy in w.floor_items:
		if w.visible.has(xy) and worth_taking(w, xy):
			loot.append(xy)
	if not loot.is_empty() and not hurt and w.timer > w.timer_max * 0.4:
		var best_xy: Vector2i = loot[0]
		var best_d := cheb(best_xy, pos)
		for xy in loot:
			var d := cheb(xy, pos)
			if d < best_d:
				best_d = d
				best_xy = xy
		var mv2: Variant = step_towards(w, st, best_xy.x, best_xy.y)
		if mv2 != null:
			return ["move", mv2]
	if hurt and w.in_safe_room and w.timer > 120:
		return ["rest", null]
	if w.in_safe_room and w.pet != null and w.pet.downed and w.timer > 150:
		return ["revive", null]
	var target: Variant = null
	var boss: Monster = null
	for m in w.monsters:
		if m.tier == "headliner":
			boss = m
			break
	if hurt and w.timer > 200:
		target = f.safe_room.centre()
	elif w.exit_sealed and boss != null:
		target = Vector2i(boss.x, boss.y)
	elif w.timer > w.timer_max * 0.4:
		# Bosses are optional before the last floor: only take them on when healthy.
		var seen: Monster = null
		for m in w.monsters:
			if w.visible.has(Vector2i(m.x, m.y)) and (not m.boss or p.hp > p.max_hp * 0.8):
				seen = m
				break
		if seen != null:
			target = Vector2i(seen.x, seen.y)
		else:
			var best_c: Variant = null
			var best_cd := 0
			for r in f.rooms:
				var c := r.centre()
				if f.explored[c.y][c.x] == 0:
					var d := cheb(c, pos)
					if best_c == null or d < best_cd:
						best_cd = d
						best_c = c
			if best_c != null:
				target = best_c
	if target == null:
		if w.on_stairs:
			return ["descend", null] if not w.stairs_locked else ["wait", null]
		var best_s: Vector2i = f.stairs[0]
		var best_sd := cheb(best_s, pos)
		for s in f.stairs:
			var d := cheb(s, pos)
			if d < best_sd:
				best_sd = d
				best_s = s
		target = best_s
	var t: Vector2i = target
	var mv3: Variant = step_towards(w, st, t.x, t.y)
	return ["move", mv3] if mv3 != null else ["wait", null]


## Companion, backstory, gender, race and class for a seed: {pet, race, cls, backstory, gender}.
## Each is drawn independently from a seeded RNG, so every combination turns up. The draws are in
## Python's order: race, class, backstory, gender.
static func run_config(seed_value: int) -> Dictionary:
	var pick := PyRandom.new(seed_value * 7919 + 13)
	var pet_order: Array = Content.table("pets").keys()
	var cfg := {}
	cfg["pet"] = pet_order[PyMath.mod(seed_value, pet_order.size())]
	cfg["race"] = pick.choice(Content.table("races").keys())
	cfg["cls"] = pick.choice(Content.table("classes").keys())
	cfg["backstory"] = pick.choice(Content.table("backstories").keys())
	cfg["gender"] = pick.choice(Content.table("genders").keys())
	return cfg


## After a Supply Drop: buy a brew or tonic from the remote shop, then close it (the bot's loop).
static func remote_shop_buy(w: World) -> void:
	for key in ["brew", "tonic"]:
		if w.shop.stock[key].on_hand != 0 and w.gold >= w.buy_price(key) and w.shop_buy(key):
			break
	w.remote_shop = false


## Play one run. `deals` is "random" (coin flip per offer), "accept" or "decline". A run that hits
## max_steps stops while still "playing" (reported as stuck). `pet` "" takes the run_config companion,
## "none" plays without one. Returns [world, tables] (tables null unless `telemetry`). The Telemetry is
## held in a local for the whole run: the event bus calls it through a bound callable only.
static func play(seed_value: int, pet: String = "", deals: String = "random", telemetry: bool = false,
		max_steps: int = MAX_STEPS) -> Array:
	var cfg := run_config(seed_value)
	if pet == "":
		pet = cfg["pet"]
	var w := World.new(seed_value, [pet, ""] if pet != "none" else null,
			{"name": "Bot", "gender": cfg["gender"], "backstory": cfg["backstory"]})
	var tel: Telemetry = null
	if telemetry:
		tel = Telemetry.new(w, "bot", "bot%05d" % seed_value, {"deals": deals})
	var coin := PyRandom.new(seed_value ^ 0xB07)
	var st := BotState.new()
	for _i in range(max_steps):
		if w.state != "playing":
			break
		if w.pending_choice:
			w.choose_class(cfg["race"], cfg["cls"])
		if PyMath.truthy(w.pending_offer):
			var take: bool = (coin.random() < 0.5) if deals == "random" else deals == "accept"
			if take:
				w.accept_contract()
			else:
				w.decline_contract()
		spend_points(w, cfg["cls"])
		manage_items(w)
		var r := choose(w, st)
		var act: String = r[0]
		var arg: Variant = r[1]
		var ok: bool
		if act == "move":
			ok = w.move_player(arg.x, arg.y)
		elif act == "descend":
			ok = w.descend()
		elif act == "rest":
			ok = w.rest()
		elif act == "pickup":
			ok = w.pickup()
		elif act == "use":
			ok = w.use_item(arg)
		elif act == "skill":
			ok = w.use_skill()
			if ok and w.remote_shop:
				remote_shop_buy(w)
		elif act == "revive":
			ok = w.revive_pet()
		else:
			ok = w.wait()
		if not ok:
			w.wait()
	var tables: Variant = tel.tables() if tel != null else null
	return [w, tables]

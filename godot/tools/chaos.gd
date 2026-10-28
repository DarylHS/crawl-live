extends SceneTree
## Chaos trace harness, Godot side. Mirrors scripts/chaos_trace.py line for line (see its header for what
## the chaos player does and why); scripts/chaos_diff.py compares the two.
##
##   godot --headless --path godot -s res://tools/chaos.gd -- --seeds 0-9 --steps 600 --out-dir DIR
##   godot --headless --path godot -s res://tools/chaos.gd -- --seed 3 --steps 600 --out run.jsonl
##
## --no-mute-standins: by default the events the P1 stand-in systems cannot produce (achievement,
## viewers_gained, sponsor_gift, fun_fact, showmanship practice_level) are left out, matching
## chaos_trace.py --mute-standins. T1/T2/T3 must pass --no-mute-standins to both sides.
const RACES := ['human', 'elf', 'dwarf', 'hobgoblin', 'bog_troll', 'houseplant']
const CLASSES := ['brawler', 'arcanist', 'analyst', 'alchemist', 'beastmaster', 'hype_man', 'demolitionist', 'quartermaster', 'duellist']
const TIERS := ['bronze', 'silver', 'gold', 'platinum', 'legendary']
const SHOPKEYS := ['tonic', 'brew', 'elixir', 'popper', 'fireworks', 'jersey', 'vest', 'pan', 'cleaver']
const ATTRS := ['str', 'dex', 'con', 'int', 'cha']
const PETS := ['none', 'cat', 'dog', 'budgie', 'mouse']
const GENDERS := ['female', 'male', 'nonbinary']
const BACKS := ['veteran', 'mixologist', 'dog_walker', 'comedian', 'parent', 'tradie', 'category_mgr', 'rideshare']
const MUTED_EVENTS := ["achievement", "viewers_gained", "sponsor_gift", "fun_fact"]

var mute := true

var evs: Array = []
var msgs: Array = []
var w: World
var p: Player
var rng: PyRandom
var out: FileAccess


func _tap(n: String, d: Dictionary) -> void:
	if not (mute and (MUTED_EVENTS.has(n) or (n == "practice_level" and d.get("skill") == "showmanship"))):
		evs.append([n, JSON.parse_string(PyJson.dumps(d))])


func _mtap(text: String, _c: Variant) -> void:
	msgs.append(text)


func cheb(ax: int, ay: int, bx: int, by: int) -> int:
	return maxi(absi(ax - bx), absi(ay - by))


func freet(x: int, y: int) -> bool:
	return (w.floor.walkable(x, y) and not w.floor.is_safe(x, y) and w.monster_at(x, y) == null
			and w.pet_at(x, y) == null and not (x == p.x and y == p.y))


func ring(cx: int, cy: int, d: int) -> Variant:
	for dy in range(-d, d + 1):
		for dx in range(-d, d + 1):
			if maxi(absi(dx), absi(dy)) == d and freet(cx + dx, cy + dy):
				return Vector2i(cx + dx, cy + dy)
	return null


func put(xy: Variant) -> void:
	if xy != null:
		p.x = xy.x; p.y = xy.y; w.update_fov()


func to_safe() -> void:
	var r := w.floor.safe_room
	for y in range(r.y, r.y + r.h):
		for x in range(r.x, r.x + r.w):
			if w.floor.walkable(x, y) and w.floor.is_safe(x, y) and w.monster_at(x, y) == null and w.pet_at(x, y) == null:
				p.x = x; p.y = y; w.update_fov(); return


func first_idx(keys: Array) -> int:
	for i in range(w.inventory.size()):
		if keys.has(w.inventory[i]):
			return i
	return -1


func dump(n: int, tag: String, ok: Variant) -> void:
	var pt := w.pet
	var cb := w.combat
	var items := PackedStringArray()
	for k in w.floor_items:
		items.append("%d,%d:%s" % [k.x, k.y, ",".join(PackedStringArray(w.floor_items[k]))])
	var explored := 0
	for row in w.floor.explored:
		for v in row:
			explored += int(v)
	var cbv: Variant = null
	if cb != null:
		var bud := []
		var ks: Array = cb.budget.keys()
		ks.sort()
		for k in ks:
			bud.append(cb.budget[k])
		var ord := []
		for r in cb.order:
			ord.append("%s:%d:%d" % [r[1].name, r[2], r[3]])
		cbv = [cb.round, bud, ord]
	var reasons := {}
	for k in w.box_reasons:
		reasons[k] = (w.box_reasons[k] as Array).duplicate()
	var on_hand := []; var bought := []; var missed := []
	for k in SHOPKEYS:
		on_hand.append(w.shop.stock[k].on_hand); bought.append(w.shop.bought[k]); missed.append(w.shop.missed[k])
	var rec := [n, tag, bool(ok) if ok != null else null, w.turn, w.depth, w.state, w.timer, w.timer_max, w.stairs_open_turn,
		p.x, p.y, p.hp, p.max_hp, p.xp, p.level, p.kills, p.stat_points, p.attrs.duplicate(), p.ac, p.attack, p.dmg_n, p.dmg_die, p.dmg_bonus, p.dr,
		w.gold, TraceFloors.mon_string(w.monsters), ";".join(items),
		[pt.x, pt.y, pt.hp, pt.max_hp, pt.xp, pt.level, pt.kills, pt.cooldown, pt.downed, pt.mode, pt.enraged] if pt != null else null,
		cbv, w.riposte, w.has_key, w.exit_sealed, w.inventory.duplicate(), w.equipment.duplicate(), w.boxes.duplicate(),
		reasons, w.box_log.duplicate(true),
		(w.last_reveal as Array).duplicate() if PyMath.truthy(w.last_reveal) else null, w.last_reason,
		w.race, w.cls, w.pending_choice, w.skill_cooldown, w.scout_turns, w.hype_turns, w.remote_shop,
		w.contract, w.pending_offer, w.death_cause,
		on_hand, bought, missed, w.shop.log.size(),
		w.training.levels.duplicate(), w.training.xp.duplicate(), w.training.steps,
		w.floor_stats.duplicate(true),
		w.rng.state_digest().substr(0, 16), w.loot_rng.state_digest().substr(0, 16), w.shop.rng.state_digest().substr(0, 16), w.deal_rng.state_digest().substr(0, 16),
		explored, evs.duplicate(), msgs.duplicate()]
	out.store_line(PyJson.dumps(rec, false, -1, true))
	evs.clear(); msgs.clear()


func act(n: int, tag: String, ok: Variant) -> Variant:
	dump(n, tag, ok)
	return ok


func safe_block(n: int) -> void:
	to_safe(); dump(n, "tp_safe", null)
	act(n, "rest", w.rest())
	act(n, "craft", w.craft(rng.randrange(4)))
	act(n, "bomb_safe", w.use_item(first_idx(["popper", "fireworks"])) if first_idx(["popper", "fireworks"]) >= 0 else null)
	act(n, "skill_safe", w.use_skill())
	act(n, "buy", w.shop_buy(SHOPKEYS[rng.randrange(9)]))
	act(n, "sell", w.shop_sell(rng.randrange(maxi(1, w.inventory.size()))))
	act(n, "revive", w.revive_pet())
	act(n, "open", w.open_box(w.boxes[rng.randrange(w.boxes.size())]) if not w.boxes.is_empty() else null)
	if rng.random() < 0.6:
		act(n, "reroll", w.reroll())
	act(n, "trade", w.trade_up(TIERS[rng.randrange(5)]))
	act(n, "potion_safe", w.use_item(first_idx(["tonic", "brew", "elixir"])) if first_idx(["tonic", "brew", "elixir"]) >= 0 else null)


func stairs_block(n: int) -> void:
	var s: Vector2i = w.floor.stairs[rng.randrange(w.floor.stairs.size())]
	if w.monster_at(s.x, s.y) == null and w.pet_at(s.x, s.y) == null:
		p.x = s.x; p.y = s.y; w.update_fov()
	if rng.random() < 0.75:
		w.has_key = true
	dump(n, "tp_stairs", null)
	var ok: bool = act(n, "descend", w.descend())
	if not ok:
		act(n, "wait", w.wait())


func _initialize() -> void:
	var seeds: Array = []
	var steps := 600
	var out_file := ""
	var out_dir := ""
	var a := OS.get_cmdline_user_args()
	var i := 0
	while i < a.size():
		match a[i]:
			"--seed":
				seeds = [int(a[i + 1])]
				i += 1
			"--seeds":
				var parts := String(a[i + 1]).split("-")
				var hi := int(parts[parts.size() - 1])
				for s in range(int(parts[0]), hi + 1):
					seeds.append(s)
				i += 1
			"--steps":
				steps = int(a[i + 1])
				i += 1
			"--out":
				out_file = a[i + 1]
				i += 1
			"--out-dir":
				out_dir = a[i + 1]
				i += 1
			"--no-mute-standins":
				mute = false
			"--mute-standins":
				mute = true
			_:
				push_error("chaos.gd: unknown argument " + a[i])
				quit(2)
				return
		i += 1
	if seeds.is_empty() or (out_file == "" and out_dir == ""):
		push_error("chaos.gd: give --seed N --out FILE, or --seeds A-B --out-dir DIR")
		quit(2)
		return
	if out_dir != "":
		DirAccess.make_dir_recursive_absolute(out_dir)
	for sd in seeds:
		_run(sd, steps, out_file if out_dir == "" else "%s/chaos_%d.jsonl" % [out_dir, sd])
	quit(0)


## One chaos run, written to `path`.
func _run(seed_v: int, steps: int, path: String) -> void:
	out = FileAccess.open(path, FileAccess.WRITE)
	var pet: String = PETS[seed_v % 5]
	var hero: Variant = null if seed_v % 4 == 0 else {"name": "H", "gender": GENDERS[seed_v % 3], "backstory": BACKS[(seed_v / 3) % 8]}
	var c := seed_v % 54
	var race: String = RACES[c % 6]; var cls: String = CLASSES[(c / 6) % 9]
	w = World.new(seed_v, [pet, ""] if pet != "none" else null, hero, Callable(self, "_tap"), Callable(self, "_mtap"))
	evs.clear(); msgs.clear()
	p = w.player
	rng = PyRandom.new(seed_v ^ 0x5C8)
	p.level = 6 + (seed_v % 7) * 2; w.refresh_stats(); p.hp = p.max_hp
	for k in ["popper", "fireworks", "popper", "tonic", "brew", "sock", "mug", "remote", "trophy", "pan", "jersey"]:
		if w.inventory.size() < 16:
			w.inventory.append(k)
	w.gold += 300
	var i0 := 0
	for t in ["bronze", "bronze", "bronze", "bronze", "silver", "silver", "silver", "gold"]:
		w.add_box(t, "r%d" % i0)
		i0 += 1
	if seed_v % 5 == 0:
		for kv in [["tinkering", 8], ["power_napping", 5], ["first_aid", 5], ["lobbing", 5], ["haggling", 5], ["gambling", 5]]:
			w.training.levels[kv[0]] = kv[1]
	if seed_v % 3 != 0:
		if first_idx(["jersey"]) >= 0:
			act(-1, "equip", w.use_item(first_idx(["jersey"])))
		act(-1, "choose_class", w.choose_class(race, cls))
	dump(-1, "setup", null)
	for n in range(steps):
		if w.state != "playing":
			break
		if w.pending_choice:
			act(n, "choose_class", w.choose_class(race, cls))
		if w.pending_offer != null:
			if rng.random() < 0.5:
				act(n, "accept", w.accept_contract())
			else:
				act(n, "decline", w.decline_contract())
		if p.stat_points > 0 and rng.random() < 0.3:
			act(n, "spend", w.spend_point(ATTRS[rng.randrange(5)]))
		if n % 20 == 0:
			var kind := (n / 20) % 10
			if kind in [0, 6]:
				safe_block(n)
			elif kind in [2, 7]:
				stairs_block(n)
			elif kind in [1, 9]:
				if not w.monsters.is_empty():
					var m: Monster = w.monsters[rng.randrange(w.monsters.size())]
					put(ring(m.x, m.y, 1)); dump(n, "tp_mon", null)
					if kind == 9:
						act(n, "skill", w.use_skill())
			elif kind == 3:
				for k in ["fireworks", "popper", "tonic", "elixir", "sock", "mug", "trophy", "remote", "cleaver", "vest"]:
					if w.inventory.size() < 16 and rng.random() < 0.5:
						w.inventory.append(k)
				w.add_box(TIERS[rng.randrange(3)], "grant%d" % n)
				if seed_v % 2 == 1 and (n / 200) % 2 == 1:
					w.gold = 0
				else:
					w.gold += 100
				dump(n, "grant", null)
			elif kind == 4:
				if not w.monsters.is_empty():
					var m: Monster = w.monsters[rng.randrange(w.monsters.size())]
					put(ring(m.x, m.y, 2 + rng.randrange(2)))
					if rng.random() < 0.5:
						for o in w.monsters:
							if cheb(o.x, o.y, m.x, m.y) <= 2:
								o.hp = mini(o.hp, 2)
					dump(n, "tp_bomb", null)
					var i := first_idx(["fireworks", "popper"])
					act(n, "bomb", w.use_item(i) if i >= 0 else null)
					act(n, "skill", w.use_skill())
			elif kind == 5:
				var tgt: Monster = null
				for m in w.monsters:
					if m.boss or m.tier != "":
						tgt = m; break
				if tgt != null:
					put(ring(tgt.x, tgt.y, 1)); dump(n, "tp_boss", null)
			elif kind == 8:
				p.hp = maxi(1, p.max_hp / 2)
				if w.pet != null and not w.pet.downed:
					w.pet.hp = 1
				dump(n, "hurt", null)
		if w.state != "playing":
			break
		if seed_v % 4 != 3 and p.hp < p.max_hp / 4:
			p.hp = p.max_hp / 2
		var av := rng.randrange(24)
		var adj: Monster = null
		for m in w.monsters:
			if cheb(m.x, m.y, p.x, p.y) == 1:
				adj = m; break
		var tag: String
		var ok: bool
		if av <= 1 or (av <= 7 and adj == null):
			var d: Vector2i = DungeonFloor.NEIGHBOURS_8[rng.randrange(8)]
			tag = "move"; ok = w.move_player(d.x, d.y)
		elif av <= 7:
			tag = "attack"; ok = w.move_player(adj.x - p.x, adj.y - p.y)
		elif av == 8:
			tag = "wait"; ok = w.wait()
		elif av == 9:
			tag = "pickup"; ok = w.pickup()
		elif av == 10:
			tag = "drop"; ok = w.drop(rng.randrange(maxi(1, w.inventory.size())))
		elif av <= 12:
			tag = "use"; ok = w.use_item(rng.randrange(maxi(1, w.inventory.size())))
		elif av == 13:
			tag = "unequip"; ok = w.unequip(["weapon", "armour"][rng.randrange(2)])
		elif av <= 15:
			tag = "skill"; ok = w.use_skill()
		elif av == 16:
			tag = "rest"; ok = w.rest()
		elif av == 17:
			tag = "craft"; ok = w.craft(rng.randrange(4))
		elif av == 18:
			tag = "buy"; ok = w.shop_buy(SHOPKEYS[rng.randrange(9)])
		elif av == 19:
			tag = "sell"; ok = w.shop_sell(rng.randrange(maxi(1, w.inventory.size())))
		elif av == 20:
			tag = "command"; ok = w.command_pet()
		elif av == 21:
			tag = "revive"; ok = w.revive_pet()
		elif av == 22:
			var r := rng.randrange(3)
			if r == 0:
				tag = "open"; ok = w.open_box(TIERS[rng.randrange(5)])
			elif r == 1:
				tag = "reroll"; ok = w.reroll()
			else:
				tag = "trade"; ok = w.trade_up(TIERS[rng.randrange(5)])
		else:
			tag = "descend"; ok = w.descend()
		dump(n, tag, ok)
		if not ok and w.state == "playing":
			act(n, "wait", w.wait())
	dump(steps, "end", null)
	out.close()
	w.events.tap = Callable()
	w.messages.tap = Callable()
	w = null
	p = null

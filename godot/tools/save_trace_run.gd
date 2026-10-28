class_name SaveTraceRun
extends RefCounted
## Save/load parity harness, Godot side (slice T5). Mirrors scripts/save_trace.py line for line (see its
## docstring for the traces and what they prove); tools/save_trace.gd is the command line and
## tests/test_save_game.gd calls it too. scripts/save_diff.py compares the two sides.
##
## A SaveTraceRun is the chaos player of scripts/chaos_trace.py (its action mix, no tracing): setup(),
## then step(n) once per game step with its own PyRandom stream.

const RACES := ['human', 'elf', 'dwarf', 'hobgoblin', 'bog_troll', 'houseplant']
const CLASSES := ['brawler', 'arcanist', 'analyst', 'alchemist', 'beastmaster', 'hype_man', 'demolitionist', 'quartermaster', 'duellist']
const TIERS := ['bronze', 'silver', 'gold', 'platinum', 'legendary']
const SHOPKEYS := ['tonic', 'brew', 'elixir', 'popper', 'fireworks', 'jersey', 'vest', 'pan', 'cleaver']
const ATTRS := ['str', 'dex', 'con', 'int', 'cha']
const PETS := ['none', 'cat', 'dog', 'budgie', 'mouse']
const GENDERS := ['female', 'male', 'nonbinary']
const BACKS := ['veteran', 'mixologist', 'dog_walker', 'comedian', 'parent', 'tradie', 'category_mgr', 'rideshare']

var seed_value: int
var race: String
var cls: String
var w: World
var rng: PyRandom


## sha256 of the text's UTF-8 bytes, first 16 hex digits.
static func sha(text: String) -> String:
	return text.sha256_text().substr(0, 16)


## The save text of `w` as Python's json.dumps(save.to_dict(w)).
static func save_text(world: World) -> String:
	return SaveGame.dumps(world)


## `world` null builds the seed's own World (as Python's Chaos.__init__).
func _init(seed_v: int, world: World = null) -> void:
	seed_value = seed_v
	var pet: String = PETS[seed_v % 5]
	var hero: Variant = null if seed_v % 4 == 0 else {"name": "H", "gender": GENDERS[seed_v % 3], "backstory": BACKS[(seed_v / 3) % 8]}
	var c := seed_v % 54
	race = RACES[c % 6]
	cls = CLASSES[(c / 6) % 9]
	w = world if world != null else World.new(seed_v, [pet, ""] if pet != "none" else null, hero)
	rng = PyRandom.new(seed_v ^ 0x5C8)


func cheb(ax: int, ay: int, bx: int, by: int) -> int:
	return maxi(absi(ax - bx), absi(ay - by))


func free_tile(x: int, y: int) -> bool:
	var p := w.player
	return (w.floor.walkable(x, y) and not w.floor.is_safe(x, y) and w.monster_at(x, y) == null
			and w.pet_at(x, y) == null and not (x == p.x and y == p.y))


func ring(cx: int, cy: int, d: int) -> Variant:
	for dy in range(-d, d + 1):
		for dx in range(-d, d + 1):
			if maxi(absi(dx), absi(dy)) == d and free_tile(cx + dx, cy + dy):
				return Vector2i(cx + dx, cy + dy)
	return null


func put(xy: Variant) -> void:
	if xy != null:
		w.player.x = xy.x
		w.player.y = xy.y
		w.update_fov()


func to_safe() -> void:
	var p := w.player
	var r := w.floor.safe_room
	for y in range(r.y, r.y + r.h):
		for x in range(r.x, r.x + r.w):
			if w.floor.walkable(x, y) and w.floor.is_safe(x, y) and w.monster_at(x, y) == null and w.pet_at(x, y) == null:
				p.x = x
				p.y = y
				w.update_fov()
				return


func first_idx(keys: Array) -> int:
	for i in range(w.inventory.size()):
		if keys.has(w.inventory[i]):
			return i
	return -1


func setup() -> void:
	var p := w.player
	p.level = 6 + (seed_value % 7) * 2
	w.refresh_stats()
	p.hp = p.max_hp
	for k in ["popper", "fireworks", "popper", "tonic", "brew", "sock", "mug", "remote", "trophy", "pan", "jersey"]:
		if w.inventory.size() < 16:
			w.inventory.append(k)
	w.gold += 300
	var i0 := 0
	for t in ["bronze", "bronze", "bronze", "bronze", "silver", "silver", "silver", "gold"]:
		w.add_box(t, "r%d" % i0)
		i0 += 1
	if seed_value % 5 == 0:
		for kv in [["tinkering", 8], ["power_napping", 5], ["first_aid", 5], ["lobbing", 5], ["haggling", 5], ["gambling", 5]]:
			w.training.levels[kv[0]] = kv[1]
	if seed_value % 3 != 0:
		if first_idx(["jersey"]) >= 0:
			w.use_item(first_idx(["jersey"]))
		w.choose_class(race, cls)


func safe_block() -> void:
	to_safe()
	w.rest()
	w.craft(rng.randrange(4))
	if first_idx(["popper", "fireworks"]) >= 0:
		w.use_item(first_idx(["popper", "fireworks"]))
	w.use_skill()
	w.shop_buy(SHOPKEYS[rng.randrange(9)])
	w.shop_sell(rng.randrange(maxi(1, w.inventory.size())))
	w.revive_pet()
	if not w.boxes.is_empty():
		w.open_box(w.boxes[rng.randrange(w.boxes.size())])
	if rng.random() < 0.6:
		w.reroll()
	w.trade_up(TIERS[rng.randrange(5)])
	if first_idx(["tonic", "brew", "elixir"]) >= 0:
		w.use_item(first_idx(["tonic", "brew", "elixir"]))


func stairs_block() -> void:
	var p := w.player
	var s: Vector2i = w.floor.stairs[rng.randrange(w.floor.stairs.size())]
	if w.monster_at(s.x, s.y) == null and w.pet_at(s.x, s.y) == null:
		p.x = s.x
		p.y = s.y
		w.update_fov()
	if rng.random() < 0.75:
		w.has_key = true
	if not w.descend():
		w.wait()


## One chaos step; returns [tag, ok] of the main action.
func step(n: int) -> Array:
	var p := w.player
	if w.pending_choice:
		w.choose_class(race, cls)
	if w.pending_offer != null:
		if rng.random() < 0.5:
			w.accept_contract()
		else:
			w.decline_contract()
	if p.stat_points > 0 and rng.random() < 0.3:
		w.spend_point(ATTRS[rng.randrange(5)])
	if n % 20 == 0:
		var kind := (n / 20) % 10
		if kind in [0, 6]:
			safe_block()
		elif kind in [2, 7]:
			stairs_block()
		elif kind in [1, 9]:
			if not w.monsters.is_empty():
				var m: Monster = w.monsters[rng.randrange(w.monsters.size())]
				put(ring(m.x, m.y, 1))
				if kind == 9:
					w.use_skill()
		elif kind == 3:
			for k in ["fireworks", "popper", "tonic", "elixir", "sock", "mug", "trophy", "remote", "cleaver", "vest"]:
				if w.inventory.size() < 16 and rng.random() < 0.5:
					w.inventory.append(k)
			w.add_box(TIERS[rng.randrange(3)], "grant%d" % n)
			if seed_value % 2 == 1 and (n / 200) % 2 == 1:
				w.gold = 0
			else:
				w.gold += 100
		elif kind == 4:
			if not w.monsters.is_empty():
				var m: Monster = w.monsters[rng.randrange(w.monsters.size())]
				put(ring(m.x, m.y, 2 + rng.randrange(2)))
				if rng.random() < 0.5:
					for o in w.monsters:
						if cheb(o.x, o.y, m.x, m.y) <= 2:
							o.hp = mini(o.hp, 2)
				var i := first_idx(["fireworks", "popper"])
				if i >= 0:
					w.use_item(i)
				w.use_skill()
		elif kind == 5:
			var tgt: Monster = null
			for m in w.monsters:
				if m.boss or m.tier != "":
					tgt = m
					break
			if tgt != null:
				put(ring(tgt.x, tgt.y, 1))
		elif kind == 8:
			p.hp = maxi(1, p.max_hp / 2)
			if w.pet != null and not w.pet.downed:
				w.pet.hp = 1
	if w.state != "playing":
		return ["over", null]
	if seed_value % 4 != 3 and p.hp < p.max_hp / 4:
		p.hp = p.max_hp / 2
	var av := rng.randrange(24)
	var adj: Monster = null
	for m in w.monsters:
		if cheb(m.x, m.y, p.x, p.y) == 1:
			adj = m
			break
	var tag: String
	var ok: bool
	if av <= 1 or (av <= 7 and adj == null):
		var d: Vector2i = DungeonFloor.NEIGHBOURS_8[rng.randrange(8)]
		tag = "move"
		ok = w.move_player(d.x, d.y)
	elif av <= 7:
		tag = "attack"
		ok = w.move_player(adj.x - p.x, adj.y - p.y)
	elif av == 8:
		tag = "wait"
		ok = w.wait()
	elif av == 9:
		tag = "pickup"
		ok = w.pickup()
	elif av == 10:
		tag = "drop"
		ok = w.drop(rng.randrange(maxi(1, w.inventory.size())))
	elif av <= 12:
		tag = "use"
		ok = w.use_item(rng.randrange(maxi(1, w.inventory.size())))
	elif av == 13:
		tag = "unequip"
		ok = w.unequip(["weapon", "armour"][rng.randrange(2)])
	elif av <= 15:
		tag = "skill"
		ok = w.use_skill()
	elif av == 16:
		tag = "rest"
		ok = w.rest()
	elif av == 17:
		tag = "craft"
		ok = w.craft(rng.randrange(4))
	elif av == 18:
		tag = "buy"
		ok = w.shop_buy(SHOPKEYS[rng.randrange(9)])
	elif av == 19:
		tag = "sell"
		ok = w.shop_sell(rng.randrange(maxi(1, w.inventory.size())))
	elif av == 20:
		tag = "command"
		ok = w.command_pet()
	elif av == 21:
		tag = "revive"
		ok = w.revive_pet()
	elif av == 22:
		var r := rng.randrange(3)
		if r == 0:
			tag = "open"
			ok = w.open_box(TIERS[rng.randrange(5)])
		elif r == 1:
			tag = "reroll"
			ok = w.reroll()
		else:
			tag = "trade"
			ok = w.trade_up(TIERS[rng.randrange(5)])
	else:
		tag = "descend"
		ok = w.descend()
	if not ok and w.state == "playing":
		w.wait()
	return [tag, ok]


## What a load loses (see scripts/save_trace.py drop_unsaved): the Tracker counts the v7 save does not keep.
static func drop_unsaved(world: World) -> void:
	var t := world.achievements.tracker
	t.unarmed_kills = 0
	t.pet_kills = 0
	t.maps = 0
	t.junk_sold = 0
	t.nat1s = 0


## The Chaos player and World at the save point (playing, out of combat; odd seeds in the safe room), or a
## run whose World is over / still in a fight (check `w`).
static func play_to_save_point(seed_v: int) -> SaveTraceRun:
	var c := SaveTraceRun.new(seed_v)
	c.setup()
	var w := c.w
	var before := 60 + (seed_v * 53) % 700
	var n := 0
	while n < before and w.state == "playing":
		c.step(n)
		n += 1
	while w.state == "playing" and w.combat != null and n < before + 400:
		c.step(n)
		n += 1
	if w.state == "playing" and w.combat == null and seed_v % 2 == 1:
		c.to_safe()
	return c


## Continue `w` with a fresh policy stream and write the trace to `path` (see scripts/save_trace.py).
static func continue_run(world: World, seed_v: int, steps: int, path: String) -> void:
	var c := SaveTraceRun.new(seed_v, world)
	c.rng = PyRandom.new(seed_v ^ 0xC0117)
	var out := FileAccess.open(path, FileAccess.WRITE)
	var text := save_text(world) if world.combat == null else ""
	out.store_line(PyJson.dumps(["header", seed_v, world.turn, world.depth, world.state, text.to_utf8_buffer().size(), sha(text)], true, -1, true))
	for n in range(steps):
		if world.state != "playing":
			break
		var r := c.step(n)
		var p := world.player
		var rec: Array = [n, r[0], bool(r[1]) if r[1] != null else null, world.turn, world.depth, world.state, p.hp, p.x, p.y,
				world.gold, sha(TraceFloors.mon_string(world.monsters)), world.rng.state_digest().substr(0, 16),
				world.loot_rng.state_digest().substr(0, 16), world.shop.rng.state_digest().substr(0, 16),
				world.deal_rng.state_digest().substr(0, 16), world.showrunner.rng.state_digest().substr(0, 16),
				world.viewers, world.messages.lines[-1][0] if not world.messages.lines.is_empty() else null,
				world.messages.lines.size()]
		if n % 25 == 24 and world.combat == null:
			rec.append(sha(save_text(world)))
		out.store_line(PyJson.dumps(rec, true, -1, true))
	text = save_text(world) if world.combat == null else ""
	out.store_line(PyJson.dumps(["end", world.turn, world.depth, world.state, text.to_utf8_buffer().size(), sha(text)], true, -1, true))
	out.close()

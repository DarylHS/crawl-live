class_name SaveGame
extends RefCounted
## Save and load a run as JSON (one slot, safe rooms only), crawler/save.py, format version 7.
##
## A loaded World is built normally (so event subscriptions exist) and then has its state
## overwritten, including all RNG states, so play continues exactly where it left off. The
## subsystems (Practice, Achievements, Showrunner, FunFacts, Shop) are never reassigned: load fills
## the ones the new World built, as Python does (port plan section 3, back-references).
##
## The layout, key order and types are Python's, so a save written by either side loads in the other:
## to_dict builds the same keys in the same order, save writes with PyJson.dumps (what json.dumps
## writes: ", " and ": " separators, floats by repr, ensure_ascii), and load reads with PyJsonLoad,
## which keeps ints and floats apart and reads repr floats exactly. Because of that no field needs
## coercing by schema after the parse. Godot's own JSON.stringify and JSON.parse_string are not used.
##
## Files: save(world, path) writes path.tmp (Python's with_suffix(".tmp")) then renames it over path.
## The default path is slot_path(DEFAULT_DIR), "user://saves/slot1.json"; callers with a --save-dir
## option pass slot_path(dir). Failures are push_error plus a return value (save: false; load and
## from_dict: null) where Python raises (mid-combat save, wrong version, unreadable file).

const VERSION: int = 7
## Where the game keeps saves unless told otherwise (the --save-dir option overrides it).
const DEFAULT_DIR: String = "user://saves"
const SLOT_FILE: String = "slot1.json"

## Top-level keys from_dict reads (a missing one is Python's KeyError).
const REQUIRED: Array[String] = [
	"seed", "turn", "state", "death_cause", "depth", "timer", "timer_max", "inventory", "boxes",
	"race", "cls", "pending_choice", "skill_cooldown", "scout_turns", "exit_sealed", "gold",
	"contract", "pending_offer", "floor_stats", "box_log", "hero_name", "gender", "backstory",
	"hype_turns", "riposte", "remote_shop", "has_key", "stairs_open_turn", "box_reasons",
	"last_reason", "stairs_announced", "next_spawn", "spawn_cap", "warnings_left", "was_safe",
	"plant_fed_floor", "practice", "equipment", "floor_items", "last_reveal", "toasts", "messages",
	"player", "pet", "monsters", "floor", "rng", "loot_rng", "deal_rng", "shop", "shop_rng",
	"funfacts", "achievements", "showrunner"]


## The slot file inside `dir` (a --save-dir value or DEFAULT_DIR).
static func slot_path(dir: String = DEFAULT_DIR) -> String:
	return dir.path_join(SLOT_FILE)


## [624 words + index, gauss] as save.py `_rng_state` (gauss is always None for this game).
static func _rng_state(rng: PyRandom) -> Array:
	return [rng.get_state(), null]


static func _set_rng(rng: PyRandom, state: Array) -> void:
	rng.set_state(state[0])


## A 0/1 byte row as a JSON array of ints.
static func _int_row(row: PackedByteArray) -> Array:
	return Array(row)


## A 0/1 byte row as a JSON array of bools (Python's safe and explored grids hold bools).
static func _bool_row(row: PackedByteArray) -> Array:
	var out: Array = []
	out.resize(row.size())
	for i in row.size():
		out[i] = row[i] != 0
	return out


## The whole run as a Dictionary in Python's key order. A fight in progress cannot be saved:
## push_error and an empty Dictionary (Python raises ValueError).
static func to_dict(w: World) -> Dictionary:
	if w.combat != null:
		push_error("SaveGame.to_dict: can't save mid-combat")    # saves are safe-room only, which ends it
		return {}
	var f := w.floor
	var sr := w.showrunner
	var d := {}
	d["version"] = VERSION
	d["seed"] = w.seed
	d["turn"] = w.turn
	d["state"] = w.state
	d["death_cause"] = w.death_cause
	d["depth"] = w.depth
	d["timer"] = w.timer
	d["timer_max"] = w.timer_max
	d["warnings_left"] = w._warnings_left
	d["was_safe"] = w._was_safe
	d["inventory"] = w.inventory
	d["equipment"] = w.equipment
	d["boxes"] = w.boxes
	d["box_reasons"] = w.box_reasons
	d["last_reason"] = w.last_reason
	var items: Array = []
	for k in w.floor_items:
		items.append([k.x, k.y, w.floor_items[k]])
	d["floor_items"] = items
	d["last_reveal"] = w.last_reveal
	d["toasts"] = w.toasts
	d["messages"] = w.messages.lines.duplicate()
	d["race"] = w.race
	d["cls"] = w.cls
	d["pending_choice"] = w.pending_choice
	d["skill_cooldown"] = w.skill_cooldown
	d["scout_turns"] = w.scout_turns
	d["exit_sealed"] = w.exit_sealed
	d["has_key"] = w.has_key
	d["stairs_open_turn"] = w.stairs_open_turn
	d["stairs_announced"] = w._stairs_announced
	d["next_spawn"] = w._next_spawn
	d["spawn_cap"] = w._spawn_cap
	d["gold"] = w.gold
	d["contract"] = w.contract
	d["pending_offer"] = w.pending_offer
	d["hero_name"] = w.hero_name
	d["gender"] = w.gender
	d["backstory"] = w.backstory
	d["hype_turns"] = w.hype_turns
	d["practice"] = w.training.to_dict()
	d["riposte"] = w.riposte
	d["remote_shop"] = w.remote_shop
	d["plant_fed_floor"] = w._plant_fed_floor
	d["floor_stats"] = w.floor_stats
	d["box_log"] = w.box_log
	d["shop"] = w.shop.to_dict()
	d["shop_rng"] = _rng_state(w.shop.rng)
	d["deal_rng"] = _rng_state(w.deal_rng)
	var said: Array = w.funfacts.said.keys()
	said.sort()
	d["funfacts"] = {"last_turn": w.funfacts.last_turn, "said": said,
			"miss_streak": w.funfacts.miss_streak, "streak_chance": w.funfacts.streak_chance,
			"drought": w.funfacts.drought}
	d["player"] = w.player.to_dict()
	d["pet"] = w.pet.to_dict() if w.pet != null else null
	var mons: Array = []
	for m in w.monsters:
		mons.append(m.to_dict())
	d["monsters"] = mons
	var tiles: Array = []
	var safe: Array = []
	var explored: Array = []
	for y in f.height:
		tiles.append(_int_row(f.tiles[y]))
		safe.append(_bool_row(f.safe[y]))
		explored.append(_bool_row(f.explored[y]))
	var rooms: Array = []
	for r in f.rooms:
		rooms.append({"x": r.x, "y": r.y, "w": r.w, "h": r.h})
	var stairs: Array = []
	for s in f.stairs:
		stairs.append([s.x, s.y])
	var furniture: Array = []
	for k in f.furniture:
		furniture.append([k.x, k.y, f.furniture[k]])
	var door: Variant = null
	if f.safe_door != null:
		door = [f.safe_door.x, f.safe_door.y]
	d["floor"] = {"width": f.width, "height": f.height, "depth": f.depth, "tiles": tiles,
			"safe": safe, "explored": explored, "rooms": rooms,
			"start_room": f.rooms.find(f.start_room), "safe_room": f.rooms.find(f.safe_room),
			"stairs": stairs, "safe_door": door, "furniture": furniture}
	d["rng"] = _rng_state(w.rng)
	d["loot_rng"] = _rng_state(w.loot_rng)
	var equipped: Array = w.achievements.tracker.equipped.keys()
	equipped.sort()
	d["achievements"] = {"unlocked": w.achievements.unlocked,
			"kills": w.achievements.tracker.kills, "pickups": w.achievements.tracker.pickups,
			"equipped": equipped}
	d["showrunner"] = {"viewers": sr.viewers, "peak": sr.peak, "history": sr.history,
			"kill_turns": sr._kill_turns, "last_fun": sr._last_fun, "gift_idx": sr._gift_idx,
			"last_flee_quip": sr._last_flee_quip, "samples": sr.samples, "rng": _rng_state(sr.rng)}
	return d


## Build a World from a to_dict() Dictionary (typed as PyJsonLoad gives it: ints are ints). Returns
## null on an unsupported version or a missing key (Python raises ValueError or KeyError).
static func from_dict(d: Dictionary) -> World:
	if d.get("version") != VERSION or typeof(d.get("version")) != TYPE_INT:
		push_error("SaveGame.from_dict: Unsupported save version %s" % str(d.get("version")))
		return null
	for key in REQUIRED:
		if not d.has(key):
			push_error("SaveGame.from_dict: missing key '%s'" % key)
			return null
	var w := World.new(d["seed"])
	# Rebuild from scratch: drop anything the constructor's first floor produced.
	w.messages.lines.clear()
	for key in ["turn", "state", "death_cause", "depth", "timer", "timer_max", "inventory",
			"boxes", "race", "cls", "pending_choice", "skill_cooldown", "scout_turns",
			"exit_sealed", "gold", "contract", "pending_offer", "floor_stats", "box_log",
			"hero_name", "gender", "backstory", "hype_turns", "riposte", "remote_shop",
			"has_key", "stairs_open_turn", "box_reasons", "last_reason"]:
		w.set(key, d[key])
	w._stairs_announced = d["stairs_announced"]
	w._next_spawn = d["next_spawn"]
	w._spawn_cap = d["spawn_cap"]
	w._warnings_left = d["warnings_left"]
	w._was_safe = d["was_safe"]
	w._plant_fed_floor = d["plant_fed_floor"]
	w.training.load(d["practice"])
	w.equipment = d["equipment"]
	w.floor_items = {}
	for e in d["floor_items"]:
		w.floor_items[Vector2i(e[0], e[1])] = e[2]
	w.last_reveal = d["last_reveal"] if PyMath.truthy(d["last_reveal"]) else null
	w.toasts = d["toasts"]
	for m in d["messages"]:
		w.messages.add(m[0], m[1])
	w.player = Player.from_dict(d["player"])
	w.pet = Pet.from_dict(d["pet"]) if PyMath.truthy(d["pet"]) else null
	w.monsters = []
	for m in d["monsters"]:
		w.monsters.append(Monster.from_dict(m))

	var fd: Dictionary = d["floor"]
	var f := DungeonFloor.new(fd["width"], fd["height"], fd["depth"])
	for y in f.height:
		f.tiles[y] = PackedByteArray(fd["tiles"][y])
		var safe_row := PackedByteArray()
		var explored_row := PackedByteArray()
		safe_row.resize(f.width)
		explored_row.resize(f.width)
		for x in f.width:
			safe_row[x] = 1 if fd["safe"][y][x] else 0
			explored_row[x] = 1 if fd["explored"][y][x] else 0
		f.safe[y] = safe_row
		f.explored[y] = explored_row
	for r in fd["rooms"]:
		f.rooms.append(DungeonRoom.new(r["x"], r["y"], r["w"], r["h"]))
	f.start_room = f.rooms[fd["start_room"]]
	f.safe_room = f.rooms[fd["safe_room"]]
	for s in fd["stairs"]:
		f.stairs.append(Vector2i(s[0], s[1]))
	if fd["safe_door"] != null:    # every generated floor has a door; Python's tuple(None) would raise
		f.safe_door = Vector2i(fd["safe_door"][0], fd["safe_door"][1])
	f.furniture = {}
	for e in fd["furniture"]:
		f.furniture[Vector2i(e[0], e[1])] = e[2]
	w.floor = f

	_set_rng(w.rng, d["rng"])
	_set_rng(w.loot_rng, d["loot_rng"])
	_set_rng(w.deal_rng, d["deal_rng"])
	w.shop.load(d["shop"])
	_set_rng(w.shop.rng, d["shop_rng"])
	var ff := w.funfacts
	var f2: Dictionary = d["funfacts"]
	ff.last_turn = f2["last_turn"]
	ff.said = {}
	for k in f2["said"]:
		ff.said[k] = true
	ff.miss_streak = f2["miss_streak"]
	ff.streak_chance = f2["streak_chance"]
	ff.drought = f2["drought"]
	var a: Dictionary = d["achievements"]
	w.achievements.unlocked = a["unlocked"]
	var t := w.achievements.tracker
	t.kills = a["kills"]
	t.pickups = a["pickups"]
	t.equipped = {}
	for k in a["equipped"]:
		t.equipped[k] = true
	var s: Dictionary = d["showrunner"]
	var sr := w.showrunner
	sr.viewers = s["viewers"]
	sr.peak = s["peak"]
	sr.history = s["history"]
	sr._kill_turns = s["kill_turns"]
	sr._last_fun = s["last_fun"]
	sr._gift_idx = s["gift_idx"]
	sr._last_flee_quip = s["last_flee_quip"]
	sr.samples = s["samples"]
	_set_rng(sr.rng, s["rng"])
	w.update_fov()
	return w


## The save as text, exactly what Python's json.dumps(to_dict(world)) writes ("" if it cannot be saved).
static func dumps(w: World) -> String:
	if w.combat != null:
		push_error("SaveGame.dumps: can't save mid-combat")
		return ""
	return PyJson.dumps(to_dict(w))


## Write the save atomically (path.tmp, then rename over path), creating directories. Returns false
## (and writes nothing) mid-combat or when the file cannot be written.
static func save(world: World, path: String = "") -> bool:
	if world.combat != null:
		push_error("SaveGame.save: can't save mid-combat")
		return false
	if path == "":
		path = slot_path()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var tmp := path.get_basename() + ".tmp"
	var fa := FileAccess.open(tmp, FileAccess.WRITE)
	if fa == null:
		push_error("SaveGame.save: cannot write %s (error %d)" % [tmp, FileAccess.get_open_error()])
		return false
	fa.store_string(dumps(world))
	fa.close()
	var err := DirAccess.rename_absolute(tmp, path)     # a crash mid-write never corrupts the slot
	if err != OK:
		push_error("SaveGame.save: cannot rename %s to %s (error %d)" % [tmp, path, err])
		return false
	return true


## Read a save file. Returns null (with a push_error) when it is missing, not JSON or not a v7 save.
static func load(path: String = "") -> World:
	if path == "":
		path = slot_path()
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		push_error("SaveGame.load: cannot read %s (error %d)" % [path, FileAccess.get_open_error()])
		return null
	var text := fa.get_as_text()
	fa.close()
	return from_text(text)


## Build a World from save text (json.loads then from_dict).
static func from_text(text: String) -> World:
	var data: Variant = PyJsonLoad.parse(text)
	if PyJsonLoad.error != "" or not data is Dictionary:
		push_error("SaveGame.from_text: not a save (%s)" % PyJsonLoad.error)
		return null
	return from_dict(data)


static func has_save(path: String = "") -> bool:
	if path == "":
		path = slot_path()
	return FileAccess.file_exists(path)

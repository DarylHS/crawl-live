class_name TraceFloors
extends RefCounted
## Floor-only parity trace records (port plan 6.1/6.2; normative: scripts/py_trace.py docstring and
## functions floor_sections, dump_floor, run_floors). Pure generate_floor mode: one PyRandom(seed),
## generate_floor(rng, d) for d in 1..floors. Shared by tools/trace.gd and tests/test_dungeon_parity.gd.
##
## Every number that goes into a hash input is a decimal int; the records are plain Dictionaries
## written with PyJson.dumps.

const TRACE_VERSION := 1


static func sha256_hex(text: String) -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(text.to_utf8_buffer())
	return ctx.finish().hex_encode()


static func h16(text: String) -> String:
	return sha256_hex(text).substr(0, 16)


## sha256 of godot/data/manifest.json bytes (the trace header's content_sha).
static func content_sha() -> String:
	var bytes := FileAccess.get_file_as_bytes("res://data/manifest.json")
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(bytes)
	return ctx.finish().hex_encode()


## Rows as strings of digits (tiles) or 0/1 (safe).
static func row_strings(grid: Array) -> Array:
	var out: Array = []
	for row in grid:
		var b: PackedByteArray = (row as PackedByteArray).duplicate()
		for k in b.size():
			b[k] += 48   # single digits 0-3 / 0-1 only
		out.append(b.get_string_from_ascii())
	return out


## Fingerprint sections: tiles, safe, rooms, stairs, furniture, safe_door, and, when `items` is not
## null (World mode, py_trace.floor_sections), floor_items ("x,y:key,key;..." in insertion order)
## and monsters (mon_string).
static func floor_sections(fl: DungeonFloor, items: Variant = null, monsters: Array = []) -> Array:
	var rooms := PackedStringArray()
	for r in fl.rooms:
		rooms.append("%d,%d,%d,%d" % [r.x, r.y, r.w, r.h])
	var stairs := PackedStringArray()
	for s in fl.stairs:
		stairs.append("%d,%d" % [s.x, s.y])
	var furn := PackedStringArray()
	for p in fl.furniture:
		furn.append("%d,%d,%s" % [p.x, p.y, fl.furniture[p]])
	var door := "-"
	if fl.safe_door != null:
		door = "%d,%d" % [fl.safe_door.x, fl.safe_door.y]
	var secs: Array = ["".join(row_strings(fl.tiles)), "".join(row_strings(fl.safe)), ";".join(rooms),
			";".join(stairs), ";".join(furn), door]
	if items != null:
		var its := PackedStringArray()
		for p in items:
			its.append("%d,%d:%s" % [p.x, p.y, ",".join(PackedStringArray(items[p]))])
		secs.append(";".join(its))
		secs.append(mon_string(monsters))
	return secs


static func floor_fp(fl: DungeonFloor, items: Variant = null, monsters: Array = []) -> String:
	return h16("#".join(floor_sections(fl, items, monsters)))


## key:x:y:hp:max_hp:alerted:unseen_turns:stunned:phase:dmg_bonus per monster, joined by "|"
## (booleans as 1/0), as py_trace.mon_string.
static func mon_string(monsters: Array) -> String:
	var parts := PackedStringArray()
	for m in monsters:
		parts.append("%s:%d:%d:%d:%d:%d:%d:%d:%d:%d" % [m.key, m.x, m.y, m.hp, m.max_hp,
				1 if m.alerted else 0, m.unseen_turns, m.stunned, m.phase, m.dmg_bonus])
	return "|".join(parts)


## Dungeon-only dump fields, in py_trace.dump_floor order.
static func dump_floor(fl: DungeonFloor) -> Dictionary:
	var rooms: Array = []
	for r in fl.rooms:
		rooms.append([r.x, r.y, r.w, r.h])
	var sc := fl.start_room.centre()
	var sr := fl.safe_room
	var stairs: Array = []
	for s in fl.stairs:
		stairs.append([s.x, s.y])
	var furn: Array = []
	for p in fl.furniture:
		furn.append([p.x, p.y, fl.furniture[p]])
	var door: Variant = null
	if fl.safe_door != null:
		door = [fl.safe_door.x, fl.safe_door.y]
	return {"tiles": row_strings(fl.tiles), "safe": row_strings(fl.safe), "rooms": rooms,
			"start": [sc.x, sc.y], "safe_room": [sr.x, sr.y, sr.w, sr.h], "safe_door": door,
			"stairs": stairs, "furniture": furn}


static func header(seed_value: int) -> Dictionary:
	return {"k": "header", "impl": "godot", "trace_version": TRACE_VERSION, "seed": seed_value,
			"policy": null, "steps": 0, "pet": null, "hero": null, "content_sha": content_sha(),
			"mode": "floors"}


## Header plus one floor record per depth, as Dictionaries (key order as in py_trace.run_floors).
static func run_floors(seed_value: int, floors: int) -> Array:
	var out: Array = [header(seed_value)]
	var rng := PyRandom.new(seed_value)
	for d in range(1, floors + 1):
		var fl := Dungeon.generate_floor(rng, d)
		var rec := {"k": "floor", "depth": d, "fp": floor_fp(fl), "words": rng.words_used,
				"rs": [rng.state_digest().substr(0, 16)]}
		rec.merge(dump_floor(fl))
		out.append(rec)
	return out


static func to_lines(records: Array) -> String:
	var s := ""
	for r in records:
		s += PyJson.dumps(r, false, -1, true) + "\n"
	return s


# --- World mode (--floor-only --spawns): World(seed), then new_floor(2..floors) ----------------

## Receives the world's events through World's `tracer` seam and records one floor record at each
## floor_start, as py_trace.Tracer.write_floor does. Holds the world weakly (the world's event bus
## holds this object's tap).
class WorldSink extends RefCounted:
	var records: Array = []
	var _world_ref: WeakRef

	func attach_world(w: Object) -> void:
		_world_ref = weakref(w)

	func on_event(event_name: String, _data: Dictionary) -> void:
		if event_name != "floor_start" or _world_ref == null:
			return
		var w: World = _world_ref.get_ref()
		if w == null:
			return
		records.append(TraceFloors.world_floor_record(w))


## Words used so far by the five streams: main, loot, shop, deal, show.
static func stream_words(w: World) -> Array:
	return [w.rng.words_used, w.loot_rng.words_used, w.shop.rng.words_used, w.deal_rng.words_used,
			w.showrunner.rng.words_used]


## state_digest()[:16] of the five streams, in the same order.
static func stream_digests(w: World) -> Array:
	var out: Array = []
	for r in [w.rng, w.loot_rng, w.shop.rng, w.deal_rng, w.showrunner.rng]:
		out.append(r.state_digest().substr(0, 16))
	return out


## The floor record in World mode (py_trace.Tracer.write_floor with detail=True), key order as Python.
static func world_floor_record(w: World) -> Dictionary:
	var rec := {"k": "floor", "depth": w.depth, "fp": floor_fp(w.floor, w.floor_items, w.monsters),
			"rs": stream_digests(w)}
	rec.merge(dump_floor(w.floor))
	rec["player"] = [w.player.x, w.player.y]
	rec["timer"] = [w.timer, w.timer_max]
	rec["words"] = stream_words(w)
	var mons: Array = []
	for m in w.monsters:
		mons.append([m.key, m.x, m.y, m.hp, m.max_hp, m.alerted, m.unseen_turns, m.stunned, m.phase,
				m.dmg_bonus, m.tier, m.boss])
	rec["monsters"] = mons
	var items: Array = []
	for p in w.floor_items:
		items.append([p.x, p.y, (w.floor_items[p] as Array).duplicate()])
	rec["items"] = items
	return rec


## Header plus one floor record per depth: World(seed) builds floor 1, then new_floor(2..floors).
## `pet` is a species key ("" for none), `hero` a Dictionary or null (as py_trace --pet / --hero).
static func run_floors_world(seed_value: int, floors: int, pet: String = "", hero: Variant = null) -> Array:
	var sink := WorldSink.new()
	var pet_arg: Variant = [pet, ""] if pet != "" else null
	var w := World.new(seed_value, pet_arg, hero, Callable(sink, "on_event"), Callable(), sink)
	for d in range(2, floors + 1):
		w.new_floor(d)
	w.events.tap = Callable()   # the tap holds the sink; drop it so nothing outlives the call
	var h := header(seed_value)
	h["mode"] = "floors_world"
	h["pet"] = pet if pet != "" else null
	h["hero"] = hero
	return [h] + sink.records

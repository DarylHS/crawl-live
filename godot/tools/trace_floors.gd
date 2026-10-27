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


## Fingerprint sections (without items/monsters): tiles, safe, rooms, stairs, furniture, safe_door.
static func floor_sections(fl: DungeonFloor) -> Array:
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
	return ["".join(row_strings(fl.tiles)), "".join(row_strings(fl.safe)), ";".join(rooms),
			";".join(stairs), ";".join(furn), door]


static func floor_fp(fl: DungeonFloor) -> String:
	return h16("#".join(floor_sections(fl)))


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
		s += PyJson.dumps(r, false) + "\n"
	return s

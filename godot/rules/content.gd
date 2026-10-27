class_name Content
extends RefCounted
## Static loader for the generated game content in res://data/*.json (port plan section 4).
##
## Content.table("monsters") loads res://data/monsters.json once and caches it. JSON numbers
## parse as float in Godot, so every number is coerced to int except the leaves listed in
## manifest.json "float_paths" (RFC 6901 pointers relative to the document root, e.g.
## "/mixologist/potion_mult"), which stay float. Dictionaries keep Python insertion order.
##
## The returned Dictionaries and Arrays are the live cache: tests that patch content edit them
## in place and must restore them (or call Content.reload()). Never hand-edit data/*.json; change
## scripts/export_content.py and regenerate.
##
## File IO is allowed here (and only in save/settings/telemetry): rules otherwise stay pure.

const DATA_DIR := "res://data/"

static var _tables: Dictionary = {}
static var _manifest: Dictionary = {}


## Drop every cached table (tests that patched content call this to get a clean copy).
static func reload() -> void:
	_tables = {}
	_manifest = {}


## manifest.json: {"generator", "python", "source_commit", "files": {file: {sha256, sources, float_paths}}}.
static func manifest() -> Dictionary:
	if _manifest.is_empty():
		var m = _parse(DATA_DIR + "manifest.json")
		if m is Dictionary:
			_manifest = _coerce_ints(m)
	return _manifest


## Table names (file names without .json), in manifest order, manifest excluded.
static func names() -> PackedStringArray:
	var out := PackedStringArray()
	for f in manifest().get("files", {}):
		out.append(String(f).trim_suffix(".json"))
	return out


## One table by file name without extension: "monsters", "items", "config", ... Returns null
## (and push_error) if the file is missing or invalid.
static func table(table_name: String) -> Variant:
	if _tables.has(table_name):
		return _tables[table_name]
	var file := table_name + ".json"
	var raw = _parse(DATA_DIR + file)
	if raw == null:
		return null
	var info: Dictionary = manifest().get("files", {}).get(file, {})
	var floats := {}
	for p in info.get("float_paths", []):
		floats[p] = true
	var data = _coerce_ints(raw) if floats.is_empty() else _coerce(raw, floats, "")
	_tables[table_name] = data
	return data


## Sections of config.json: Content.config("ai"), Content.config("config"), ...
static func config(section: String) -> Dictionary:
	return table("config")[section]


static func monster(key: String) -> Dictionary:
	return table("monsters")[key]


static func pet(species: String) -> Dictionary:
	return table("pets")[species]


static func item(key: String) -> Dictionary:
	return table("items")["items"][key]


static func fists() -> Dictionary:
	return table("items")["fists"]


## Headliner row for a floor (JSON keys are strings).
static func boss(depth: int) -> Dictionary:
	return table("bosses")[str(depth)]


static func box(tier: String) -> Dictionary:
	return table("loot_boxes")[tier]


static func race(key: String) -> Dictionary:
	return table("races")[key]


## Class row ("class" is a GDScript keyword).
static func klass(key: String) -> Dictionary:
	return table("classes")[key]


static func skill(key: String) -> Dictionary:
	return table("skills")[key]


static func backstory(key: String) -> Dictionary:
	return table("backstories")[key]


static func gender(key: String) -> Dictionary:
	return table("genders")[key]


## True when every data file still hashes to the sha256 recorded in manifest.json.
static func verify() -> bool:
	var ok := true
	for f in manifest().get("files", {}):
		var ctx := HashingContext.new()
		ctx.start(HashingContext.HASH_SHA256)
		ctx.update(FileAccess.get_file_as_bytes(DATA_DIR + f))
		if ctx.finish().hex_encode() != manifest()["files"][f]["sha256"]:
			push_error("Content: %s does not match manifest.json (regenerate with scripts/export_content.py)" % f)
			ok = false
	return ok


static func _parse(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("Content: missing %s (run scripts/export_content.py)" % path)
		return null
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		push_error("Content: %s line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data


## Every number becomes int (no float_paths in this document). In place.
static func _coerce_ints(node: Variant) -> Variant:
	match typeof(node):
		TYPE_FLOAT:
			if node != floorf(node):
				push_error("Content: non-integral number %s where an int is expected" % node)
			return int(node)
		TYPE_DICTIONARY:
			for k in node:
				node[k] = _coerce_ints(node[k])
		TYPE_ARRAY:
			for i in node.size():
				node[i] = _coerce_ints(node[i])
	return node


## Numbers become int unless their JSON pointer is in `floats`, where they become float. In place.
static func _coerce(node: Variant, floats: Dictionary, path: String) -> Variant:
	match typeof(node):
		TYPE_FLOAT, TYPE_INT:
			if floats.has(path):
				return float(node)
			if typeof(node) == TYPE_FLOAT and node != floorf(node):
				push_error("Content: non-integral number %s at %s is not in float_paths" % [node, path])
			return int(node)
		TYPE_DICTIONARY:
			for k in node:
				var p := path + "/" + String(k).replace("~", "~0").replace("/", "~1")
				node[k] = _coerce(node[k], floats, p)
		TYPE_ARRAY:
			for i in node.size():
				node[i] = _coerce(node[i], floats, path + "/" + str(i))
	return node

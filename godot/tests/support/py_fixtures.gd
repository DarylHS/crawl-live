class_name PyFixtures
extends RefCounted
## Loads and decodes the Python fixtures made by scripts/make_fixtures.py (path in the FIXTURES
## environment variable, set by scripts/gd_test.sh).
##
## Encoding: None "n:", bool "b:1"/"b:0", int "i:<dec>", float "f:<16 hex digits of the IEEE-754
## bits>", str "s:<text>", list {"l": [...]}, dict {"d": [[key, value], ...]} (insertion order).

static var _cache: Dictionary = {}
static var _loaded := false
static var _error := ""


## The whole fixture document, or {} when FIXTURES is not set (tests then skip with a pending).
static func data() -> Dictionary:
	if not _loaded:
		_loaded = true
		var path := OS.get_environment("FIXTURES")
		if path == "":
			_error = "FIXTURES is not set (run through scripts/gd_test.sh)"
		elif not FileAccess.file_exists(path):
			_error = "FIXTURES file does not exist: " + path
		else:
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_cache = parsed
			else:
				_error = "FIXTURES file does not parse as a JSON object: " + path
	return _cache


static func available() -> bool:
	return not data().is_empty()


## Call at the top of every fixture-backed test: fails the test (with the path and the reason) when
## FIXTURES is unset, missing or not valid JSON, and returns false so the test can return.
static func require(test: GutTest) -> bool:
	data()
	if _error != "":
		test.fail_test("fixtures unavailable: " + _error)
		return false
	return true


static func decode(node: Variant) -> Variant:
	if node is Dictionary:
		if node.has("l"):
			var a: Array = []
			for e in node["l"]:
				a.append(decode(e))
			return a
		var d := {}
		for kv in node["d"]:
			d[decode(kv[0])] = decode(kv[1])
		return d
	var t: String = node
	match t.substr(0, 2):
		"n:":
			return null
		"b:":
			return t == "b:1"
		"i:":
			return t.substr(2).to_int()
		"f:":
			return float_from_hex(t.substr(2))
		"s:":
			return t.substr(2)
	push_error("PyFixtures.decode: bad node %s" % t)
	return null


static func float_from_hex(h: String) -> float:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_u32(4, h.substr(0, 8).hex_to_int())
	bytes.encode_u32(0, h.substr(8, 8).hex_to_int())
	return bytes.decode_double(0)


## "f:<hex>" of a double: compares NaN and -0.0 correctly where == cannot.
static func float_bits(x: float) -> String:
	var bytes := PackedByteArray()
	bytes.resize(8)
	bytes.encode_double(0, x)
	var hex := ""
	for i in range(7, -1, -1):
		hex += "%02x" % bytes[i]
	return "f:" + hex


## Rows of one section ("math", "round") decoded cell by cell; name "" for top-level lists ("json").
static func rows(group: String, name: String = "") -> Array:
	var out: Array = []
	var src: Array = data()[group][name] if name != "" else data()[group]
	for row in src:
		var r: Array = []
		for cell in row:
			r.append(decode(cell))
		out.append(r)
	return out

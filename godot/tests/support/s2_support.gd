class_name S2Support
extends RefCounted
## Helpers for the S2 tests (dice, attributes, entities, combat): the loader for the S2
## Python fixtures (scripts/make_fixtures_s2.py, path in FIXTURES_S2).

static var _doc: Dictionary = {}
static var _loaded := false
static var _error := ""


## The S2 fixture document, or {} (with an error remembered) when FIXTURES_S2 is unset or bad.
static func doc() -> Dictionary:
	if not _loaded:
		_loaded = true
		var path := OS.get_environment("FIXTURES_S2")
		if path == "":
			_error = "FIXTURES_S2 is not set (run through scripts/gd_test.sh)"
		elif not FileAccess.file_exists(path):
			_error = "FIXTURES_S2 file does not exist: " + path
		else:
			var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_doc = parsed
			else:
				_error = "FIXTURES_S2 does not parse as a JSON object: " + path
	return _doc


## Fails the test and returns false when the fixtures are unavailable.
static func require(test: GutTest) -> bool:
	doc()
	if _error != "":
		test.fail_test("fixtures unavailable: " + _error)
		return false
	return true


## Rows of tables[name], every cell decoded.
static func rows(table_name: String) -> Array:
	var out: Array = []
	for row in doc()["tables"][table_name]:
		var r: Array = []
		for cell in row:
			r.append(PyFixtures.decode(cell))
		out.append(r)
	return out


## Build an entity from a fixture spec [kind, key, [[field, value], ...]].
static func build(spec: Array) -> Entity:
	var e: Entity
	match spec[0]:
		"player":
			e = Entities.new_player(0, 0)
		"monster":
			e = Entities.spawn_monster(spec[1], 0, 0)
		_:
			e = Entities.new_pet(spec[1], "", 0, 0)
	for kv in spec[2]:
		e.set(kv[0], kv[1])
	return e

class_name S4Support
extends RefCounted
## Helpers for the S4 tests (encounter, bosses, items, loot, crafting, contracts, shop): the loader
## for the S4 Python fixtures (scripts/make_fixtures_s4.py, path in FIXTURES_S4) and a duck-typed
## stand-in for the World members that Contracts reads (World itself arrives in slice S6).

static var _doc: Dictionary = {}
static var _loaded := false
static var _error := ""


## The members of World that Contracts.effect / preview read (see the SEAM note in contracts.gd).
## Slice S6 deletes this stand-in and builds a real World instead.
class FakeWorld extends RefCounted:
	var contract: Variant = null
	var timer: int = 0
	var floor_stats: Array = []
	var monsters: Array = []
	var player: Entity

	func _init(p_contract: Variant, p_timer: int, p_stats: Array, p_monsters: Array, p_player: Entity) -> void:
		contract = p_contract
		timer = p_timer
		floor_stats = p_stats
		monsters = p_monsters
		player = p_player

	## World.timer_text(turns=None): "<h>h <mm>m".
	func timer_text(turns: Variant = null) -> String:
		var t: int = timer if turns == null else turns
		return "%dh %sm" % [PyMath.floordiv(t, 60), PyFmt.zero_pad(PyMath.mod(t, 60), 2)]


## The S4 fixture document, or {} (with an error remembered) when FIXTURES_S4 is unset or bad.
static func doc() -> Dictionary:
	if not _loaded:
		_loaded = true
		var path := OS.get_environment("FIXTURES_S4")
		if path == "":
			_error = "FIXTURES_S4 is not set (run through scripts/gd_test.sh)"
		elif not FileAccess.file_exists(path):
			_error = "FIXTURES_S4 file does not exist: " + path
		else:
			var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
			if parsed is Dictionary:
				_doc = parsed
			else:
				_error = "FIXTURES_S4 does not parse as a JSON object: " + path
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

extends TestCase
## Parity of the `walk` policy run traces with Python (port plan 6.4, slice S7). scripts/gd_test.sh
## sets WALK_TRACES to a directory with walk_<seed>.jsonl from
## `py_trace.py --seeds 0-9 --policy walk --steps 500` and WALK_COMBOS to one with <name>.jsonl for
## the pet and hero combinations below. The full acceptance run (seeds 0-49, four pets, heroes) is
## tools/trace.gd + scripts/parity_diff.py --dirs --scope core.
##
## Compared at core scope, as parity_diff.py does: msg records, the `i` counter of ev records, the
## events of the stand-in systems (achievement, box_gained, viewers_gained, sponsor_gift, fun_fact),
## showmanship practice_level events and the many_at_3 field of the others,
## viewers in turn records and the show stream (index 4 of r, rs and words) are dropped from both
## sides. T1 to T3 replace the stand-ins and this test then compares everything.
## A missing reference directory fails the test (run through scripts/gd_test.sh).

const STEPS := 500
const SKIP_EVENTS := ["achievement", "box_gained", "viewers_gained", "sponsor_gift", "fun_fact"]

## [name, seed, pet, hero "GENDER:BACKSTORY"]; mirrors the combo list in scripts/gd_test.sh.
const COMBOS := [
	["cat_tradie_3", 3, "cat", "female:tradie"],
	["cat_none_30", 30, "cat", ":"],
	["dog_rideshare_8", 8, "dog", "male:rideshare"],
	["dog_veteran_41", 41, "dog", "female:veteran"],
	["budgie_dog_walker_12", 12, "budgie", "male:dog_walker"],
	["budgie_none_27", 27, "budgie", ":"],
	["mouse_comedian_21", 21, "mouse", "female:comedian"],
	["mouse_parent_36", 36, "mouse", "male:parent"],
]


func _need(var_name: String) -> String:
	var v := OS.get_environment(var_name)
	if v == "":
		fail_test("%s is not set (run through scripts/gd_test.sh)" % var_name)
	return v


## The record with the fields core scope ignores removed, or an empty Dictionary to skip it.
static func _core(rec: Dictionary) -> Dictionary:
	var k: String = rec["k"]
	if k == "msg":
		return {}
	if k == "ev" and SKIP_EVENTS.has(rec["e"]):
		return {}
	if k == "ev" and rec["e"] == "practice_level":
		if rec["p"]["skill"] == "showmanship":
			return {}
		rec["p"].erase("many_at_3")
	if k == "ev":
		rec.erase("i")
	if k == "turn":
		rec.erase("viewers")
	for key in ["r", "rs", "words"]:
		if rec.has(key) and (rec[key] as Array).size() >= 5:
			var a: Array = rec[key]
			rec[key] = a.slice(0, 4) + a.slice(5)
	return rec


static func _read(path: String) -> Array:
	var out: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		var rec: Dictionary = JSON.parse_string(line)
		var core := _core(rec)
		if not core.is_empty():
			out.append(core)
	return out


## Compares a Godot trace with the Python file; returns "" when identical at core scope.
func _walk_diff(py_path: String, seed_value: int, pet: String, hero: Variant) -> String:
	if not FileAccess.file_exists(py_path):
		return "missing " + py_path
	var py := _read(py_path)
	var mine: Array = []
	for rec in TraceRun.run_trace(seed_value, "walk", STEPS, pet, hero):
		# through JSON text so both sides carry the same number types as the Python file
		var core := _core(JSON.parse_string(PyJson.dumps(rec, false)))
		if not core.is_empty():
			mine.append(core)
	if mine.size() != py.size():
		return "record count %d vs Python %d" % [mine.size(), py.size()]
	for i in mine.size():
		var got: Dictionary = mine[i]
		var want: Dictionary = py[i]
		if want["k"] == "header":
			want["impl"] = got["impl"]
		var diff := TestCase.strict_diff(got, want)
		if diff != "":
			return "record %d differs: %s (godot %s)" % [i, diff.left(200), PyJson.dumps(got, false).left(200)]
	return ""


func test_walk_traces_match_python(seed_value = use_parameters(range(10))) -> void:
	var dir := _need("WALK_TRACES")
	if dir == "":
		return
	var diff := _walk_diff("%s/walk_%d.jsonl" % [dir, seed_value], seed_value, "", null)
	assert_eq(diff, "", "seed %d" % seed_value)


func test_pet_and_hero_walk_traces_match_python(combo = use_parameters(COMBOS)) -> void:
	var dir := _need("WALK_COMBOS")
	if dir == "":
		return
	var parts: PackedStringArray = String(combo[3]).split(":")
	var story := parts[1] if parts.size() > 1 else ""
	var hero := {"name": "Bot", "gender": null if parts[0] == "" else parts[0],
			"backstory": null if story == "" else story}
	var diff := _walk_diff("%s/%s.jsonl" % [dir, combo[0]], combo[1], combo[2], hero)
	assert_eq(diff, "", combo[0])


func test_trace_run_is_deterministic() -> void:
	var a := TraceRun.run_trace(5, "walk", 60, "cat")
	var b := TraceRun.run_trace(5, "walk", 60, "cat")
	assert_eq(PyJson.dumps(a, false), PyJson.dumps(b, false))
	assert_eq(a[0]["k"], "header")
	assert_eq(a[-1]["k"], "end")

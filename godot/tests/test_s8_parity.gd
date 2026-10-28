extends TestCase
## Parity of the `hunter` policy run traces with Python (port plan 6.4, slice S8). scripts/gd_test.sh
## sets HUNTER_TRACES to a directory with hunter_<seed>.jsonl from
## `py_trace.py --seeds 0-4 --policy hunter --steps 3000` and HUNTER_COMBOS to one with <name>.jsonl for
## the pet and hero combinations below. The full acceptance run (seeds 0-49, no pet, each pet and heroes) is
## tools/trace.gd + scripts/parity_diff.py --dirs --scope core.
##
## Compared at core scope exactly as test_s7_parity.gd does (it shares its filter): msg records, the
## stand-in systems' events, showmanship practice events, viewers and the show stream are dropped from both
## sides. T1 to T3 replace the stand-ins and this test then compares everything.
## A missing reference directory fails the test (run through scripts/gd_test.sh).

const S7 := preload("res://tests/test_s7_parity.gd")
const STEPS := 3000

## [name, seed, pet, hero "GENDER:BACKSTORY"]; mirrors the combo list in scripts/gd_test.sh.
const COMBOS := [
	["cat_tradie_3", 3, "cat", "female:tradie"],
	["dog_rideshare_8", 8, "dog", "male:rideshare"],
	["budgie_dog_walker_12", 12, "budgie", "male:dog_walker"],
	["mouse_comedian_21", 21, "mouse", "female:comedian"],
	["cat_none_30", 30, "cat", ":"],
]


func _need(var_name: String) -> String:
	var v := OS.get_environment(var_name)
	if v == "":
		fail_test("%s is not set (run through scripts/gd_test.sh)" % var_name)
	return v


## "" when the Godot hunter trace equals the Python file at core scope.
func _hunter_diff(py_path: String, seed_value: int, pet: String, hero: Variant) -> String:
	if not FileAccess.file_exists(py_path):
		return "missing " + py_path
	var py := S7._read(py_path)
	var mine: Array = []
	for rec in TraceRun.run_trace(seed_value, "hunter", STEPS, pet, hero):
		var core := S7._core(JSON.parse_string(PyJson.dumps(rec, false)))
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


func test_hunter_traces_match_python(seed_value = use_parameters(range(5))) -> void:
	var dir := _need("HUNTER_TRACES")
	if dir == "":
		return
	var diff := _hunter_diff("%s/hunter_%d.jsonl" % [dir, seed_value], seed_value, "", null)
	assert_eq(diff, "", "seed %d" % seed_value)


func test_pet_and_hero_hunter_traces_match_python(combo = use_parameters(COMBOS)) -> void:
	var dir := _need("HUNTER_COMBOS")
	if dir == "":
		return
	var parts: PackedStringArray = String(combo[3]).split(":")
	var story := parts[1] if parts.size() > 1 else ""
	var hero := {"name": "Bot", "gender": null if parts[0] == "" else parts[0],
			"backstory": null if story == "" else story}
	var diff := _hunter_diff("%s/%s.jsonl" % [dir, combo[0]], combo[1], combo[2], hero)
	assert_eq(diff, "", combo[0])

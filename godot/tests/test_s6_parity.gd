extends TestCase
## Parity of World's floors and spawns with Python (port plan 6.4, slice S6). scripts/gd_test.sh
## sets SPAWN_TRACES to a directory with floors_<seed>.jsonl from
## `py_trace.py --floor-only --spawns --floors 6` (seeds 0-19 in the suite). The full acceptance run (seeds 0-499)
## is tools/trace.gd + scripts/parity_diff.py --dirs.
##
## Compared in full, show stream included (the Showrunner is real since T2); the Python references are made
## with nothing muted (scripts/gd_test.sh).


func _need(var_name: String) -> String:
	var v := OS.get_environment(var_name)
	if v == "":
		fail_test("%s is not set (run through scripts/gd_test.sh)" % var_name)
	return v


## [name, seed, pet, hero "GENDER:BACKSTORY"]; mirrors the combo list in scripts/gd_test.sh.
const COMBOS := [
	["cat_tradie_3", 3, "cat", "female:tradie"],
	["dog_rideshare_8", 8, "dog", "male:rideshare"],
	["budgie_none_12", 12, "budgie", ":"],
	["mouse_mixologist_21", 21, "mouse", "female:mixologist"],
	["none_parent_5", 5, "none", "male:parent"],
]


func test_pet_and_hero_world_traces_match_python(combo = use_parameters(COMBOS)) -> void:
	var dir := _need("SPAWN_COMBOS")
	if dir == "":
		return
	var path := "%s/%s.jsonl" % [dir, combo[0]]
	if not FileAccess.file_exists(path):
		fail_test("missing " + path)
		return
	var py: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		py.append(JSON.parse_string(line))
	var parts: PackedStringArray = String(combo[3]).split(":")
	var story := parts[1] if parts.size() > 1 else ""
	var hero := {"name": "Bot", "gender": null if parts[0] == "" else parts[0],
			"backstory": null if story == "" else story}
	var pet: String = "" if combo[2] == "none" else combo[2]
	var mine := TraceFloors.run_floors_world(combo[1], 4, pet, hero)
	assert_eq(mine.size(), py.size())
	for i in mini(mine.size(), py.size()):
		var got: Dictionary = JSON.parse_string(PyJson.dumps(mine[i], false))
		var want: Dictionary = py[i]
		if want["k"] == "header":
			want["impl"] = got["impl"]
		var diff := TestCase.strict_diff(got, want)
		if diff != "":
			fail_test("%s record %d differs: %s" % [combo[0], i, diff.left(200)])
			return
	assert_true(true)


func test_world_floor_traces_match_python(seed_value = use_parameters(range(20))) -> void:
	var dir := _need("SPAWN_TRACES")
	if dir == "":
		return
	var path := "%s/floors_%d.jsonl" % [dir, seed_value]
	if not FileAccess.file_exists(path):
		fail_test("missing " + path)
		return
	var py: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		py.append(JSON.parse_string(line))
	var mine := TraceFloors.run_floors_world(seed_value, 6)
	assert_eq(mine.size(), py.size())
	for i in mini(mine.size(), py.size()):
		# through JSON text so both sides carry the same number types as the Python file
		var got: Dictionary = JSON.parse_string(PyJson.dumps(mine[i], false))
		var want: Dictionary = py[i]
		if want["k"] == "header":
			want["impl"] = got["impl"]
		var diff := TestCase.strict_diff(got, want)
		if diff != "":
			var which: String = "header" if want["k"] == "header" else str(int(want["depth"]))
			fail_test("seed %d record %s differs: %s" % [seed_value, which, diff.left(200)])
			return
	assert_true(true)

extends TestCase
## Parity of World's floors and spawns with Python (port plan 6.4, slice S6). scripts/gd_test.sh
## sets SPAWN_TRACES to a directory with floors_<seed>.jsonl from
## `py_trace.py --floor-only --spawns --floors 6` (seeds 0-49). The full acceptance run (seeds 0-499)
## is tools/trace.gd + scripts/parity_diff.py --dirs.
##
## The `show` stream (index 4 of rs and words) is dropped from both sides: Showrunner is still a
## stand-in that never draws (slice T2 replaces it, and this test then compares all five).


func _need(var_name: String) -> String:
	var v := OS.get_environment(var_name)
	if v == "":
		fail_test("%s is not set (run through scripts/gd_test.sh)" % var_name)
	return v


## Drop the show stream from a floor record's rs and words (core scope of parity_diff).
static func _core(rec: Dictionary) -> Dictionary:
	for key in ["rs", "words"]:
		if rec.has(key) and (rec[key] as Array).size() >= 5:
			rec[key] = (rec[key] as Array).slice(0, 4)
	return rec


func test_world_floor_traces_match_python(seed_value = use_parameters(range(50))) -> void:
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
		var got: Dictionary = _core(JSON.parse_string(PyJson.dumps(mine[i], false)))
		var want: Dictionary = _core(py[i])
		if want["k"] == "header":
			want["impl"] = got["impl"]
		var diff := TestCase.strict_diff(got, want)
		if diff != "":
			var which: String = "header" if want["k"] == "header" else str(int(want["depth"]))
			fail_test("seed %d record %s differs: %s" % [seed_value, which, diff.left(200)])
			return
	assert_true(true)

extends TestCase
## Parity of the bot (port plan 6.4, slice T6) with Python.
##
## BOT_TRACES (scripts/gd_test.sh): bot_<seed>.jsonl from `py_trace.py --seeds 0-3 --policy bot --steps 3000`
## (--mute funfacts until T3 lands); the Godot `bot` trace must equal it in full (every ev, turn, floor, act,
## msg and end record). Seeds 0-3 take in a victory, a collapse and two deaths. The pet, hero, race and class
## come from BotPolicy.run_config, as in py_trace.py.
##
## The CSV check plays the same seeds with telemetry and compares what PyCsv writes (no events table, as
## the committed files) with the rows of the committed runs/bot_*.csv, byte for byte, header included.
## The full acceptance sets (traces 0-49, CSVs 0-99) are in scripts/parity_all.sh.
## A missing reference directory fails the test (run through scripts/gd_test.sh).

const S7 := preload("res://tests/test_s7_parity.gd")
const STEPS := 3000
const CSV_SEEDS := 4
const TABLES := ["runs", "floors", "boxes", "shop", "practice"]


func _need(var_name: String) -> String:
	var v := OS.get_environment(var_name)
	if v == "":
		fail_test("%s is not set (run through scripts/gd_test.sh)" % var_name)
	return v


## "" when the Godot bot trace equals the Python file in full.
func _bot_diff(py_path: String, seed_value: int) -> String:
	if not FileAccess.file_exists(py_path):
		return "missing " + py_path
	var py := S7._read(py_path)
	var setup := TracePolicies.default_setup("bot", seed_value)
	var mine: Array = []
	for rec in TraceRun.run_trace(seed_value, "bot", STEPS, setup[0], setup[1]):
		mine.append(JSON.parse_string(PyJson.dumps(rec, false)))
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


func test_bot_traces_match_python(seed_value = use_parameters(range(4))) -> void:
	var dir := _need("BOT_TRACES")
	if dir == "":
		return
	assert_eq(_bot_diff("%s/bot_%d.jsonl" % [dir, seed_value], seed_value), "", "seed %d" % seed_value)


func test_bot_csv_rows_match_the_committed_files() -> void:
	var root := _need("CRAWL_ROOT")
	if root == "":
		return
	var out := TestHelpers.tmp_dir("bot_csv")
	for sd in range(CSV_SEEDS):
		var r := BotPolicy.play(sd, "", "random", true)
		assert_true(PyCsv.write_tables(r[1], out, "bot_", ["events"]))
	for t in TABLES:
		var ref_path := "%s/runs/bot_%s.csv" % [root, t]
		if not FileAccess.file_exists(ref_path):
			fail_test("missing " + ref_path)
			continue
		var lines := FileAccess.get_file_as_string(ref_path).split("\r\n", false)
		var want := lines[0] + "\r\n"
		for n in range(1, lines.size()):
			var run_id := String(lines[n]).get_slice(",", 0)
			if run_id.begins_with("bot") and int(run_id.substr(3)) < CSV_SEEDS:
				want += lines[n] + "\r\n"
		var got := FileAccess.get_file_as_string(out + "bot_%s.csv" % t)
		assert_true(got == want, "bot_%s.csv differs from the committed rows (%d vs %d bytes)" % [t, got.length(), want.length()])

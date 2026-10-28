extends TestCase
## Telemetry and PyCsv (crawler/telemetry.py, tests/test_telemetry.py; slice T4), plus the byte-for-byte
## comparison of the CSV files with Python's.
##
## Ported here: test_write_tables_appends_with_one_header and the two bot tests (T6). Not ported yet
## (see port plan Appendix B.1): test_game_logs_finished_player_runs (needs the App, P5).
##
## CHAOS_CSV (made by scripts/gd_test.sh): Python's CSV files for chaos seeds 0-15 (scripts/chaos_trace.py
## --telemetry-dir). tools/chaos.gd writes the same runs in a child Godot process and
## scripts/parity_diff.py --csv compares the two directories byte for byte. The seeds cover unfinished,
## killed, collapsed and victorious runs, every event type the chaos player causes, and a set of odd events
## (quotes, commas, newlines, unicode, float text, bools) emitted on the bus. The full set (more seeds) is in
## scripts/parity_all.sh. A missing CHAOS_CSV fails the test (run through scripts/gd_test.sh).

const SEEDS := "0-15"
const STEPS := 200

const RUNS_COLS := ["run_id", "source", "seed", "pet", "race", "backstory", "gender", "cls", "outcome", "depth",
		"turns", "kills", "level", "gold", "viewers", "peak_viewers", "boxes", "achievements",
		"practice_levels", "death_cause"]
const FLOORS_COLS := ["run_id", "source", "depth", "turn", "hp", "max_hp", "hp_frac", "level", "str", "dex", "con",
		"int", "cha", "attack", "ac", "dmg_avg", "potions", "bombs", "gold", "boxes", "cls", "race", "backstory",
		"pet", "pet_level", "pet_down", "timer_max", "viewers", "contract", "damage_taken", "gold_earned",
		"kills_here", "viewers_gained", "result", "died_here"]
const BOXES_COLS := ["run_id", "source", "tier", "item", "value", "ev", "rerolled", "turn", "reason"]
const SHOP_COLS := ["run_id", "source", "depth", "item", "demand", "sales", "lost", "delivered", "on_hand",
		"forecast_before", "forecast", "reorder_point", "ordered"]
const PRACTICE_COLS := ["run_id", "source", "skill", "level", "used"]
const EVENTS_COLS := ["run_id", "turn", "floor", "event", "value", "detail"]


# --- test_telemetry.py -----------------------------------------------------

func test_write_tables_appends_with_one_header() -> void:
	var dir := TestHelpers.tmp_dir("telemetry_append")
	for sd in [1, 2]:
		var w := World.new(sd)
		var tel := Telemetry.new(w, "test", "r%d" % sd)
		w._kill_player("test")
		assert_true(PyCsv.write_tables(tel.tables(), dir, "t_"))
	var rows := PyCsv.read_dicts(dir + "t_runs.csv")
	var ids := []
	for r in rows:
		ids.append(r["run_id"])
	assert_eq(ids, ["r1", "r2"])
	var text := FileAccess.get_file_as_string(dir + "t_runs.csv")
	assert_eq(text.count("run_id,source,seed"), 1)
	assert_eq(text.count("\r\n"), 3)


func test_bot_run_produces_consistent_tables() -> void:
	var r := BotPolicy.play(3, "", "random", true)
	var w: World = r[0]
	var t: Dictionary = r[1]
	var run: Dictionary = t["runs"][0]
	assert_true(run["outcome"] in ["victory", "killed", "collapse"])
	var floors: Array = t["floors"]
	var depths := []
	var died := 0
	for f in floors:
		depths.append(f["depth"])
		died += int(f["died_here"])
	var want := []
	for d in range(1, w.depth + 1):
		want.append(d)
	assert_eq(depths, want)
	assert_eq(died, int(run["outcome"] != "victory"))
	for i in range(floors.size() - 1):
		assert_eq(floors[i]["result"], "cleared")
	assert_eq((t["boxes"] as Array).size(), w.box_log.size())
	var events := {}
	for e in t["events"]:
		events[e["event"]] = true
	assert_true(events.has("kill") and (events.has("floor_start") or w.depth == 1))
	assert_false(events.has("turn"))


func test_bot_is_deterministic() -> void:
	var a := BotPolicy.play(5, "", "random", true)
	var b := BotPolicy.play(5, "", "random", true)
	assert_eq_deep(a[1]["runs"], b[1]["runs"])
	assert_eq_deep(a[1]["floors"], b[1]["floors"])


# --- Telemetry tables ------------------------------------------------------

func _played(sd: int) -> Array:
	var w := World.new(sd, ["cat", ""], {"name": "H", "gender": "female", "backstory": "tradie"})
	var tel := Telemetry.new(w, "test", "rx", {"deals": "random"})
	var rng := PyRandom.new(sd)
	TestHelpers.play(w, rng, 120)
	w.last_reason = "why"
	w._reveal("silver")
	w.new_floor(2)
	return [w, tel]


func test_columns_are_pythons_in_order() -> void:
	var r := _played(4)
	var t: Dictionary = (r[1] as Telemetry).tables()
	assert_eq(t.keys(), ["runs", "floors", "boxes", "shop", "practice", "events"])
	assert_eq((t["runs"][0] as Dictionary).keys(), RUNS_COLS + ["deals"])
	assert_eq((t["floors"][0] as Dictionary).keys(), FLOORS_COLS)
	assert_eq((t["boxes"][0] as Dictionary).keys(), BOXES_COLS)
	assert_eq((t["practice"][0] as Dictionary).keys(), PRACTICE_COLS)
	assert_eq((t["events"][0] as Dictionary).keys(), EVENTS_COLS)
	assert_eq(t["floors"].size(), 2)


func test_shop_columns() -> void:
	var r := _played(4)
	var w: World = r[0]
	w.shop.end_of_floor(1)
	var t: Dictionary = (r[1] as Telemetry).tables()
	assert_false((t["shop"] as Array).is_empty())
	assert_eq((t["shop"][0] as Dictionary).keys(), SHOP_COLS)


func test_outcomes_and_floor_results() -> void:
	var r := _played(6)
	var w: World = r[0]
	var tel: Telemetry = r[1]
	var t: Dictionary = tel.tables()
	assert_eq(t["runs"][0]["outcome"], "unfinished")
	assert_eq([t["floors"][0]["result"], t["floors"][1]["result"]], ["cleared", "unfinished"])
	assert_eq(t["floors"][0]["died_here"], 0)
	w._kill_player("Killed by a test")
	t = tel.tables()
	assert_eq([t["runs"][0]["outcome"], t["floors"][1]["result"], t["floors"][1]["died_here"]], ["killed", "killed", 1])
	assert_eq(t["runs"][0]["death_cause"], "Killed by a test")
	var w2 := World.new(6)
	var tel2 := Telemetry.new(w2, "test", "ry")
	w2._kill_player("Crushed when floor 1 collapsed")
	assert_eq(tel2.tables()["runs"][0]["outcome"], "collapse")
	var w3 := World.new(6)
	var tel3 := Telemetry.new(w3, "test", "rz")
	w3.state = "victory"
	var t3: Dictionary = tel3.tables()
	assert_eq([t3["runs"][0]["outcome"], t3["floors"][0]["result"], t3["floors"][0]["died_here"]], ["victory", "victory", 0])
	assert_eq([t3["runs"][0]["gender"], t3["runs"][0]["cls"], t3["runs"][0]["backstory"]], ["none", "none", "none"])


func test_floor_row_values() -> void:
	var w := World.new(9, ["dog", "Rex"])
	var tel := Telemetry.new(w, "test", "rv")
	var row: Dictionary = tel.tables()["floors"][0]
	var p := w.player
	assert_eq([row["depth"], row["hp"], row["max_hp"], row["pet"], row["pet_level"], row["pet_down"]],
			[1, p.hp, p.max_hp, "dog", w.pet.level, false])
	assert_eq(row["hp_frac"], 1.0)
	assert_eq(row["dmg_avg"], Dice.average(p.dmg_n, p.dmg_die, p.dmg_bonus))
	assert_eq(row["viewers"], w.viewers)
	assert_eq(row["contract"], "none")
	assert_eq(row["str"], w.score("str"))
	p.hp = 1
	w.new_floor(2)
	assert_eq(tel.tables()["floors"][1]["hp_frac"], PyMath.round_n(1.0 / p.max_hp, 3))


func test_event_value_and_detail_follow_python() -> void:
	var w := World.new(2)
	var tel := Telemetry.new(w, "test", "re")
	var before := tel.events.size()
	w.events.emit("turn", {"turn": 5})                                   # skipped
	assert_eq(tel.events.size(), before)
	w.events.emit("x", {"damage": true, "amount": 1.5, "item": "pan", "tier": "gold"})
	w.events.emit("x", {"damage": false, "xp": 4, "monster": "", "item": null, "boss": false})
	w.events.emit("x", {"kills": "3", "cause": 7, "depth": 2})
	w.events.emit("x", {})
	var rows: Array = tel.events.slice(before)
	assert_eq([rows[0]["value"], rows[0]["detail"]], [1.5, "pan"])      # bool is not a value; first detail key wins
	assert_eq([rows[1]["value"], rows[1]["detail"]], [4, "False"])      # str(False), as Python's pet_kill rows
	assert_eq([rows[2]["value"], rows[2]["detail"]], [2, "7"])
	assert_eq([rows[3]["value"], rows[3]["detail"]], ["", ""])
	assert_eq(rows[0]["turn"], w.turn)
	assert_eq(rows[0]["floor"], w.depth)
	assert_eq(rows[0]["run_id"], "re")


func test_run_id_and_meta() -> void:
	var w := World.new(3)
	var a := Telemetry.new(w, "bot", 1)
	assert_eq(a.run_id, 1)                                   # any truthy id is kept as given
	var b := Telemetry.new(w)
	assert_eq(b.source, "player")
	assert_eq(String(b.run_id).length(), 12)
	assert_true(String(b.run_id).is_valid_hex_number())
	var c := Telemetry.new(w, "bot", "", {"deals": "accept"})
	assert_ne(c.run_id, b.run_id)
	assert_eq((c.tables()["runs"][0] as Dictionary)["deals"], "accept")


func test_subscription_order_is_pythons() -> void:
	var w := World.new(3)
	var star_before := w.events.subscribers("*").size()
	var fs_before := w.events.subscribers("floor_start").size()
	var tel := Telemetry.new(w)
	assert_eq(w.events.subscribers("*").size(), star_before + 1)
	assert_eq(w.events.subscribers("floor_start").size(), fs_before + 1)
	assert_true(w.events.subscribers("*")[star_before].get_object() == tel)
	assert_eq(tel.arrivals.size(), 1)        # floor 1 started before the subscription
	w.new_floor(2)
	assert_eq(tel.arrivals.size(), 2)
	assert_eq(tel.arrivals[1]["depth"], 2)


func test_practice_levels_and_achievements_count() -> void:
	var w := World.new(10)
	var tel := Telemetry.new(w, "bot", "rp")
	w.training.gain("lobbing", 10)
	var run: Dictionary = tel.tables()["runs"][0]
	var total := 0
	for k in w.training.levels:
		total += w.training.levels[k]
	assert_eq(run["practice_levels"], total)
	assert_eq(run["achievements"], w.achievements.unlocked.size())
	assert_eq(run["peak_viewers"], w.showrunner.peak)


# --- Ownership (port plan section 3, back-references to World) -------------

func _build_owned() -> Array:
	var w := World.new(5, ["dog", "Rex"])
	var tel := Telemetry.new(w, "test", "ro")
	w.new_floor(2)
	assert_true(tel.world == w)
	return [weakref(w), weakref(tel), weakref(w.events)]   # both strong references die on return


func test_telemetry_and_world_are_freed_when_dropped() -> void:
	var refs := _build_owned()
	assert_null(refs[0].get_ref(), "world")
	assert_null(refs[1].get_ref(), "telemetry")
	assert_null(refs[2].get_ref(), "event bus")


func test_telemetry_kept_alone_does_not_keep_the_world() -> void:
	var tel := _telemetry_only()
	assert_null(tel.world)


func _telemetry_only() -> Telemetry:
	var w := World.new(5)
	return Telemetry.new(w, "test", "rk")


# --- PyCsv ----------------------------------------------------------------

func test_csv_quoting_and_line_ends() -> void:
	assert_eq(PyCsv.encode_row(["a", "b c", ""]), "a,b c,\r\n")
	assert_eq(PyCsv.encode_row(["x,y", "say \"hi\"", "l1\nl2", "cr\rcr"]), "\"x,y\",\"say \"\"hi\"\"\",\"l1\nl2\",\"cr\rcr\"\r\n")
	assert_eq(PyCsv.encode_row([""]), "\"\"\r\n")           # a lone empty field is quoted (csv module)
	assert_eq(PyCsv.encode_row(["", ""]), ",\r\n")
	assert_eq(PyCsv.encode_row([" lead", "tail ", "a;b", "tab\t"]), " lead,tail ,a;b,tab\t\r\n")
	assert_eq(PyCsv.encode_row(["Zoë"]), "Zoë\r\n")


func test_csv_cell_text_is_python_str() -> void:
	assert_eq(PyCsv.encode_row([null, true, false, 3, -4, 1.0, 0.1 + 0.2, 1e-05, 1e16, 2.5, 123456.789, 0.067]),
			",True,False,3,-4,1.0,0.30000000000000004,1e-05,1e+16,2.5,123456.789,0.067\r\n")


func test_csv_header_rows_and_missing_keys() -> void:
	var rows := [{"a": 1, "b": "x"}, {"b": "y"}, {"b": null, "a": 2.5}]
	assert_eq(PyCsv.encode_rows(rows), "a,b\r\n1,x\r\n,y\r\n2.5,\r\n")      # restval "", columns by the first row
	assert_eq(PyCsv.encode_rows(rows, false), "1,x\r\n,y\r\n2.5,\r\n")
	assert_eq(PyCsv.encode_rows([]), "")


func test_csv_extra_key_is_an_error() -> void:
	assert_eq(PyCsv.encode_rows([{"a": 1}, {"a": 2, "z": 3}]), "")
	assert_push_error("not in fieldnames")


func test_csv_write_tables_skip_empty_and_append() -> void:
	var dir := TestHelpers.tmp_dir("csv_write")
	var tables := {"one": [{"k": 1}], "two": [{"k": "a,b"}], "empty": [], "skipped": [{"k": 9}]}
	assert_true(PyCsv.write_tables(tables, dir, "p_", ["skipped"]))
	assert_true(PyCsv.write_tables(tables, dir, "p_", ["skipped"]))
	assert_eq(FileAccess.get_file_as_string(dir + "p_one.csv"), "k\r\n1\r\n1\r\n")
	assert_eq(FileAccess.get_file_as_string(dir + "p_two.csv"), "k\r\n\"a,b\"\r\n\"a,b\"\r\n")
	assert_false(FileAccess.file_exists(dir + "p_empty.csv"))
	assert_false(FileAccess.file_exists(dir + "p_skipped.csv"))


func test_csv_empty_existing_file_gets_a_header_and_nested_dirs_are_made() -> void:
	var dir := TestHelpers.tmp_dir("csv_empty")
	var f := FileAccess.open(dir + "e_t.csv", FileAccess.WRITE)
	f.close()
	PyCsv.write_tables({"t": [{"k": 1}]}, dir, "e_")
	assert_eq(FileAccess.get_file_as_string(dir + "e_t.csv"), "k\r\n1\r\n")
	DirAccess.remove_absolute(dir + "deep/er/t.csv")      # tmp_dir clears files, not sub-directories
	PyCsv.write_tables({"t": [{"k": 1}]}, dir + "deep/er", "")
	assert_eq(FileAccess.get_file_as_string(dir + "deep/er/t.csv"), "k\r\n1\r\n")


func test_csv_parse_round_trip() -> void:
	var rows := [{"a": "x,y", "b": "q\"uote", "c": "two\r\nlines", "d": ""}, {"a": "", "b": "z", "c": "", "d": "Zoë"}]
	var text := PyCsv.encode_rows(rows)
	var parsed := PyCsv.parse(text)
	assert_eq(parsed.size(), 3)
	assert_eq(parsed[0], ["a", "b", "c", "d"])
	assert_eq(parsed[1], ["x,y", "q\"uote", "two\r\nlines", ""])
	assert_eq(parsed[2], ["", "z", "", "Zoë"])
	assert_eq(PyCsv.parse("a,b\n1,2"), [["a", "b"], ["1", "2"]])


# --- Python parity ---------------------------------------------------------

func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


func test_chaos_csv_files_are_byte_identical_to_python() -> void:
	var py_dir := OS.get_environment("CHAOS_CSV")
	if py_dir == "" or not DirAccess.dir_exists_absolute(py_dir):
		fail_test("CHAOS_CSV is not set or missing (run through scripts/gd_test.sh)")
		return
	var root := OS.get_environment("CRAWL_ROOT")
	if root == "":
		fail_test("CRAWL_ROOT is not set (run through scripts/gd_test.sh)")
		return
	var out := ProjectSettings.globalize_path(TestHelpers.tmp_dir("telemetry_chaos"))
	var gd_dir := out.path_join("csv")
	_remove_tree(gd_dir)       # the writer appends, so start from nothing
	var log: Array = []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", root + "/godot",
			"-s", "res://tools/chaos.gd", "--", "--seeds", SEEDS, "--steps", str(STEPS),
			"--out-dir", out, "--telemetry-dir", gd_dir], log, true)
	assert_eq(code, 0, "chaos.gd exit code: %s" % "".join(log).right(400))
	log = []
	code = OS.execute("python3", [root + "/scripts/parity_diff.py", "--csv", py_dir, gd_dir], log, true)
	var report := "".join(log)
	assert_eq(code, 0, "parity_diff --csv: %s" % report.left(1500))
	assert_true("byte-identical" in report, report.left(300))
	assert_true("96 files" in report, report.left(300))      # 16 seeds x 6 tables

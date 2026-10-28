extends TestCase
## SaveGame and PyJsonLoad (crawler/save.py, slice T5): the JSON reader that keeps ints and floats apart, the
## save layout (key order, types), file handling (directory parameter, atomic write, mid-combat refusal,
## corrupt files), ownership of the loaded World, and the Python parity of the saves.
##
## Parity (SAVE_TRACES, made by scripts/gd_test.sh with scripts/save_trace.py): Python's saves and traces for
## seeds 0-7 (seed 3 dies before it can be saved, so seven runs are compared). A child Godot process (tools/save_trace.gd) plays the same seeds, writes its own saves and
## loads Python's; a child Python process (scripts/save_trace.py --load-dir) loads Godot's. scripts/save_diff.py
## then requires byte-identical save files and identical traces: continuing without saving, after a save and
## load in the same language, and after loading the other language's save. The full set (seeds 0-99) is in
## scripts/parity_all.sh. A missing SAVE_TRACES fails the test (run through scripts/gd_test.sh).

const SEEDS := "0-7"
const STEPS := 150


# --- PyJsonLoad --------------------------------------------------------------

func test_parse_keeps_int_and_float_apart() -> void:
	var v: Variant = PyJsonLoad.parse("{\"a\": 1, \"b\": 1.0, \"c\": -0, \"d\": 1e3, \"e\": [2, 2.5, -3], \"f\": 12345678901234}")
	assert_eq(PyJsonLoad.error, "")
	assert_eq(v, {"a": 1, "b": 1.0, "c": 0, "d": 1000.0, "e": [2, 2.5, -3], "f": 12345678901234})


func test_parse_literals_strings_and_nesting() -> void:
	var v: Variant = PyJsonLoad.parse(" {\"t\": true, \"f\": false, \"n\": null, \"s\": \"a\\\"b\\\\c\\/d\\n\\u00e9\\ud83d\\ude00x\", \"o\": {}, \"l\": [[], [{}]]} ")
	assert_eq(PyJsonLoad.error, "")
	assert_eq(v["t"], true)
	assert_eq(v["f"], false)
	assert_null(v["n"])
	assert_eq(v["s"], "a\"b\\c/d\n\u00e9\U01F600x")
	assert_eq(v["o"], {})
	assert_eq(v["l"], [[], [{}]])
	assert_eq(v.keys(), ["t", "f", "n", "s", "o", "l"], "insertion order")
	assert_eq(PyJsonLoad.parse("\"raw \u00e9 text\""), "raw \u00e9 text")


func test_parse_special_floats() -> void:
	var v: Array = PyJsonLoad.parse("[NaN, Infinity, -Infinity]")
	assert_true(is_nan(v[0]))
	assert_eq(v[1], INF)
	assert_eq(v[2], -INF)


func test_parse_errors_set_the_message_and_return_null() -> void:
	for text in ["", "{", "[1,]", "{\"a\" 1}", "{1: 2}", "[1] x", "\"abc", "tru", "[1 2]", "{\"a\": }", "\"\\q\"", "--1"]:
		assert_null(PyJsonLoad.parse(text), text)
		assert_ne(PyJsonLoad.error, "", text)
	PyJsonLoad.parse("null")
	assert_eq(PyJsonLoad.error, "")


func test_repr_floats_parse_back_exactly() -> void:
	var rng := PyRandom.new(2024)
	var bad := 0
	var n := 0
	for i in range(4000):
		var x := rng.random() * pow(10.0, float(rng.randrange(-6, 12)))
		if i % 7 == 0:
			x = -x
		var back: float = PyJsonLoad.parse(PyFmt.repr_float(x))
		n += 1
		if back != x:
			bad += 1
	assert_eq(bad, 0, "of %d" % n)
	for t in ["1e-05", "1e+16", "1.7976931348623157e+308", "0.1", "2.5", "1.5e-07", "123456789.123456", "0.30000000000000004", "1e+22", "1e+23"]:
		assert_eq(PyFmt.repr_float(PyJsonLoad.parse(t)), t, t)
	assert_eq(PyJsonLoad.parse("-0.0"), -0.0)
	assert_eq(PyFmt.repr_float(PyJsonLoad.parse("-0.0")), "-0.0")
	# The to_float path is wrong for some of these; the reader must not be.
	var wrong := 0
	for i in range(4000):
		var x := rng.random()
		if PyFmt.repr_float(x).to_float() != x:
			wrong += 1
	gut.p("String.to_float misreads %d of 4000 repr floats; PyJsonLoad none" % wrong)


func _bits(x: float) -> int:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, x)
	return b.decode_s64(0)


func test_tiny_and_subnormal_floats() -> void:
	# bit patterns from CPython
	assert_eq(_bits(PyJsonLoad.parse("5e-324")), 1)
	assert_eq(_bits(PyJsonLoad.parse("1e-310")), 20240225330731)
	assert_eq(_bits(PyJsonLoad.parse("2.2250738585072014e-308")), 4503599627370496)
	assert_eq(_bits(PyJsonLoad.parse("1e-300")), 118622047889322841)
	assert_eq(_bits(PyJsonLoad.parse("1.5e-320")), 3036)


func test_invalid_number_forms_are_errors() -> void:
	for text in ["01", "-01", "00", "1.", "1e", "1e+", "-", ".5", "1.e3", "+1", "1e-"]:
		assert_null(PyJsonLoad.parse(text), text)
		assert_ne(PyJsonLoad.error, "", text)
	for text in ["0", "-0", "0.5", "10", "1e5", "1E+5", "0e0", "-0.0e-1"]:
		PyJsonLoad.parse(text)
		assert_eq(PyJsonLoad.error, "", text)


func test_dumps_then_parse_is_the_identity_on_game_shaped_data() -> void:
	var d := {"a": [1, 2.0, 0.1 + 0.2], "b": {"c": null, "d": "x\ny\u00e9"}, "e": 1e-05, "f": 123456789.123456, "g": true}
	assert_eq(PyJsonLoad.parse(PyJson.dumps(d)), d)


# --- SaveGame layout -----------------------------------------------------------

const KEYS := ["version", "seed", "turn", "state", "death_cause", "depth", "timer", "timer_max", "warnings_left",
		"was_safe", "inventory", "equipment", "boxes", "box_reasons", "last_reason", "floor_items", "last_reveal",
		"toasts", "messages", "race", "cls", "pending_choice", "skill_cooldown", "scout_turns", "exit_sealed",
		"has_key", "stairs_open_turn", "stairs_announced", "next_spawn", "spawn_cap", "gold", "contract",
		"pending_offer", "hero_name", "gender", "backstory", "hype_turns", "practice", "riposte", "remote_shop",
		"plant_fed_floor", "floor_stats", "box_log", "shop", "shop_rng", "deal_rng", "funfacts", "player", "pet",
		"monsters", "floor", "rng", "loot_rng", "achievements", "showrunner"]


func test_save_layout_is_pythons() -> void:
	var w := World.new(5, ["cat", "Tom"])
	var d := SaveGame.to_dict(w)
	assert_eq(d.keys(), KEYS)
	assert_eq(d["version"], 7)
	assert_eq(SaveGame.VERSION, 7)
	assert_eq(d["floor"].keys(), ["width", "height", "depth", "tiles", "safe", "explored", "rooms", "start_room",
			"safe_room", "stairs", "safe_door", "furniture"])
	assert_eq(d["showrunner"].keys(), ["viewers", "peak", "history", "kill_turns", "last_fun", "gift_idx",
			"last_flee_quip", "samples", "rng"])
	assert_eq(d["funfacts"].keys(), ["last_turn", "said", "miss_streak", "streak_chance", "drought"])
	assert_eq(d["achievements"].keys(), ["unlocked", "kills", "pickups", "equipped"])
	assert_eq(d["rng"].size(), 2)
	assert_eq(d["rng"][0].size(), 625)
	assert_null(d["rng"][1])
	assert_true(d["floor"]["safe"][0][0] is bool, "safe and explored hold bools")
	assert_true(d["floor"]["tiles"][0][0] is int, "tiles hold ints")
	assert_eq(d["player"].keys().slice(0, 4), ["x", "y", "name", "glyph"])


func test_saved_text_is_json_dumps_text() -> void:
	var w := World.new(6)
	var text := SaveGame.dumps(w)
	assert_true(text.begins_with("{\"version\": 7, \"seed\": 6, \"turn\": "))
	assert_true(text.contains("\"state\": \"playing\", \"death_cause\": null"))
	assert_false(text.contains("\n"))


func test_text_round_trip_is_exact_for_many_states() -> void:
	for sd in [0, 1, 2, 3]:
		var c := SaveTraceRun.new(sd)
		c.setup()
		for n in range(120 + 40 * sd):
			if c.w.state == "playing":
				c.step(n)
		if c.w.combat != null:
			continue
		var text := SaveGame.dumps(c.w)
		var v := SaveGame.from_text(text)
		assert_not_null(v, "seed %d" % sd)
		assert_eq(SaveGame.dumps(v), text, "seed %d re-dumps to the same text" % sd)
		assert_eq(SaveGame.to_dict(v), SaveGame.to_dict(c.w), "seed %d" % sd)


# --- Bot-played states: save at a safe room, continue both worlds ------------------------

func test_bot_runs_round_trip_and_continue_identically() -> void:
	var done := 0
	for sd in range(0, 12):
		var cfg := BotPolicy.run_config(sd)
		var w := World.new(sd, [cfg["pet"], ""], {"name": "Bot", "gender": cfg["gender"], "backstory": cfg["backstory"]})
		var st := BotPolicy.BotState.new()
		for _i in range(6000):
			SaveTraceRun.bot_step(w, st, cfg)
			if w.state != "playing" or (w.in_safe_room and w.combat == null and w.depth >= 2 and w.turn > 150 * sd):
				break
		if w.state != "playing" or w.combat != null:
			continue
		var text := SaveGame.dumps(w)
		var v := SaveGame.from_text(text)
		assert_not_null(v, "seed %d" % sd)
		assert_eq(SaveGame.dumps(v), text, "seed %d re-dumps to the same text" % sd)
		SaveTraceRun.drop_unsaved(w)             # what Python's v7 save does not keep
		var sv := BotPolicy.BotState.new()
		st = BotPolicy.BotState.new()
		for n in range(700):
			if n >= 250 and w.combat == null and v.combat == null:     # a save needs both out of a fight
				break
			if w.state == "playing":
				SaveTraceRun.bot_step(w, st, cfg)
			if v.state == "playing":
				SaveTraceRun.bot_step(v, sv, cfg)
		assert_eq(SaveGame.dumps(v), SaveGame.dumps(w), "seed %d continues identically" % sd)
		done += 1
	assert_gt(done, 5, "enough bot runs reached a save point")


# --- Files -----------------------------------------------------------------------

func test_slot_path_and_directory_parameter() -> void:
	assert_eq(SaveGame.slot_path(), "user://saves/slot1.json")
	assert_eq(SaveGame.slot_path("/tmp/somewhere"), "/tmp/somewhere/slot1.json")
	var dir := TestHelpers.tmp_dir("save_dir_param") + "nested/saves"
	var path := SaveGame.slot_path(dir)
	DirAccess.remove_absolute(path)               # tmp_dir clears only the top level
	assert_false(SaveGame.has_save(path))
	var w := World.new(7)
	assert_true(SaveGame.save(w, path))             # creates the nested directories
	assert_true(SaveGame.has_save(path))
	assert_false(FileAccess.file_exists(dir + "/slot1.tmp"), "the temporary file is gone")
	assert_eq(FileAccess.get_file_as_string(path), SaveGame.dumps(w))
	assert_eq(SaveGame.dumps(SaveGame.load(path)), SaveGame.dumps(w))
	# Saving again replaces the slot.
	w.turn += 5
	assert_true(SaveGame.save(w, path))
	assert_eq(SaveGame.load(path).turn, w.turn)


func test_missing_and_corrupt_files_load_as_null() -> void:
	var dir := TestHelpers.tmp_dir("save_corrupt")
	assert_null(SaveGame.load(dir + "nope.json"))
	assert_push_error("cannot read")
	var f := FileAccess.open(dir + "bad.json", FileAccess.WRITE)
	f.store_string("{\"version\": 7, ")
	f.close()
	assert_null(SaveGame.load(dir + "bad.json"))
	assert_push_error("not a save")
	f = FileAccess.open(dir + "list.json", FileAccess.WRITE)
	f.store_string("[1, 2]")
	f.close()
	assert_null(SaveGame.load(dir + "list.json"))
	assert_push_error("not a save")


func _dict_of(w: World) -> Dictionary:
	return PyJsonLoad.parse(SaveGame.dumps(w))


func test_nested_gaps_and_odd_versions_are_errors_not_script_errors() -> void:
	var d := _dict_of(World.new(8))
	d["version"] = "7"
	assert_null(SaveGame.from_dict(d))
	assert_push_error("Unsupported save version")
	d["version"] = true
	assert_null(SaveGame.from_dict(d))
	assert_push_error("Unsupported save version")
	d = _dict_of(World.new(8))
	d["floor"].erase("tiles")
	assert_null(SaveGame.from_dict(d))
	assert_push_error("missing key 'tiles' in 'floor'")
	d = _dict_of(World.new(8))
	d["showrunner"]["rng"][0] = [1, 2]
	assert_null(SaveGame.from_dict(d))
	assert_push_error("not an RNG state")
	d = _dict_of(World.new(8))
	d["player"] = 3
	assert_null(SaveGame.from_dict(d))
	assert_push_error("not an object")


func test_missing_key_and_old_version_are_refused() -> void:
	var d := _dict_of(World.new(8))
	d.erase("shop")
	assert_null(SaveGame.from_dict(d))
	assert_push_error("missing key 'shop'")
	d = _dict_of(World.new(8))
	d["version"] = 6
	assert_null(SaveGame.from_dict(d))
	assert_push_error("Unsupported save version 6")
	d["version"] = 7.0
	assert_null(SaveGame.from_dict(d))
	assert_push_error("Unsupported save version")


# --- Loading restores the subsystems in place, and the loaded world is freed -------------

func _load_and_watch() -> Array:
	var text := SaveGame.dumps(World.new(11, ["dog", "Rex"]))
	var v := SaveGame.from_text(text)
	var training := v.training
	var ach := v.achievements
	var show := v.showrunner
	var ff := v.funfacts
	assert_true(training.world == v and ach.world == v and show.world == v and ff.world == v)
	v.wait()          # events still reach the subsystems the new World built
	return [weakref(v), weakref(training), weakref(ach), weakref(show), weakref(ff), weakref(v.shop)]


func test_loaded_world_and_its_subsystems_are_freed_together() -> void:
	var refs := _load_and_watch()
	for r in refs:
		assert_null(r.get_ref())


func test_loaded_world_keeps_the_event_subscriptions() -> void:
	var w := World.new(12)
	var v := SaveGame.from_text(SaveGame.dumps(w))
	var steps_before: int = v.training.steps
	v.events.emit("step", {"sneaky": false})
	assert_eq(v.training.steps, steps_before + 1)
	assert_eq(v.achievements.tracker.kills, w.achievements.tracker.kills)


# --- Parity with Python ------------------------------------------------------------

func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	for d in DirAccess.get_directories_at(path):
		_remove_tree(path.path_join(d))
	for f in DirAccess.get_files_at(path):
		DirAccess.remove_absolute(path.path_join(f))
	DirAccess.remove_absolute(path)


func test_saves_and_continuations_match_python() -> void:
	var py_dir := OS.get_environment("SAVE_TRACES")
	var root := OS.get_environment("CRAWL_ROOT")
	if py_dir == "" or not DirAccess.dir_exists_absolute(py_dir) or root == "":
		fail_test("SAVE_TRACES or CRAWL_ROOT is not set (run through scripts/gd_test.sh)")
		return
	var base := ProjectSettings.globalize_path(TestHelpers.tmp_dir("save_parity"))
	var gd_dir := base.path_join("gd")
	var py_x := base.path_join("py_x")
	_remove_tree(gd_dir)
	_remove_tree(py_x)
	var log: Array = []
	# Godot plays the seeds, saves, reloads, and loads Python's saves.
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", root + "/godot",
			"-s", "res://tools/save_trace.gd", "--", "--seeds", SEEDS, "--steps", str(STEPS),
			"--out-dir", gd_dir, "--load-dir", py_dir], log, true)
	assert_eq(code, 0, "save_trace.gd exit code: %s" % "".join(log).right(400))
	log = []
	code = OS.execute("python3", [root + "/scripts/save_diff.py", py_dir, gd_dir, "--seeds", SEEDS], log, true)
	var report := "".join(log)
	assert_eq(code, 0, "save_diff (Python saves loaded in Godot): %s" % report.left(1500))
	assert_true("SAVE PARITY OK" in report and "0 problems" in report and "cross-loaded 7" in report, report.left(300))
	# Python loads Godot's saves.
	log = []
	code = OS.execute("python3", [root + "/scripts/save_trace.py", "--seeds", SEEDS, "--steps", str(STEPS),
			"--out-dir", py_x, "--load-dir", gd_dir], log, true)
	assert_eq(code, 0, "save_trace.py exit code: %s" % "".join(log).right(400))
	log = []
	code = OS.execute("python3", [root + "/scripts/save_diff.py", py_x, gd_dir, "--seeds", SEEDS], log, true)
	report = "".join(log)
	assert_eq(code, 0, "save_diff (Godot saves loaded in Python): %s" % report.left(1500))
	assert_true("SAVE PARITY OK" in report and "0 problems" in report and "cross-loaded 14" in report, report.left(300))
	gut.p(report.strip_edges())

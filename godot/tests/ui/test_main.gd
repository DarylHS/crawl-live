extends TestCase
## The main scene (P7): it starts on the title with the game view hidden, real key events pushed through
## the window reach the AppState, and the command line options (--seed, --pet, --save-dir, --runs-dir)
## land in it. tools/e2e_run.gd is the full scripted run; this keeps its first steps in the suite.

const K := preload("res://tools/key_events.gd")


func _main() -> Main:
	var m: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	m.summary_on_headless = false
	add_child_autofree(m)
	m.app.settings_path = ""
	m.app.runs_dir = ""
	m.app.save_path = TestHelpers.tmp_dir("main_scene") + "slot.json"
	return m


func test_main_starts_on_the_title_and_keys_reach_the_app() -> void:
	var m := _main()
	await get_tree().process_frame
	assert_eq(m.app.scene, "title")
	assert_false(m.game_view.visible)
	m.app.seed_value = 7
	get_tree().root.push_input(K.key(KEY_ENTER))
	assert_eq(m.app.scene, "identity")
	for _i in 3:
		get_tree().root.push_input(K.key(KEY_ENTER))
	await get_tree().process_frame
	assert_eq(m.app.scene, "game")
	assert_true(m.game_view.visible)
	assert_eq(m.app.world.seed, 7)
	assert_true(m.hud.game_view.world == m.app.world)
	get_tree().root.push_input(K.key(KEY_ESCAPE))
	await get_tree().process_frame
	assert_eq(m.app.scene, "title")
	assert_false(m.game_view.visible)


func test_command_line_options_reach_the_app() -> void:
	var a := AppState.new({"settings_path": "", "runs_dir": ""})
	Main.configure(a, Main._parse_args(PackedStringArray(["--seed", "12", "--pet", "mouse", "--save-dir", "/tmp/x", "--runs-dir", "/tmp/y"])))
	assert_eq(a.seed_value, 12)
	assert_eq(a.pet_idx, Content.table("pets").keys().find("mouse"))
	assert_eq(a.save_path, "/tmp/x/slot1.json")
	assert_eq(a.settings_path, "/tmp/x/settings.json")
	assert_eq(a.runs_dir, "/tmp/y")


func test_a_default_main_uses_the_players_files_and_remembers_tab_and_f2() -> void:
	var a := AppState.new({"settings_path": "", "runs_dir": ""})
	Main.configure(a, {})
	assert_eq(a.settings_path, UserSettings.DEFAULT_PATH)
	assert_eq(a.runs_dir, "user://runs")
	assert_eq(a.save_path, SaveGame.slot_path())
	# Tab and F2 survive a restart (an own directory stands in for user://).
	var dir := TestHelpers.tmp_dir("main_persist")
	var m: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	m.summary_on_headless = false
	m.options = {"save-dir": dir.trim_suffix("/"), "runs-dir": dir + "runs"}
	add_child_autofree(m)
	await get_tree().process_frame
	for _i in 4:
		get_tree().root.push_input(K.key(KEY_ENTER))
	await get_tree().process_frame
	get_tree().root.push_input(K.key(KEY_TAB))
	get_tree().root.push_input(K.key(KEY_F2))
	await get_tree().process_frame
	assert_eq(m.app.view, "top")
	m.queue_free()
	await get_tree().process_frame
	var m2: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	m2.summary_on_headless = false
	m2.options = {"save-dir": dir.trim_suffix("/"), "runs-dir": dir + "runs"}
	add_child_autofree(m2)
	await get_tree().process_frame
	assert_eq(m2.app.view, "top")
	assert_eq(m2.app.settings["render_scale"], "sharp")
	assert_eq(m2.game_view.fp_view.render_scale, "sharp")

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

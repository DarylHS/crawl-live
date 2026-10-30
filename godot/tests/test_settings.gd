extends TestCase
## tests/test_settings.py: the view choice round-trips, and anything odd falls back to first-person
## (UserSettings, slice T5). A path of "" is Python's path=None.


func _write(path: String, text: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(text)
	f.close()


func test_view_round_trips() -> void:
	var path := TestHelpers.tmp_dir("settings_round_trip") + "settings.json"
	assert_true(UserSettings.save({"view": "top"}, path))
	assert_eq(UserSettings.load(path), {"view": "top", "render_scale": "retro", "effects": "on", "volume": 70,
			"muted": false})      # P5 added the render scale, P8 the effects level and sound; the file is just {"view": "top"}
	assert_eq(FileAccess.get_file_as_string(path), "{\"view\": \"top\"}")      # json.dumps text
	assert_true(UserSettings.save({"view": "fp"}, path))
	assert_eq(UserSettings.load(path)["view"], "fp")


func test_missing_or_corrupt_file_falls_back_to_fp() -> void:
	var dir := TestHelpers.tmp_dir("settings_corrupt")
	assert_eq(UserSettings.load(dir + "nope.json")["view"], "fp")
	var bad := dir + "bad.json"
	for text in ["{not json", "", "[1, 2]", "null"]:
		_write(bad, text)
		assert_eq(UserSettings.load(bad)["view"], "fp", text)


func test_unknown_view_falls_back_to_fp() -> void:
	var path := TestHelpers.tmp_dir("settings_unknown") + "settings.json"
	for value in ["sideways", 3, null]:
		UserSettings.save({"view": value}, path)
		assert_eq(UserSettings.load(path)["view"], "fp", str(value))


func test_empty_path_disables_persistence() -> void:
	assert_eq(UserSettings.load(""), UserSettings.DEFAULTS)
	assert_true(UserSettings.save({"view": "top"}, ""))      # no error, nothing written
	assert_eq(UserSettings.load("")["view"], "fp")


func test_settings_path_and_default() -> void:
	assert_eq(UserSettings.settings_path("/tmp/x"), "/tmp/x/settings.json")
	assert_eq(UserSettings.DEFAULT_PATH, "user://settings.json")
	var d := UserSettings.load("")
	d["view"] = "top"
	assert_eq(UserSettings.DEFAULTS["view"], "fp", "load returns a copy")
	assert_eq(UserSettings.VIEWS.size(), 2)


func test_save_creates_missing_directories_and_leaves_no_tmp() -> void:
	var dir := TestHelpers.tmp_dir("settings_dirs")
	var path := dir + "a/b/settings.json"
	assert_true(UserSettings.save({"view": "top"}, path))
	assert_eq(UserSettings.load(path)["view"], "top")
	assert_false(FileAccess.file_exists(dir + "a/b/settings.tmp"))

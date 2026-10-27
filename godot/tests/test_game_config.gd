extends TestCase
## GameConfig mirrors crawler/config.py (fixture: every upper-case constant, typed).


func after_each() -> void:
	TestHelpers.restore_patches()


func test_every_python_constant_matches() -> void:
	if not PyFixtures.available():
		pending("FIXTURES not set (run through scripts/gd_test.sh)")
		return
	var bad: Array = []
	var rows := PyFixtures.rows("config")
	for r in rows:
		var cfg: Object = GameConfig
		var got: Variant = cfg.get(r[0])
		var diff := strict_diff(got, r[1])
		if diff != "":
			bad.append([r[0], diff])
	assert_gt(rows.size(), 55)
	assert_eq(bad, [])


func test_floor_turns_matches_python() -> void:
	if not PyFixtures.available():
		pending("FIXTURES not set (run through scripts/gd_test.sh)")
		return
	for r in PyFixtures.rows("config_floor_turns"):
		assert_eq(GameConfig.floor_turns(r[0]), r[1])


func test_known_values() -> void:
	assert_eq(GameConfig.MAP_W, 120)
	assert_eq(GameConfig.RESPAWN_CAP, 1.25)
	assert_eq(GameConfig.TIMER_WARNINGS, [0.5, 0.25, 0.1])
	assert_eq(GameConfig.TEXT, [225, 222, 235])
	assert_eq(GameConfig.floor_turns(1), 720)
	assert_eq(GameConfig.floor_turns(3), 840)


func test_static_vars_can_be_patched_and_restored() -> void:
	TestHelpers.patch_static(GameConfig, "MAP_W", 40)
	assert_eq(GameConfig.MAP_W, 40)
	TestHelpers.restore_patches()
	assert_eq(GameConfig.MAP_W, 120)


func test_arrays_are_copies_of_the_content_cache() -> void:
	GameConfig.HEADLINER_DROPS.append("junk")
	var fresh: Array = Content.table("config")["config"]["HEADLINER_DROPS"]
	assert_eq(fresh.size(), 5)
	GameConfig.HEADLINER_DROPS.pop_back()

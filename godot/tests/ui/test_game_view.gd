extends TestCase
## GameView (P5): Tab switching and the settings file (tests/test_render.py
## `test_tab_toggles_and_remembers_the_view`, `test_tab_back_to_first_person_has_no_stale_hurt_flash`,
## the Tab part of `test_fp_combat_is_grid_locked`, `test_looking_diagonally_down_a_corridor`), the Graphics
## render scale (an owner addition: Retro, Sharp, Full), and run logging
## (tests/test_telemetry.py `test_game_logs_finished_player_runs`).

const SCENE := preload("res://scenes/game_view.tscn")


## A GameView that never touches the player's settings or runs unless a test gives it paths.
func _game(settings_path: String = "", runs_dir: String = "") -> GameView:
	var g: GameView = SCENE.instantiate()
	g.settings_path = settings_path
	g.runs_dir = runs_dir
	g.input_enabled = false
	add_child_autofree(g)
	g.size = Vector2(1024, 640)
	return g


## Python test_render `_start`: seed 1, the first companion, the default hero.
func _world(seed_value: int = 1) -> World:
	var hero := {"name": "Crawler", "gender": Content.table("genders").keys()[0],
			"backstory": Content.table("backstories").keys()[0]}
	return World.new(seed_value, [Content.table("pets").keys()[0], ""], hero)


func _empty(w: World, x: int, y: int) -> bool:
	return w.floor.walkable(x, y) and w.monster_at(x, y) == null and w.pet_at(x, y) == null


func test_tab_toggles_and_remembers_the_view() -> void:
	var path := TestHelpers.tmp_dir("game_view_tab") + "settings.json"
	var g := _game(path)
	assert_eq(g.view, "fp")
	assert_false(FileAccess.file_exists(path))               # first-person on a fresh install
	var w := _world()
	g.start(w)
	g.blocked = true                                          # an open menu swallows Tab
	assert_false(g.press(&"toggle_view"))
	assert_eq(g.view, "fp")
	g.blocked = false
	var turn := w.turn
	assert_true(g.press(&"toggle_view"))
	assert_eq(g.view, "top")
	assert_eq(w.turn, turn)                                   # switching view costs no turn
	assert_true(g.top_view.visible and not g.fp_view.visible)
	assert_eq(UserSettings.load(path)["view"], "top")
	var g2 := _game(path)
	assert_eq(g2.view, "top")                                 # the next launch starts on the map
	assert_true(g.press(&"toggle_view"))
	assert_eq(g.view, "fp")
	assert_true(g.fp_view.visible and not g.top_view.visible)
	assert_eq(_game(path).view, "fp")


func test_end_screens_ignore_tab() -> void:
	var g := _game()
	var w := _world()
	g.start(w)
	w.state = "dead"
	assert_false(g.press(&"toggle_view"))
	assert_eq(g.view, "fp")


func test_the_hidden_view_does_no_work() -> void:
	var g := _game()
	g.start(_world())
	assert_eq(g.fp_view.viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	g.press(&"toggle_view")
	assert_eq(g.fp_view.viewport.render_target_update_mode, SubViewport.UPDATE_DISABLED)
	assert_eq(g.fp_view.process_mode, Node.PROCESS_MODE_DISABLED)
	assert_eq(g.top_view.process_mode, Node.PROCESS_MODE_INHERIT)
	g.press(&"toggle_view")
	assert_eq(g.fp_view.viewport.render_target_update_mode, SubViewport.UPDATE_ALWAYS)
	assert_eq(g.top_view.process_mode, Node.PROCESS_MODE_DISABLED)


func test_keys_go_to_the_view_that_is_showing() -> void:
	var g := _game()
	var w := _world()
	w.monsters.clear()
	g.start(w)
	var spot := Vector2i.ZERO
	for y in w.floor.height:
		for x in w.floor.width:
			if spot == Vector2i.ZERO and _empty(w, x, y) and _empty(w, x + 1, y):
				spot = Vector2i(x, y)
	w.player.x = spot.x
	w.player.y = spot.y
	w.update_fov()
	g.press(&"toggle_view")                                   # the map: move_e goes east
	assert_true(g.press(&"move_e"))
	assert_eq(Vector2i(w.player.x, w.player.y), spot + Vector2i(1, 0))
	var angle := g.fp_view.logic.angle
	assert_false(g.press(&"turn_right"))                      # the map has no turning
	assert_eq(g.fp_view.logic.angle, angle)


func test_tab_back_to_first_person_has_no_stale_hurt_flash() -> void:
	var g := _game()
	var w := _world()
	g.start(w)
	g.fp_view.refresh(0.0)
	g.press(&"toggle_view")
	assert_eq(g.view, "top")
	w.player.hp -= 3                                          # hurt while on the map
	g.top_view.refresh()
	g.press(&"toggle_view")
	g.fp_view.refresh(0.0)
	assert_eq(g.fp_view.logic.flash, 0.0)
	assert_eq(g.fp_view.flash_rect.color.a, 0.0)
	assert_false(g.fp_view.logic.animating(w))


func test_tab_mid_combat_keeps_the_lock() -> void:
	var g := _game()
	var w := _world()
	w.monsters.clear()
	w.pet.downed = true
	g.start(w)
	var f := w.floor
	var found: Array = []
	for y in f.height:
		for x in f.width:
			if not found.is_empty() or not _empty(w, x, y) or f.is_safe(x, y):
				continue
			for d in [0, 2, 4, 6]:
				var s: Vector2i = FpLogic.DIRS8[d]
				var run := 0
				while _empty(w, x + s.x * (run + 1), y + s.y * (run + 1)):
					run += 1
				if run == 3 and not f.walkable(x + s.x * 4, y + s.y * 4) and found.is_empty():
					found = [Vector2i(x, y), d]
	assert_false(found.is_empty())
	var spot: Vector2i = found[0]
	var s: Vector2i = FpLogic.DIRS8[found[1]]
	w.player.x = spot.x
	w.player.y = spot.y
	w.player.max_hp = 999
	w.player.hp = 999
	var m := Entities.spawn_monster("goblin", spot.x + 3 * s.x, spot.y + 3 * s.y)
	m.hp = 999
	m.max_hp = 999
	w.monsters.append(m)
	w.update_fov()
	assert_true(w.join_combat(m))
	w.combat.round = 1
	m.stunned = 99
	g.fp_view.logic.angle = found[1] * 45
	g.fp_view.controller.update(1.0 / 30, [])
	assert_true(g.fp_view.logic.grid)
	g.press(&"toggle_view")                                   # Tab mid-combat keeps the lock
	g.press(&"toggle_view")
	g.fp_view.controller.update(1.0 / 30, [])
	assert_eq(g.view, "fp")
	assert_true(g.fp_view.logic.grid)
	w.combat = null                                           # the fight ends: free look again
	g.fp_view.controller.update(1.0 / 30, [])
	assert_false(g.fp_view.logic.grid)


func test_looking_diagonally_down_a_corridor() -> void:
	# Python only saved a screenshot; here both views must build and show the same place.
	var g := _game()
	var w := _world()
	g.start(w)
	var f := w.floor
	var best := [0, Vector2i.ZERO, 1]
	for y in f.height:
		for x in f.width:
			if not _empty(w, x, y):
				continue
			for d in [1, 3, 5, 7]:
				var s: Vector2i = FpLogic.DIRS8[d]
				var run := 0
				var c := Vector2i(x, y)
				while run < 8 and f.walkable(c.x + s.x, c.y + s.y) and f.walkable(c.x + s.x, c.y) \
						and f.walkable(c.x, c.y + s.y):
					run += 1
					c += s
				if run > best[0]:
					best = [run, Vector2i(x, y), d]
	assert_gte(best[0], 3)
	w.player.x = best[1].x
	w.player.y = best[1].y
	w.update_fov()
	g.fp_view.logic.angle = best[2] * 45.0
	g.fp_view.logic.cam = []
	g.fp_view.refresh(0.0)
	assert_eq(g.fp_view.logic.compass(), FpLogic.COMPASS8[best[2]])
	assert_eq(g.fp_view.minimap.compass_label.text, "Facing " + FpLogic.COMPASS8[best[2]])
	var ahead := g.fp_view.rig.ahead(1.0) - g.fp_view.rig.global_position
	var s: Vector2i = FpLogic.DIRS8[best[2]]
	assert_almost_eq(ahead.normalized().distance_to(Vector3(s.x, 0, s.y).normalized()), 0.0, 1e-4)
	g.press(&"toggle_view")
	assert_eq(g.top_view.cam_tile, TopView.camera(w))


# --- Render scale -----------------------------------------------------------------------------

func test_render_scale_sizes_and_the_unchanged_framing() -> void:
	var g := _game()
	g.start(_world())
	var fp := g.fp_view
	var cam := fp.rig.camera
	var fov := cam.fov
	var want := {"retro": Vector2i(320, 200), "sharp": Vector2i(640, 400), "full": Vector2i(1024, 640)}
	for choice: String in want:
		fp.set_render_scale(choice)
		assert_eq(fp.viewport.size, want[choice], choice)
		assert_eq(fp.viewport_size(), want[choice], choice)
		assert_almost_eq(float(fp.viewport.size.x) / fp.viewport.size.y, 1.6, 1e-6, choice)   # same aspect
		assert_eq(cam.fov, fov, choice)                       # same horizontal field of view
		assert_eq(cam.keep_aspect, Camera3D.KEEP_WIDTH, choice)
		assert_eq(fp.screen.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST if choice == "retro" \
				else CanvasItem.TEXTURE_FILTER_LINEAR, choice)
	fp.set_render_scale("nonsense")
	assert_eq(fp.render_scale, "retro")                       # anything unknown counts as Retro
	fp.set_render_scale("full")
	g.size = Vector2(800, 500)                                # "Full" follows the on-screen size
	await get_tree().process_frame
	assert_eq(fp.viewport.size, Vector2i(800, 500))


func test_f2_cycles_the_render_scale_and_it_is_remembered() -> void:
	var path := TestHelpers.tmp_dir("game_view_scale") + "settings.json"
	var g := _game(path)
	g.start(_world())
	assert_eq(g.fp_view.render_scale, "retro")                # the default
	assert_true(g.press(&"cycle_render_scale"))
	assert_eq(g.fp_view.render_scale, "sharp")
	assert_true(g.press(&"cycle_render_scale"))
	assert_eq(g.fp_view.render_scale, "full")
	assert_eq(UserSettings.load(path)["render_scale"], "full")
	assert_eq(_game(path).fp_view.render_scale, "full")       # the next launch keeps it
	assert_true(g.press(&"cycle_render_scale"))
	assert_eq(g.fp_view.render_scale, "retro")
	assert_eq(UserSettings.load(path)["render_scale"], "retro")
	g.press(&"toggle_view")                                   # the view and the scale share one file
	var saved := UserSettings.load(path)
	assert_eq(saved["view"], "top")
	assert_eq(saved["render_scale"], "retro")


func test_the_f2_and_tab_keys_are_in_the_input_map() -> void:
	assert_true(InputMap.has_action(&"toggle_view"))
	assert_true(InputMap.has_action(&"cycle_render_scale"))
	var tab := InputEventKey.new()
	tab.physical_keycode = KEY_TAB
	assert_true(InputMap.action_has_event(&"toggle_view", tab))
	var f2 := InputEventKey.new()
	f2.physical_keycode = KEY_F2
	assert_true(InputMap.action_has_event(&"cycle_render_scale", f2))


func test_billboards_and_walls_keep_their_framing_at_every_scale() -> void:
	# A monster two tiles ahead is at the same place in every viewport: its unprojected position
	# as a fraction of the frame is the same at 320, 640 and 1024 pixels wide.
	var g := _game()
	var w := _world()
	w.monsters.clear()
	g.start(w)
	g.fp_view.logic.cam = []
	g.fp_view.refresh(0.0)
	var cam := g.fp_view.rig.camera
	var point := g.fp_view.rig.ahead(2.0)
	var fractions: Array = []
	for choice in ["retro", "sharp", "full"]:
		g.fp_view.set_render_scale(choice)
		var screen := cam.unproject_position(point)
		fractions.append(snappedf(screen.x / g.fp_view.viewport.size.x, 0.001))
		fractions.append(snappedf(screen.y / g.fp_view.viewport.size.y, 0.001))
	assert_eq(fractions[0], fractions[2])
	assert_eq(fractions[0], fractions[4])
	assert_eq(fractions[1], fractions[3])
	assert_eq(fractions[1], fractions[5])


# --- Settings file ------------------------------------------------------------------------------

func test_settings_keep_the_view_and_render_scale_together() -> void:
	var path := TestHelpers.tmp_dir("game_view_settings") + "settings.json"
	assert_true(UserSettings.save({"view": "top", "render_scale": "sharp"}, path))
	assert_eq(UserSettings.load(path), {"view": "top", "render_scale": "sharp"})
	UserSettings.save({"view": "top", "render_scale": "huge"}, path)     # an unknown scale falls back
	assert_eq(UserSettings.load(path)["render_scale"], "retro")
	UserSettings.save({"view": "top"}, path)                              # an old file has no scale
	assert_eq(UserSettings.load(path), {"view": "top", "render_scale": "retro"})


# --- Run logging --------------------------------------------------------------------------------

func test_game_logs_finished_player_runs() -> void:
	var dir := TestHelpers.tmp_dir("game_view_runs")
	var g := _game("", dir)
	var w := _world(2)
	g.start(w)
	w.timer = 1
	g.press(&"wait")                                          # the floor collapses
	assert_eq(w.state, "dead")
	var rows := PyCsv.read_dicts(dir + "player_runs.csv")
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["outcome"], "collapse")
	assert_eq(rows[0]["source"], "player")
	g.press(&"wait")                                          # no second write
	assert_eq(PyCsv.read_dicts(dir + "player_runs.csv").size(), 1)
	assert_eq(g.logged_runs, 1)


func test_renders_each_floor_with_the_overlays() -> void:
	# Python test_renders_each_floor_with_the_overlays: every floor draws in both views with the
	# minimap and compass up (the per-floor mesh is checked in test_fp_scene.gd).
	var g := _game()
	var w := World.new(4, ["dog", "Rex"])
	g.start(w)
	for depth in range(1, 7):
		if depth > 1:
			w.new_floor(depth)
		g.fp_view.refresh(0.0)
		assert_eq(g.fp_view.viewport.size, Vector2i(320, 200))
		assert_true(g.fp_view.minimap.visible, "floor %d" % depth)
		assert_eq(g.fp_view.minimap.data.image.get_size(), Vector2i(192, 120))
		assert_true(g.fp_view.minimap.compass_label.text.begins_with("Facing "))
		g.top_view.refresh()
		assert_eq(g.top_view.cam_tile, TopView.camera(w))
	g.fp_view.hud = false                                       # a menu covers the view: no overlays
	g.fp_view.refresh(0.0)
	assert_false(g.fp_view.minimap.visible)

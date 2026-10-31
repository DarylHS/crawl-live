extends TestCase
## The top-down map's 32 px tiles zoom (P9) next to the 16 px glyph overview (test_top_view.gd keeps the
## pygame-exact overview honest): the 32 x 20 window and its camera, the tile sets (art, tint, fog, safe-room
## edges, flat-colour fallback), the zoom switch and the key that makes it, and the scaled boxes, brackets and bars.

const SCENE := preload("res://scenes/top_view.tscn")
const K := preload("res://tools/key_events.gd")


func after_each() -> void:
	SpriteArt.use_set(SpriteArt.DEFAULT_SET)
	SpriteArt.reset()


func _view() -> TopView:
	var v: TopView = SCENE.instantiate()
	v.input_enabled = false
	add_child_autofree(v)
	return v


func _empty(w: World, x: int, y: int) -> bool:
	return w.floor.walkable(x, y) and w.monster_at(x, y) == null and w.pet_at(x, y) == null


func test_the_tiles_zoom_shows_a_32_by_20_window_clamped_to_the_floor() -> void:
	var w := World.new(4)
	var f := w.floor
	var p := w.player
	for t in [Vector2i(0, 0), Vector2i(f.width - 1, f.height - 1), Vector2i(f.width / 2, f.height / 2),
			Vector2i(3, f.height - 2), Vector2i(f.width - 2, 5)]:
		p.x = t.x
		p.y = t.y
		var c := TopView.camera(w, 32, 20)
		assert_eq(c.x, mini(maxi(0, t.x - 16), maxi(0, f.width - 32)), str(t))
		assert_eq(c.y, mini(maxi(0, t.y - 10), maxi(0, f.height - 20)), str(t))
		assert_true(c.x + 32 <= f.width and c.y + 20 <= f.height)
	assert_eq(TopView.metrics("tiles"), [32, 20, 32])
	assert_eq(TopView.metrics("glyphs"), [64, 40, 16])
	assert_eq(TopView.ART_VIEW_W * TopView.ART_TILE, 1024)            # the same 1024 x 640 map area at both zooms
	assert_eq(TopView.ART_VIEW_H * TopView.ART_TILE, 640)
	assert_eq(TopView.camera(w), TopView.camera(w, 64, 40))            # the glyph camera is unchanged


func test_the_zoom_switches_tile_sets_and_the_map_scrolls_by_32() -> void:
	var v := _view()
	var w := World.new(4)
	w.player.x = w.floor.width / 2
	w.player.y = w.floor.height / 2
	v.start(w)
	assert_eq(v.zoom, "glyphs")                                        # the scene starts as pygame's picture
	assert_eq(v.terrain.tile_set.tile_size, Vector2i(16, 16))
	v.set_zoom("tiles")
	assert_eq(v.zoom, "tiles")
	assert_eq(v.terrain.tile_set.tile_size, Vector2i(32, 32))
	assert_eq(v.cam_tile, TopView.camera(w, 32, 20))
	assert_eq(v.map_node.position, Vector2(-v.cam_tile * 32))
	assert_true(v.marks.art_mode)
	v.set_zoom("glyphs")                                               # and back: the 16 px overview is untouched
	assert_eq(v.terrain.tile_set.tile_size, Vector2i(16, 16))
	assert_eq(v.cam_tile, TopView.camera(w))
	assert_eq(v.map_node.position, Vector2(-v.cam_tile * 16))
	assert_false(v.marks.art_mode)


func test_art_tiles_are_lit_dim_or_unseen_and_safe_rooms_have_pale_edges() -> void:
	var v := _view()
	var w := World.new(4)
	v.start(w)
	v.set_zoom("tiles")
	var f := w.floor
	var cam := v.cam_tile
	var counts := {"lit": 0, "dim": 0}
	for y in range(cam.y, cam.y + 20):
		for x in range(cam.x, cam.x + 32):
			var kind := v.tile_kind_at(x, y)
			if f.explored[y][x] == 0:
				assert_eq(kind, -1, "unseen %d,%d" % [x, y])
				continue
			var lit := w.visible.has(Vector2i(x, y))
			assert_eq(kind % 2, 0 if lit else 1, "%d,%d" % [x, y])      # even columns are lit, odd are dim
			counts["lit" if lit else "dim"] += 1
			if kind in [TopView.SAFE_WALL_LIT, TopView.SAFE_WALL_DIM]:
				assert_eq(f.tiles[y][x], DungeonFloor.WALL)
			if f.tiles[y][x] != DungeonFloor.WALL:
				assert_true(kind in [TopView.FLOOR_LIT, TopView.FLOOR_DIM, TopView.SAFE_LIT, TopView.SAFE_DIM], "%d,%d" % [x, y])
	assert_gt(counts["lit"], 20)
	# a safe room is walled in pale tiles all round, and only walls next to it
	var mask := TopView._safe_wall_mask(f)
	var edge := 0
	for i in mask.size():
		if mask[i] != 0:
			edge += 1
			assert_eq(f.tiles[i / f.width][i % f.width], DungeonFloor.WALL)
	assert_gt(edge, 10)


func test_tiles_keep_the_floors_tint_and_dim_by_the_fog_ratio_but_safe_rooms_stay_untinted() -> void:
	for depth in range(1, 7):
		var s2 := TopView.build_art_tile_set(depth).get_source(0) as TileSetAtlasSource
		var tint := FpLogic.depth_tint(depth)
		assert_eq(s2.get_tile_data(Vector2i(TopView.WALL_LIT, 0), 0).modulate, tint, "wall tint %d" % depth)
		assert_eq(s2.get_tile_data(Vector2i(TopView.WALL_B_LIT, 0), 0).modulate, tint)
		assert_eq(s2.get_tile_data(Vector2i(TopView.FLOOR_LIT, 0), 0).modulate, tint)
		assert_eq(s2.get_tile_data(Vector2i(TopView.SAFE_LIT, 0), 0).modulate, Color.WHITE)
		assert_eq(s2.get_tile_data(Vector2i(TopView.SAFE_WALL_LIT, 0), 0).modulate, Color.WHITE)
		var dim := s2.get_tile_data(Vector2i(TopView.FLOOR_DIM, 0), 0).modulate
		assert_almost_eq(dim.g, tint.g * TopView.DIM_K, 1e-5)
	# pygame's remembered tiles are 0.46 of the lit ones (WALL_DIM / WALL_LIT), which is where DIM_K comes from
	var lit := UiColours.c("WALL_LIT")
	var dim_c := UiColours.c("WALL_DIM")
	assert_almost_eq(dim_c.r / lit.r, TopView.DIM_K, 0.02)


func test_art_tiles_are_the_real_pictures_and_fall_back_to_flat_colours() -> void:
	var tile_set := TopView.build_art_tile_set(2)
	var atlas := (tile_set.get_source(0) as TileSetAtlasSource).texture.get_image()
	assert_eq(atlas.get_size(), Vector2i(320, 32))
	assert_true(atlas.get_region(Rect2i(0, 0, 32, 32)).get_data() == SpriteArt.supplied("tile:2:wall_0").get_data())
	SpriteArt.use_set(SpriteArt.PLACEHOLDER_SET)
	var flat := (TopView.build_art_tile_set(2).get_source(0) as TileSetAtlasSource).texture.get_image()
	assert_eq(flat.get_pixel(5, 5), UiColours.c("WALL_LIT"))          # no art: the glyph map's colours


func test_a_new_art_set_rebuilds_the_tiles() -> void:
	var v := _view()
	var w := World.new(4)
	v.start(w)
	v.set_zoom("tiles")
	var before := v.terrain.tile_set
	v.refresh()
	assert_true(v.terrain.tile_set == before)                          # nothing changed: nothing rebuilt
	SpriteArt.use_set(SpriteArt.PLACEHOLDER_SET)
	v.refresh()
	assert_false(v.terrain.tile_set == before)                         # the set changed: tiles made again
	assert_gt(v.written, 0)


func test_tiles_draw_sprites_with_scaled_boxes_brackets_and_bars() -> void:
	var v := _view()
	var w := World.new(4)
	w.monsters.clear()
	var p := w.player
	var tiles: Array[Vector2i] = []
	for n in DungeonFloor.NEIGHBOURS_8:
		if _empty(w, p.x + n.x, p.y + n.y):
			tiles.append(Vector2i(p.x + n.x, p.y + n.y))
	assert_gt(tiles.size(), 2)
	var boss := Bosses.spawn_boss(1, tiles[0].x, tiles[0].y)
	var act := Bosses.spawn_act("opening", "goblin", tiles[1].x, tiles[1].y)
	act.hp = 3
	w.monsters.append(boss)
	w.monsters.append(act)
	w.floor_items[tiles[2]] = ["tonic"]
	w.update_fov()
	v.start(w)
	v.set_zoom("tiles")
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(v.marks.drawn["boxes"], 2)                              # the Headliner's and the Act's tier boxes
	assert_eq(v.marks.drawn["bars"], 1)
	assert_eq(v.marks.drawn["brackets"], 0)
	assert_true(w.join_combat(act))
	w.update_fov()
	v.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(v.marks.drawn["brackets"], w.threats().size())
	assert_gt(w.threats().size(), 0)
	assert_gte(v.marks.drawn["glyphs"], 4)                            # you, the pet, two monsters and the item: one picture each


func test_z_zooms_the_map_in_and_out_only_in_the_map_view() -> void:
	var app := AppState.new({"settings_path": "", "runs_dir": ""})
	var w := World.new(2)
	app.attach_world(w)
	var seen: Array[String] = []
	app.map_zoom_changed.connect(func(z: String) -> void: seen.append(z))
	assert_eq(app.map_zoom, "glyphs")                                  # a bare AppState is pygame's picture
	app.set_view("fp")
	assert_false(app.toggle_zoom())                                    # nothing to zoom in the first-person view
	app.set_view("top")
	assert_true(app.toggle_zoom())
	assert_eq(app.map_zoom, "tiles")
	app.handle_key(K.key(KEY_Z))                                       # the real key
	assert_eq(app.map_zoom, "glyphs")
	assert_eq(seen, ["tiles", "glyphs"])
	app.open_overlay("inventory")
	assert_false(app.toggle_zoom())                                    # menus swallow it, as they do Tab
	assert_true(InputMap.has_action(&"zoom_map") and InputMap.has_action(&"cycle_art_set"))
	var keys := InputMap.action_get_events(&"zoom_map")
	assert_eq((keys[0] as InputEventKey).physical_keycode, KEY_Z)
	assert_eq((InputMap.action_get_events(&"cycle_art_set")[0] as InputEventKey).physical_keycode, KEY_F5)


func test_f5_cycles_the_art_sets_on_any_screen_and_says_so() -> void:
	var app := AppState.new({"settings_path": "", "runs_dir": ""})
	var notes: Array[String] = []
	app.setting_changed.connect(func(t: String) -> void: notes.append(t))
	var sets := SpriteArt.available_sets()
	app.handle_key(K.key(KEY_F5))                                      # on the title screen
	assert_eq(SpriteArt.art_set, sets[1 % sets.size()])
	assert_eq(notes[0], "Art set: %s" % SpriteArt.art_set)
	for _i in sets.size() - 1:
		app.handle_key(K.key(KEY_F5))
	assert_eq(SpriteArt.art_set, SpriteArt.DEFAULT_SET)                # a full lap


func test_a_game_view_in_plain_mode_keeps_the_glyph_overview() -> void:
	var g: GameView = preload("res://scenes/game_view.tscn").instantiate()
	g.settings_path = ""
	g.runs_dir = ""
	g.input_enabled = false
	g.set_plain(true)                                                  # the pygame pairing tools
	add_child_autofree(g)
	g.start(World.new(2))
	g.set_view("top")
	assert_eq(g.top_view.zoom, "glyphs")
	assert_eq(g.top_view.tile_px, 16)
	g.app.set_map_zoom("tiles")                                        # Z (or the real game's start) zooms in
	assert_eq(g.top_view.zoom, "tiles")
	assert_eq(g.top_view.tile_px, 32)

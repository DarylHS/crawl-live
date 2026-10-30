extends TestCase
## The top-down map (P5): Renderer._camera clamping, the lit / dim / unseen look of tiles in the
## TileMapLayer, what the glyph layer draws (boss tier boxes, provoke brackets, health bars), and the
## top-view half of tests/test_render.py `test_movement_follows_the_view` (the map moves by the
## compass, whichever way the 3D view looks).

const SCENE := preload("res://scenes/top_view.tscn")


func _view() -> TopView:
	var v: TopView = SCENE.instantiate()
	v.input_enabled = false
	add_child_autofree(v)
	return v


func _empty(w: World, x: int, y: int) -> bool:
	return w.floor.walkable(x, y) and w.monster_at(x, y) == null and w.pet_at(x, y) == null


func test_the_camera_centres_on_you_and_clamps_to_the_floor() -> void:
	var w := World.new(4)
	var f := w.floor
	var p := w.player
	for t in [Vector2i(0, 0), Vector2i(f.width - 1, f.height - 1), Vector2i(f.width / 2, f.height / 2),
			Vector2i(3, f.height - 2), Vector2i(f.width - 2, 5)]:
		p.x = t.x
		p.y = t.y
		var c := TopView.camera(w)
		assert_eq(c.x, mini(maxi(0, t.x - 32), maxi(0, f.width - 64)), str(t))
		assert_eq(c.y, mini(maxi(0, t.y - 20), maxi(0, f.height - 40)), str(t))
		assert_true(c.x >= 0 and c.y >= 0 and c.x + 64 <= f.width and c.y + 40 <= f.height)
	assert_eq(TopView.TILE, 16)
	assert_eq(TopView.VIEW_W * TopView.TILE, 1024)
	assert_eq(TopView.VIEW_H * TopView.TILE, 640)


func test_tiles_are_unseen_dim_or_lit_by_kind() -> void:
	var v := _view()
	var w := World.new(4)
	v.start(w)
	var f := w.floor
	var cam := v.cam_tile
	var counts := {"unseen": 0, "lit": 0, "dim": 0}
	for y in range(cam.y, cam.y + 40):
		for x in range(cam.x, cam.x + 64):
			var kind := v.tile_kind_at(x, y)
			if f.explored[y][x] == 0:
				assert_eq(kind, -1, "unseen %d,%d" % [x, y])
				counts["unseen"] += 1
				continue
			var lit := w.visible.has(Vector2i(x, y))
			var base := TopView.WALL_LIT if f.tiles[y][x] == DungeonFloor.WALL \
					else (TopView.SAFE_LIT if f.safe[y][x] != 0 else TopView.FLOOR_LIT)
			assert_eq(kind, base if lit else base + 1, "%d,%d" % [x, y])
			counts["lit" if lit else "dim"] += 1
	assert_gt(counts["lit"], 20)
	# Step away: tiles you can no longer see turn dim, and only the changed ones are written.
	var before := v.written
	assert_gt(before, 0)
	v.refresh()
	assert_eq(v.written, 0)                                  # nothing changed: nothing written
	for n in DungeonFloor.NEIGHBOURS_8:
		if _empty(w, w.player.x + n.x * 3, w.player.y + n.y * 3):
			w.player.x += n.x * 3
			w.player.y += n.y * 3
			break
	w.update_fov()
	v.refresh()
	assert_gt(v.written, 0)
	assert_lt(v.written, 64 * 40)


func test_the_map_scrolls_with_the_camera() -> void:
	var v := _view()
	var w := World.new(4)
	w.player.x = w.floor.width / 2
	w.player.y = w.floor.height / 2
	v.start(w)
	assert_eq(v.map_node.position, Vector2(-v.cam_tile * 16))
	assert_eq(v.cam_tile, TopView.camera(w))


func test_glyph_layer_draws_boxes_brackets_and_health_bars() -> void:
	var v := _view()
	var w := World.new(4)
	w.monsters.clear()
	var p := w.player
	var tiles: Array[Vector2i] = []
	for n in DungeonFloor.NEIGHBOURS_8:
		if _empty(w, p.x + n.x, p.y + n.y):
			tiles.append(Vector2i(p.x + n.x, p.y + n.y))
	assert_gt(tiles.size(), 1)
	var boss := Bosses.spawn_act("opening", "goblin", tiles[0].x, tiles[0].y)
	var plain := Entities.spawn_monster("goblin", tiles[1].x, tiles[1].y)
	plain.hp = 3
	w.monsters.append(boss)
	w.monsters.append(plain)
	w.update_fov()
	v.start(w)
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(v.marks.drawn["boxes"], 1)                    # the Act's tier box
	assert_eq(v.marks.drawn["bars"], 1)                     # the damaged goblin
	assert_eq(v.marks.drawn["brackets"], 0)                 # no fight: nothing provokes
	assert_true(w.join_combat(plain))
	w.update_fov()
	v.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(v.marks.drawn["brackets"], w.threats().size())
	assert_gt(w.threats().size(), 0)


func test_movement_follows_the_view_top_half() -> void:
	var w := World.new(1, [Content.table("pets").keys()[0], ""])
	w.monsters.clear()
	var v := _view()
	v.start(w)
	var spot := Vector2i.ZERO
	for y in w.floor.height:
		for x in w.floor.width:
			if spot == Vector2i.ZERO and _empty(w, x, y) and _empty(w, x + 1, y):
				spot = Vector2i(x, y)
	w.player.x = spot.x
	w.player.y = spot.y
	w.update_fov()
	assert_true(v.controller.press(&"move_e"))              # D / Right: east, whatever way a camera looks
	assert_eq(Vector2i(w.player.x, w.player.y), spot + Vector2i(1, 0))
	var turn := w.turn
	assert_true(v.controller.press(&"wait"))
	assert_eq(w.turn, turn + 1)
	assert_false(v.controller.press(&"walk_forward"))       # first-person keys do nothing here
	assert_false(v.controller.press(&"turn_left"))


func test_the_order_of_actions_puts_compass_moves_before_waiting() -> void:
	assert_eq(TopController.ORDER[0], &"descend")
	assert_true(TopController.ORDER.has(&"move_sw") and TopController.ORDER.has(&"wait"))

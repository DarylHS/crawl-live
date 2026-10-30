extends TestCase
## The first-person minimap (P5 parts of tests/test_firstperson.py: readable and tracks exploring,
## the window follows you, the caches follow the floor object; tests/test_render.py: the compass
## and the arrow follow the free angle). pytest read pixels off the screen surface; here MinimapImage
## makes the same pixels as an Image, and `pixel(x, y)` reads the middle of a tile.

const ACCENT := Color8(255, 196, 64)
const DANGER := Color8(235, 80, 80)


func _same(a: Color, b: Color) -> bool:
	return a.to_rgba32() == b.to_rgba32()


func test_minimap_is_readable_and_tracks_exploring() -> void:
	var w := World.new(6)
	w.monsters.clear()
	var mm := MinimapImage.new()
	var f := w.floor
	var p := w.player
	mm.redraw(w, 0.0)
	var win := MinimapImage.window(w)
	assert_eq(win.size, Vector2i(MinimapImage.WINDOW[0], MinimapImage.WINDOW[1]))
	assert_true(win.has_point(Vector2i(p.x, p.y)))
	var far := Vector2i(-1, -1)
	for y in range(win.position.y, win.end.y):
		for x in range(win.position.x, win.end.x):
			if far.x < 0 and f.tiles[y][x] != DungeonFloor.STAIRS and f.walkable(x, y) and f.safe[y][x] == 0 \
					and not w.visible.has(Vector2i(x, y)) and absi(x - p.x) + absi(y - p.y) > 6:
				far = Vector2i(x, y)
	assert_true(far.x >= 0)
	assert_eq(f.explored[far.y][far.x], 0)
	assert_false(_same(mm.pixel(far.x, far.y), MinimapImage.FLOOR))     # unexplored: backing only
	w._act_reward(Bosses.spawn_act("opening", "goblin", far.x, far.y))   # an Opening Act's map
	assert_eq(f.explored[far.y][far.x], 1)
	mm.redraw(w, 0.0)                                              # only the changed tiles redraw
	assert_true(_same(mm.pixel(far.x, far.y), MinimapImage.FLOOR))
	var seen := Vector2i(-1, -1)
	for t: Vector2i in w.visible:
		if seen.x < 0 and f.tiles[t.y][t.x] != DungeonFloor.STAIRS and f.safe[t.y][t.x] == 0 \
				and maxi(absi(t.x - p.x), absi(t.y - p.y)) > 3 and f.walkable(t.x, t.y) and win.has_point(t):
			seen = t
	assert_true(seen.x >= 0)
	assert_true(_same(mm.pixel(seen.x, seen.y), MinimapImage.IN_VIEW))

	var st := f.stairs[0]                                          # stand near the stairs to see them
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			if maxi(absi(dx), absi(dy)) == 3 and not w.visible.has(st) and f.walkable(st.x + dx, st.y + dy):
				p.x = st.x + dx
				p.y = st.y + dy
				w.update_fov()
	mm.redraw(w, 0.0)
	assert_true(w.visible.has(st))
	assert_true(w.stairs_locked)
	assert_true(_same(mm.pixel(st.x, st.y), DANGER))
	w.has_key = true
	mm.redraw(w, 0.0)
	assert_true(_same(mm.pixel(st.x, st.y), ACCENT))
	var lum := func(c: Color) -> float: return c.r + c.g + c.b
	assert_gt(lum.call(MinimapImage.FLOOR), 2.0 * lum.call(UiColours.c("FLOOR_LIT")))   # clearly lighter than before


func test_minimap_window_follows_you_and_stays_on_the_floor() -> void:
	var w := World.new(6)
	var f := w.floor
	var p := w.player
	var mw: int = MinimapImage.WINDOW[0]
	var mh: int = MinimapImage.WINDOW[1]
	var win := Rect2i()
	for t in [Vector2i(0, 0), Vector2i(f.width - 1, f.height - 1), Vector2i(f.width / 2, f.height / 2)]:
		p.x = t.x
		p.y = t.y
		win = MinimapImage.window(w)
		assert_true(win.position.x >= 0 and win.end.x <= f.width and win.position.y >= 0 and win.end.y <= f.height)
		assert_true(win.has_point(t))
	assert_eq(Vector2i(win.position.x + mw / 2, win.position.y + mh / 2), Vector2i(p.x, p.y))   # centred in the middle
	assert_true(MinimapImage.SCALE >= 4 and mw * MinimapImage.SCALE <= 1024 / 4)               # readable, and a corner only


func test_caches_follow_the_floor_object_not_its_id() -> void:
	var w := World.new(7)
	var mm := MinimapImage.new()
	for depth in [2, 3, 2, 3]:
		w.new_floor(depth)
		mm.redraw(w, 0.0)
		assert_true(mm.floor_ref == w.floor)
		for y in w.floor.height:
			assert_eq(mm.seen[y], w.floor.explored[y], "row %d" % y)


func test_compass_and_minimap_arrow_follow_the_free_angle() -> void:
	var w := World.new(1)
	var logic := FpLogic.new()
	logic.reset(w)
	logic.angle = 135.0
	assert_eq(logic.compass(), "SE")
	assert_true(logic.facing == 1 or logic.facing == 2)
	var mm := MinimapImage.new()
	mm.redraw(w, logic.angle)
	var s := MinimapImage.SCALE
	var win := MinimapImage.window(w)
	var cx := (w.player.x - win.position.x) * s + s / 2
	var cy := (w.player.y - win.position.y) * s + s / 2
	assert_true(_same(mm.image.get_pixel(cx + 2, cy + 2), Color.WHITE))        # tip points SE
	assert_false(_same(mm.image.get_pixel(cx - 4, cy - 4), Color.WHITE))
	for a in [0.0, 90.0, 180.0, 270.0]:
		mm.redraw(w, a)
		var tip := Vector2(sin(deg_to_rad(a)), -cos(deg_to_rad(a))) * 6.0
		assert_true(_same(mm.image.get_pixel(cx + int(tip.x), cy + int(tip.y)), Color.WHITE), "angle %d" % a)


func test_monsters_in_view_show_over_the_arrow() -> void:
	var w := World.new(1)
	w.monsters.clear()
	var p := w.player
	var m := Entities.spawn_monster("goblin", p.x, p.y)             # on your own tile: both show
	w.monsters.append(m)
	w.update_fov()
	var mm := MinimapImage.new()
	mm.redraw(w, 90.0)
	assert_true(_same(mm.pixel(p.x, p.y), DANGER))


func test_the_node_shows_the_image_and_the_facing_label() -> void:
	var node := Minimap.new()
	add_child_autofree(node)
	var w := World.new(1)
	node.update_from(w, 45.0, "NE")
	assert_eq(node.compass_label.text, "Facing NE")
	assert_eq(node.size, Vector2(node.data.image.get_size()))
	assert_eq(node.size, Vector2(48 * 4, 30 * 4))

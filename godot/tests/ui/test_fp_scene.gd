extends TestCase
## The first-person scene (P4 parts of tests/test_firstperson.py "renders each floor" and the
## floor caches): the floor mesh for every floor (face counts, slots, materials and tints), the
## placeholder textures, and fp_view.tscn driven headless (rebuild per floor, stairs lock, camera
## yaw, billboards). Pixels are checked by tools/screenshots.gd under Xvfb, not here.

const SCENE := preload("res://scenes/fp_view.tscn")


## Faces the mesh should have: one floor and one ceiling quad per open tile, one wall quad per
## side of an open tile that touches a wall or the map edge.
func _expected(f: DungeonFloor) -> Dictionary:
	var open := 0
	var stairs := 0
	var safe := 0
	var walls := 0
	var safe_walls := 0
	for y in f.height:
		for x in f.width:
			if f.tiles[y][x] == DungeonFloor.WALL:
				continue
			open += 1
			if f.tiles[y][x] == DungeonFloor.STAIRS:
				stairs += 1
			elif f.is_safe(x, y):
				safe += 1
			for d in FpLogic.DIRS:
				if not f.in_bounds(x + d.x, y + d.y) or f.tiles[y + d.y][x + d.x] == DungeonFloor.WALL:
					walls += 1
					if f.is_safe(x, y):
						safe_walls += 1
	return {"open": open, "stairs": stairs, "safe": safe, "walls": walls, "safe_walls": safe_walls}


func test_the_mesh_has_every_visible_face_on_every_floor() -> void:
	for seed_value in [4, 11]:
		var w := World.new(seed_value)
		for depth in range(1, 7):
			if depth > 1:
				w.new_floor(depth)
			var f := w.floor
			var mesh := FloorMeshBuilder.build_mesh(f)
			var faces := FloorMeshBuilder.faces(mesh)
			var e := _expected(f)
			var label := "seed %d floor %d" % [seed_value, depth]
			assert_eq(faces["floor"] + faces["safe_floor"] + faces["stairs"], e["open"], label)
			assert_eq(faces["ceiling"], e["open"], label)
			assert_eq(faces["stairs"], f.stairs.size(), label)
			assert_eq(faces["stairs"], e["stairs"], label)
			assert_eq(faces["safe_floor"], e["safe"], label)
			assert_eq(faces["wall_a"] + faces["wall_b"] + faces["safe_wall"], e["walls"], label)
			assert_eq(faces["safe_wall"], e["safe_walls"], label)
			assert_gt(faces["wall_a"], 0, label)
			assert_gt(faces["wall_b"], 0, label)       # both stone variants show up
			for i in mesh.get_surface_count():
				var slot := mesh.surface_get_name(i)
				assert_eq(mesh.surface_get_array_len(i), faces[slot] * 4, label + " " + slot)
				assert_eq(mesh.surface_get_array_index_len(i), faces[slot] * 6, label + " " + slot)


func test_materials_tint_stone_but_never_safe_rooms_or_stairs() -> void:
	var mats := FpMaterials.new()
	for depth in range(1, 7):
		var m := mats.for_depth(depth)
		var tint := FpLogic.depth_tint(depth)
		for slot in ["wall_a", "wall_b", "floor", "ceiling"]:
			assert_eq((m[slot] as StandardMaterial3D).albedo_color, tint, "floor %d %s" % [depth, slot])
		for slot in ["safe_wall", "safe_floor", "stairs"]:
			assert_eq((m[slot] as StandardMaterial3D).albedo_color, Color.WHITE, "floor %d %s" % [depth, slot])
		var locked := m["stairs_locked"] as StandardMaterial3D
		if FpTextures.art_image("tex:stairs_locked") != null:         # real art: a red grate of its own
			assert_true(locked.albedo_texture != (m["stairs"] as StandardMaterial3D).albedo_texture)
		else:                                                           # the open grate, tinted red
			assert_eq(locked.albedo_color, FpMaterials.LOCKED_TINT)
		for slot in m:
			var sm: StandardMaterial3D = m[slot]
			assert_eq(sm.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST)
			assert_true(sm.vertex_color_use_as_albedo)
	assert_true(mats.for_depth(6) == mats.for_depth(6))   # cached


func test_textures_are_64_px_without_mipmaps() -> void:
	for set_name in [SpriteArt.DEFAULT_SET, SpriteArt.PLACEHOLDER_SET]:         # the real art, then the code-drawn placeholders
		SpriteArt.use_set(set_name)
		for depth in range(1, 7):
			var images := FpTextures.images_for_depth(depth)
			assert_eq(images.keys(), Array(FpTextures.SLOTS))
			for slot in images:
				var img: Image = images[slot]
				assert_eq(img.get_size(), Vector2i(64, 64), "%s %d %s" % [set_name, depth, slot])
				assert_false(img.has_mipmaps(), slot)
		var images := FpTextures.images_for_depth(3)
		assert_gt(images["stairs"].get_pixel(7, 31).r, 0.3, set_name)           # the stairs grate has gold rings
		if set_name == SpriteArt.PLACEHOLDER_SET:
			# Mortar lines are darker than the bricks.
			var brick: Image = images["wall_a"]
			assert_lt(brick.get_pixel(5, 0).get_luminance(), brick.get_pixel(5, 8).get_luminance())
	SpriteArt.use_set(SpriteArt.DEFAULT_SET)


func test_the_real_textures_are_near_neutral_and_never_brighter_than_the_tint_allows() -> void:
	# Art bible section 3: stone is authored near-neutral and mid-value (no pure white: it would clip under the
	# 1.05 tint of floor 5 and 6, no strong hue: it would fight the tint). Safe rooms and the stairs are exempt.
	SpriteArt.use_set(SpriteArt.DEFAULT_SET)
	for depth in range(1, 7):
		var images := FpTextures.images_for_depth(depth)
		for slot in FpMaterials.TINTED:
			var img: Image = images[slot]
			var sum := 0.0
			var chroma := 0.0
			var peak := 0.0
			for y in 64:
				for x in 64:
					var c := img.get_pixel(x, y)
					sum += c.get_luminance()
					chroma += maxf(c.r, maxf(c.g, c.b)) - minf(c.r, minf(c.g, c.b))
					peak = maxf(peak, maxf(c.r, maxf(c.g, c.b)))
			var label := "floor %d %s" % [depth, slot]
			assert_between(sum / 4096.0, 0.1, 0.5, label + " mean luminance")
			assert_lt(chroma / 4096.0, 0.16, label + " mean chroma")
			assert_lt(peak, 0.88, label + " brightest channel")


func _view() -> FpView:
	var v: FpView = SCENE.instantiate()
	v.input_enabled = false
	add_child_autofree(v)
	return v


func test_the_view_builds_for_every_floor_and_rebuilds_on_a_new_one() -> void:
	var v := _view()
	var w := World.new(4, ["dog", "Rex"])
	v.start(w)
	assert_not_null(v.floor_mesh)
	assert_eq(v.viewport.size, Vector2i(320, 200))
	var seen: Array = []
	for depth in range(1, 7):
		if depth > 1:
			w.new_floor(depth)
		v.refresh(0.0)
		var mesh := v.floor_mesh.mesh as ArrayMesh
		assert_false(seen.has(mesh), "floor %d has a fresh mesh" % depth)
		seen.append(mesh)
		assert_eq(v.level.get_child_count(), 1)       # the old floor is gone
		var i := mesh.surface_find_by_name("wall_a")
		var mat := mesh.surface_get_material(i) as StandardMaterial3D
		assert_eq(mat.albedo_color, FpLogic.depth_tint(depth))
		assert_lt(v.build_ms, 2000.0)
		v.refresh(0.0)                                  # same floor: no rebuild
		assert_true(v.floor_mesh.mesh == mesh)


func test_stairs_swap_to_the_locked_grate_and_back() -> void:
	var v := _view()
	var w := World.new(6)
	v.start(w)
	var mesh := v.floor_mesh.mesh as ArrayMesh
	var i := mesh.surface_find_by_name("stairs")
	assert_true(w.stairs_locked)
	var locked := v.floor_mesh.get_surface_override_material(i) as StandardMaterial3D
	assert_not_null(locked)
	assert_true(locked.albedo_color == FpMaterials.LOCKED_TINT or FpTextures.art_image("tex:stairs_locked") != null)
	w.has_key = true                                    # the Headliner's key opens them
	v.refresh(0.0)
	assert_null(v.floor_mesh.get_surface_override_material(i))
	assert_eq((mesh.surface_get_material(i) as StandardMaterial3D).albedo_color, Color.WHITE)


func test_the_camera_looks_where_the_logic_looks() -> void:
	var v := _view()
	var w := World.new(4)
	v.start(w)
	for a in [0.0, 45.0, 90.0, 135.0, 180.0, 270.0, 300.0]:
		v.logic.angle = a
		v.logic.update_camera(w, 1.0)
		v.refresh(0.0)
		var eye := v.rig.global_position
		assert_almost_eq(eye.x, w.player.x + 0.5, 1e-5)
		assert_almost_eq(eye.z, w.player.y + 0.5, 1e-5)
		assert_almost_eq(eye.y, 0.4375, 1e-6)
		var ahead := v.rig.ahead(1.0) - eye             # tile space: x east, z south
		var want := Vector3(sin(deg_to_rad(a)), 0.0, -cos(deg_to_rad(a)))
		assert_almost_eq(ahead.distance_to(want), 0.0, 1e-5, "angle %s" % a)
	assert_almost_eq(v.rig.camera.fov, 69.98, 0.01)     # 2 atan(0.7), horizontal
	assert_eq(v.rig.camera.keep_aspect, Camera3D.KEEP_WIDTH)
	assert_almost_eq(v.rig.torch.omni_range, FpLogic.LIGHT, 1e-6)


func test_markers_show_what_the_player_can_see() -> void:
	var v := _view()
	var w := World.new(4, ["dog", "Rex"])
	v.start(w)
	assert_eq(v.billboards.shown, _in_front(v, w))
	var p := w.player
	w.monsters.clear()
	var tile := Vector2i(p.x, p.y)
	for n in DungeonFloor.NEIGHBOURS_8:
		if w.floor.walkable(p.x + n.x, p.y + n.y):
			tile = Vector2i(p.x + n.x, p.y + n.y)
			break
	v.logic.angle = rad_to_deg(atan2(tile.x - p.x, -(tile.y - p.y)))   # look at the neighbour
	var g := Entities.spawn_monster("goblin", tile.x, tile.y)
	w.monsters.append(g)
	w.update_fov()
	v.logic.cam = []
	v.refresh(0.0)
	assert_eq(v.billboards.shown, _in_front(v, w))
	assert_gt(v.billboards.shown, 0)


## What should be shown: everything in view that is more than Python's 0.2 tiles in front of the eye.
func _in_front(v: FpView, w: World) -> int:
	var cam := v.logic.cam
	var fwd := Vector2(cos(cam[2]), sin(cam[2]))
	var tiles: Array[Vector2i] = []
	for m in w.monsters:
		tiles.append(Vector2i(m.x, m.y))
	if w.active_pet != null:
		tiles.append(Vector2i(w.pet.x, w.pet.y))
	tiles.append_array(w.floor_items.keys())
	tiles.append_array(w.floor.stairs)
	tiles.append_array(w.floor.furniture.keys())
	var n := 0
	for t in tiles:
		if w.visible.has(t) and (t.x + 0.5 - cam[0]) * fwd.x + (t.y + 0.5 - cam[1]) * fwd.y > 0.2:
			n += 1
	return n


func test_light_never_brightens_past_the_texture_near_the_eye() -> void:
	# Python only darkens with distance ((1 - d / 8.5) ^ 1.3): ambient plus a face-on torch must
	# stay at about 1, the torch must not grow towards the eye (no 1 / d hot spot), and the fog
	# (not the light) does the falloff to black at LIGHT.
	var v := _view()
	var env: Environment = (v.get_node("Viewport/Environment") as WorldEnvironment).environment
	var torch := v.rig.torch
	assert_lt(env.ambient_light_energy + torch.light_energy, 1.05)
	assert_eq(torch.omni_attenuation, 0.0)
	assert_eq(env.fog_mode, Environment.FOG_MODE_DEPTH)
	assert_almost_eq(env.fog_depth_end, FpLogic.LIGHT, 1e-6)
	assert_eq(env.fog_light_color, Color.BLACK)
	for slot in ["stairs", "stairs_locked"]:              # the grate is not lit from inside
		assert_false((v.materials.for_depth(1)[slot] as StandardMaterial3D).emission_enabled)


func test_a_monster_ahead_shows_and_w_attacks_it() -> void:
	# Python test_render `test_forward_attacks_and_a_monster_in_view_draws`.
	var v := _view()
	var w := World.new(1, [Content.table("pets").keys()[0], ""])
	w.monsters.clear()
	v.start(w)
	var p := w.player
	var f := Vector2i.ZERO
	for _i in 4:                                        # face an open tile
		f = v.logic.relative("forward")
		if w.floor.walkable(p.x + f.x, p.y + f.y) and w.pet_at(p.x + f.x, p.y + f.y) == null \
				and w.floor.walkable(p.x + 2 * f.x, p.y + 2 * f.y) and w.pet_at(p.x + 2 * f.x, p.y + 2 * f.y) == null:
			break
		v.logic.turn(1)
	assert_false(w.in_safe_room)
	var base := v.billboards.shown
	w.monsters.append(Entities.spawn_monster("goblin", p.x + 2 * f.x, p.y + 2 * f.y))
	w.update_fov()
	v.refresh(0.0)
	assert_eq(v.billboards.shown, base + 1)                # two tiles ahead: drawn
	w.monsters.clear()
	var goblin := Entities.spawn_monster("goblin", p.x + f.x, p.y + f.y)
	w.monsters.append(goblin)
	w.update_fov()
	v.refresh(0.0)
	assert_eq(v.billboards.shown, base + 1)                # adjacent: drawn
	var turn := w.turn
	var pos := Vector2i(p.x, p.y)
	var attacks: Array = []
	w.events.subscribe("player_attack", func(_n: String, d: Dictionary) -> void: attacks.append(d))
	v.controller.press(&"walk_forward")                 # bump: attack (hit or miss), don't move
	assert_eq(Vector2i(p.x, p.y), pos)
	assert_eq(attacks.size(), 1)
	# The attack starts combat and is your action; a one-hit kill ends it and passes the turn.
	if w.combat != null:
		assert_false(w.combat.has("action"))
	else:
		assert_eq(w.turn, turn + 1)


func _key(code: Key, pressed: bool, shift := false) -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = code
	e.physical_keycode = code
	e.shift_pressed = shift
	e.pressed = pressed
	if code == KEY_PERIOD:
		e.unicode = 62 if shift else 46
	return e


func test_keys_reach_the_rules_through_the_input_map() -> void:
	var v: FpView = SCENE.instantiate()
	add_child_autofree(v)
	var w := World.new(4)
	w.monsters.clear()
	v.start(w)
	var a := v.logic.angle
	Input.parse_input_event(_key(KEY_E, true))          # a tap turns 45 degrees, for free
	Input.flush_buffered_events()
	Input.parse_input_event(_key(KEY_E, false))
	Input.flush_buffered_events()
	assert_eq(v.logic.angle, PyMath.fmod_py(a + 45, 360))
	assert_eq(w.turn, 0)
	Input.parse_input_event(_key(KEY_PERIOD, true))     # "." waits a turn
	Input.flush_buffered_events()
	Input.parse_input_event(_key(KEY_PERIOD, false))
	Input.flush_buffered_events()
	assert_eq(w.turn, 1)
	Input.parse_input_event(_key(KEY_PERIOD, true, true))   # ">" off the stairs: no turn passes
	Input.flush_buffered_events()
	Input.parse_input_event(_key(KEY_PERIOD, false, true))
	Input.flush_buffered_events()
	assert_eq(w.turn, 1)
	assert_eq(w.messages.lines[-1][0], "There are no stairs here.")


func test_hurt_flash_shows_and_menus_dim_the_view() -> void:
	var v := _view()
	var w := World.new(4)
	v.start(w)
	assert_eq(v.flash_rect.color.a, 0.0)
	w.player.hp -= 3
	v.refresh(0.0)
	assert_gt(v.flash_rect.color.a, 0.3)
	v.refresh(1.0)
	v.refresh(0.0)
	assert_eq(v.flash_rect.color.a, 0.0)                # faded within a second
	v.hud = false
	v.refresh(0.0)
	assert_lt(v.screen.modulate.r, 1.0)

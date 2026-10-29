extends TestCase
## The first-person scene (P4 parts of tests/test_firstperson.py "renders each floor" and the
## floor caches): the floor mesh for every floor (face counts, slots, materials and tints), the
## placeholder textures, and fp_view.tscn driven headless (rebuild per floor, stairs lock, camera
## yaw, markers). Pixels are checked by tools/screenshots.gd under Xvfb, not here.

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
		assert_ne((m["stairs_locked"] as StandardMaterial3D).albedo_color, Color.WHITE)
		for slot in m:
			var sm: StandardMaterial3D = m[slot]
			assert_eq(sm.texture_filter, BaseMaterial3D.TEXTURE_FILTER_NEAREST)
			assert_true(sm.vertex_color_use_as_albedo)
	assert_true(mats.for_depth(6) == mats.for_depth(6))   # cached


func test_textures_are_64_px_without_mipmaps() -> void:
	var images := FpTextures.images_for_depth(3)
	assert_eq(images.keys(), Array(FpTextures.SLOTS))
	for slot in images:
		var img: Image = images[slot]
		assert_eq(img.get_size(), Vector2i(64, 64), slot)
		assert_false(img.has_mipmaps(), slot)
	# Mortar lines are darker than the bricks, the stairs grate has gold rings.
	var brick: Image = images["wall_a"]
	assert_lt(brick.get_pixel(5, 0).get_luminance(), brick.get_pixel(5, 8).get_luminance())
	assert_gt(images["stairs"].get_pixel(7, 31).r, 0.3)


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
	assert_eq(locked.albedo_color, FpMaterials.LOCKED_TINT)
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
		assert_almost_eq(eye.y, 0.5, 1e-6)
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
	var want := 0
	var monsters := 0
	for m in w.monsters:
		if w.visible.has(Vector2i(m.x, m.y)):
			monsters += 1
	want += monsters
	if w.active_pet != null and w.visible.has(Vector2i(w.pet.x, w.pet.y)):
		want += 1
	for t in w.floor_items:
		if w.visible.has(t):
			want += 1
	for t in w.floor.stairs:
		if w.visible.has(t):
			want += 1
	for t in w.floor.furniture:
		if w.visible.has(t):
			want += 1
	assert_eq(v.markers.shown, want)
	var p := w.player
	w.monsters.clear()
	var g := Entities.spawn_monster("goblin", p.x, p.y)   # on a visible tile for sure
	w.monsters.append(g)
	v.refresh(0.0)
	assert_eq(v.markers.shown, want - monsters + 1)


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

extends TestCase
## Sprites and billboards (P5): tests/test_firstperson.py `test_every_creature_has_a_sprite`, plus
## the art bible's rules for the placeholder art (32 x 32, binary alpha, tier outlines, feet on the
## floor) and for the billboards (sizes by kind, feet on the floor, health bars on the damaged,
## fog-only shading). Pixels on screen are checked by tools/screenshots.gd under Xvfb.

const SCENE := preload("res://scenes/fp_view.tscn")


func after_each() -> void:
	SpriteArt.reset()


func _alpha_is_binary(img: Image) -> bool:
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			if a != 0.0 and a != 1.0:
				return false
	return true


func test_every_creature_has_a_sprite() -> void:
	var keys: Array[String] = []
	for k: String in Content.table("monsters"):
		keys.append("mon:" + k)
	for d: String in Content.table("bosses"):
		keys.append("boss:boss_" + d)
	for k: String in Content.table("pets"):
		keys.append("pet:" + k)
	assert_gt(keys.size(), 14)
	for k in keys:
		var s := SpriteArt.creature(k, [200, 100, 50])
		assert_eq(s.get_size(), Vector2i(32, 32), k)
		assert_gt(SpriteArt.bounds(s).size.x, 8, k)
		assert_true(_alpha_is_binary(s), k)


func test_every_asset_key_has_an_image() -> void:
	var keys := SpriteArt.all_keys()
	assert_gt(keys.size(), 50)
	assert_true(keys.has("mon:goblin") and keys.has("mon:opening_goblin") and keys.has("mon:featured_golem"))
	assert_true(keys.has("boss:boss_3") and keys.has("pet:budgie") and keys.has("item:pan"))
	assert_true(keys.has("furn:counter") and keys.has("fx:stairs_locked"))
	for k in keys:
		var kind := k.get_slice(":", 0)
		var nm := k.get_slice(":", 1)
		var img: Image
		match kind:
			"item":
				img = SpriteArt.item(nm)
			"furn":
				img = SpriteArt.furniture(nm)
			"fx":
				img = SpriteArt.stairs(nm == "stairs_locked")
			_:
				img = SpriteArt.creature(k, [180, 180, 180])
		assert_eq(img.get_size(), Vector2i(32, 32), k)
		assert_gt(SpriteArt.bounds(img).size.x, 4, k)
		assert_true(_alpha_is_binary(img), k)


func test_monster_keys_follow_the_art_bible() -> void:
	assert_eq(SpriteArt.monster_key(Entities.spawn_monster("goblin", 0, 0)), "mon:goblin")
	assert_eq(SpriteArt.monster_key(Bosses.spawn_act("opening", "brute", 0, 0)), "mon:opening_brute")
	assert_eq(SpriteArt.monster_key(Bosses.spawn_act("featured", "golem", 0, 0)), "mon:featured_golem")
	assert_eq(SpriteArt.monster_key(Bosses.spawn_boss(4, 0, 0)), "boss:boss_4")


func test_bosses_wear_their_tier_colour_and_others_a_dark_outline() -> void:
	var tiers: Dictionary = Content.table("ui_config")["firstperson"]["TIER_OUTLINE"]
	for tier: String in tiers:
		var c: Array = tiers[tier]
		var want := Color8(c[0], c[1], c[2])
		var img := SpriteArt.creature("mon:goblin", [120, 190, 80], tier)
		var found := false
		for y in 32:
			for x in 32:
				if img.get_pixel(x, y).is_equal_approx(want):
					found = true
		assert_true(found, tier)
	var plain := SpriteArt.creature("mon:goblin", [120, 190, 80])
	var used := plain.get_used_rect()
	var edge := plain.get_pixel(used.position.x + used.size.x / 2, used.position.y)
	assert_true(edge.is_equal_approx(SpriteArt.OUTLINE))


func test_light_comes_from_above_the_lower_half_is_darker() -> void:
	var img := SpriteArt.creature("mon:brute", [200, 120, 70])
	var top := 0.0
	var bottom := 0.0
	var n_top := 0
	var n_bottom := 0
	for y in 32:
		for x in 32:
			var p := img.get_pixel(x, y)
			if p.a == 0.0 or p.is_equal_approx(SpriteArt.OUTLINE):
				continue
			if y < 14:
				top += p.get_luminance()
				n_top += 1
			elif y >= 18:
				bottom += p.get_luminance()
				n_bottom += 1
	assert_lt(bottom / n_bottom, top / n_top)


func test_a_registered_image_replaces_the_placeholder_and_still_gets_finished() -> void:
	var art := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	art.fill_rect(Rect2i(8, 8, 16, 20), Color8(250, 0, 250))
	SpriteArt.register("mon:goblin", art)
	var img := SpriteArt.creature("mon:goblin", [120, 190, 80])
	assert_eq(SpriteArt.bounds(img), Rect2i(7, 7, 18, 22))     # the art plus a one pixel outline
	assert_gt(img.get_pixel(16, 10).r, img.get_pixel(16, 10).g)   # magenta art, not the green plan
	var act := SpriteArt.creature("mon:opening_goblin", [120, 190, 80], "opening")
	assert_eq(SpriteArt.bounds(act), Rect2i(7, 7, 18, 22))     # an Act without art uses its base
	SpriteArt.reset()
	assert_ne(SpriteArt.bounds(SpriteArt.creature("mon:goblin", [120, 190, 80])), Rect2i(7, 7, 18, 22))


func _view() -> FpView:
	var v: FpView = SCENE.instantiate()
	v.input_enabled = false
	add_child_autofree(v)
	return v


## The Sprite3D nodes shown, in pool order.
func _shown(b: Billboards) -> Array[Sprite3D]:
	var out: Array[Sprite3D] = []
	for child in b.get_children():
		var s := child as Sprite3D
		if s != null and s.visible and s.material_override != null and s.get("texture") != null \
				and s.texture.get_width() == 32:
			out.append(s)
	return out


func test_billboard_sizes_and_feet() -> void:
	var v := _view()
	var w := World.new(1, ["dog", "Rex"])
	w.monsters.clear()
	v.start(w)
	var p := w.player
	var f := Vector2i.ZERO
	for _i in 4:
		f = v.logic.relative("forward")
		if w.floor.walkable(p.x + 2 * f.x, p.y + 2 * f.y) and w.floor.walkable(p.x + f.x, p.y + f.y):
			break
		v.logic.turn(1)
	var wall := FloorMeshBuilder.WALL_H
	var cases := [
		[Entities.spawn_monster("goblin", p.x + 2 * f.x, p.y + 2 * f.y), 0.62 + 0.03 * 9 / 4.0],
		[Bosses.spawn_act("opening", "goblin", p.x + 2 * f.x, p.y + 2 * f.y), 0.85],
		[Bosses.spawn_act("featured", "goblin", p.x + 2 * f.x, p.y + 2 * f.y), 0.95],
		[Bosses.spawn_boss(1, p.x + 2 * f.x, p.y + 2 * f.y), 1.0],
	]
	for c in cases:
		w.monsters.clear()
		w.monsters.append(c[0])
		w.update_fov()
		v.refresh(0.0)
		var shown := _shown(v.billboards)
		var sprite: Sprite3D = null
		for s in shown:
			if absf(s.position.x - (p.x + 2 * f.x + 0.5)) < 1e-4 and absf(s.position.z - (p.y + 2 * f.y + 0.5)) < 1e-4:
				sprite = s
		assert_not_null(sprite, (c[0] as Monster).name)
		if sprite == null:
			continue
		var height := sprite.pixel_size * sprite.texture.get_height()
		assert_almost_eq(height, float(c[1]) * wall, 1e-5, (c[0] as Monster).name)
		assert_almost_eq(sprite.position.y - height / 2.0, 0.0, 1e-5)    # feet on the floor
		assert_eq(sprite.texture.get_width(), 32)
	# pet 0.5, items 0.32, furniture 0.75, the stairs arrow floats
	w.monsters.clear()
	w.pet.x = p.x + f.x
	w.pet.y = p.y + f.y
	w.floor_items[Vector2i(p.x + 2 * f.x, p.y + 2 * f.y)] = ["tonic"]
	w.update_fov()
	v.refresh(0.0)
	var heights: Array = []
	for s in _shown(v.billboards):
		heights.append(snappedf(s.pixel_size * s.texture.get_height() / wall, 0.001))
	assert_true(heights.has(0.5) and heights.has(0.32), str(heights))


func test_damaged_monsters_get_a_health_bar_and_healthy_ones_do_not() -> void:
	var v := _view()
	var w := World.new(1)
	w.monsters.clear()
	v.start(w)
	var p := w.player
	var g := Entities.spawn_monster("goblin", p.x, p.y)       # beside you: on a visible tile
	var tile := Vector2i.ZERO
	for n in DungeonFloor.NEIGHBOURS_8:
		if w.floor.walkable(p.x + n.x, p.y + n.y):
			tile = Vector2i(p.x + n.x, p.y + n.y)
			break
	g.x = tile.x
	g.y = tile.y
	w.monsters.append(g)
	w.update_fov()
	v.logic.angle = rad_to_deg(atan2(tile.x - p.x, -(tile.y - p.y)))
	v.logic.cam = []
	v.refresh(0.0)
	var bars := 0
	for child in v.billboards.get_children():
		var s := child as Sprite3D
		if s != null and s.visible and s.texture != null and s.texture.get_width() == 64:
			bars += 1
	assert_eq(bars, 0)
	g.hp = g.max_hp / 2
	v.refresh(0.0)
	for child in v.billboards.get_children():
		var s := child as Sprite3D
		if s != null and s.visible and s.texture != null and s.texture.get_width() == 64:
			bars += 1
	assert_eq(bars, 1)


func test_sprites_are_shaded_by_fog_alone_with_pythons_floor() -> void:
	var v := _view()
	var w := World.new(1)
	w.monsters.clear()
	var p := w.player
	var tile := Vector2i.ZERO
	for n in DungeonFloor.NEIGHBOURS_8:
		if w.floor.walkable(p.x + n.x, p.y + n.y):
			tile = Vector2i(p.x + n.x, p.y + n.y)
			break
	w.monsters.append(Entities.spawn_monster("goblin", tile.x, tile.y))
	w.update_fov()
	v.start(w)
	v.logic.angle = rad_to_deg(atan2(tile.x - p.x, -(tile.y - p.y)))
	v.logic.cam = []
	v.refresh(0.0)
	var b := v.billboards
	var slot_mat: ShaderMaterial = null
	for child in b.get_children():
		var s := child as Sprite3D
		if s != null and s.material_override is ShaderMaterial and s.visible:
			slot_mat = s.material_override
	assert_not_null(slot_mat)
	assert_almost_eq(Billboards.MIN_BRIGHT, 0.12, 1e-9)
	assert_true(slot_mat.shader.code.contains("min_bright = 0.12"))
	assert_true(slot_mat.shader.code.contains("light = 8.5"))
	assert_true(slot_mat.shader.code.contains("fog_disabled"))
	assert_true(slot_mat.shader.code.contains("unshaded"))


func test_billboards_scale_with_the_render_scale_because_they_use_world_units() -> void:
	var v := _view()
	var w := World.new(1, ["dog", "Rex"])
	w.monsters.clear()
	v.start(w)
	w.update_fov()
	v.refresh(0.0)
	var before: Array = []
	for s in _shown(v.billboards):
		before.append([s.position, s.pixel_size])
	for choice in ["sharp", "full", "retro"]:
		v.set_render_scale(choice)
		v.refresh(0.0)
		var after: Array = []
		for s in _shown(v.billboards):
			after.append([s.position, s.pixel_size])
		assert_eq(after, before, choice)


# --- The health bar's wall test (Python: the ray through the sprite's centre column) ------------

func _cam_at(x: int, y: int, angle_deg: float) -> Array:
	return [x + 0.5, y + 0.5, deg_to_rad(angle_deg) - PI / 2]


func test_a_bar_is_hidden_when_a_wall_covers_the_sprite_centre_column() -> void:
	# Seed 1, player (21, 5) looking 135 degrees, a damaged goblin at (23, 7): in tile FOV, but the
	# ray to its centre hits a nearer wall, so Python draws no bar (found by the verifier).
	var w := World.new(1)
	var cam := _cam_at(21, 5, 135.0)
	var scale_v := 0.62 + 0.03 * 9 / 4.0
	assert_false(FpLogic.sprite_column_clear(w.floor, cam, Vector2i(23, 7), scale_v))


func test_a_bar_shows_down_a_clear_line_and_not_behind_you_or_a_wall() -> void:
	var w := World.new(1)
	var f := w.floor
	var found := false
	for y in f.height:
		for x in f.width:
			if found or not f.walkable(x, y) or f.is_safe(x, y):
				continue
			for d in 4:
				var s: Vector2i = FpLogic.DIRS[d]
				var run := 0
				while f.walkable(x + s.x * (run + 1), y + s.y * (run + 1)):
					run += 1
				if run >= 3 and not found:
					found = true
					var cam := _cam_at(x, y, d * 90.0)
					assert_true(FpLogic.sprite_column_clear(f, cam, Vector2i(x + 2 * s.x, y + 2 * s.y), 0.6875))
					assert_false(FpLogic.sprite_column_clear(f, cam, Vector2i(x - s.x, y - s.y), 0.6875), "behind")
					var beyond := Vector2i(x + s.x * (run + 1), y + s.y * (run + 1))   # inside the wall
					assert_false(FpLogic.sprite_column_clear(f, cam, beyond, 0.6875), "past the wall")
	assert_true(found)


func test_the_billboard_bar_follows_that_rule() -> void:
	var v := _view()
	var w := World.new(1)
	w.monsters.clear()
	v.start(w)
	var g := Entities.spawn_monster("goblin", 23, 7)
	g.hp = 3
	w.monsters.append(g)
	w.player.x = 21
	w.player.y = 5
	w.update_fov()
	v.logic.angle = 135.0
	v.logic.cam = []
	v.refresh(0.0)
	var bars := 0
	for child in v.billboards.get_children():
		var s := child as Sprite3D
		if s != null and s.visible and s.texture != null and s.texture.get_width() == 64:
			bars += 1
	assert_eq(bars, 0)

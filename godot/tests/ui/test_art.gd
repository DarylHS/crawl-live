extends TestCase
## The P9 art set (docs/art-bible.md section 6): every key the game can ask for has a picture in the
## manifest (or is on the explicit fallback list), every PNG obeys the sprite rules (size, binary alpha,
## a one pixel border, feet on the bottom row, the shared palette), the art sets switch without touching code,
## the Act overlays sit on the base body, and the menu pictures only appear when asked for. The same checks
## that used to run against the placeholders now run against the real art; the placeholders are still tested
## (test_sprites.gd runs both).

const PALETTE_SIZE := 56         ## scripts/art_pipeline.py PALETTE: every sprite's colours come from these
const FALLBACK_ALLOWED: Array[String] = []   ## keys allowed to have no picture (none: wpn: and fx:torch are not in all_keys)


func after_each() -> void:
	SpriteArt.sets_dir = SpriteArt.SETS_DIR
	SpriteArt.use_set(SpriteArt.DEFAULT_SET)
	SpriteArt.reset()


func _alpha_is_binary(img: Image) -> bool:
	for y in img.get_height():
		for x in img.get_width():
			var a := img.get_pixel(x, y).a
			if a != 0.0 and a != 1.0:
				return false
	return true


func _manifest() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(SpriteArt.MANIFEST))


## The keys the manifest must hold: everything SpriteArt.all_keys() lists, the Act overlays, the torch frames,
## loot boxes, and the terrain textures and tiles of every floor.
func _required_keys() -> Array[String]:
	var keys: Array[String] = []
	for k in SpriteArt.all_keys():
		if not (k.begins_with("mon:opening_") or k.begins_with("mon:featured_")):     # Acts are the base body plus an overlay
			keys.append(k)
	keys.append_array(["fx:badge_opening", "fx:sash_featured", "fx:torch_0", "fx:torch_1"])
	for tier: String in Content.table("loot_boxes"):
		keys.append("box:" + tier)
		keys.append("box_big:" + tier)
	for depth in range(1, 7):
		for slot in ["wall_0", "wall_1", "floor", "ceiling"]:
			keys.append("tex:%d:%s" % [depth, slot])
		for slot in ["wall_0", "wall_1", "floor"]:
			keys.append("tile:%d:%s" % [depth, slot])
	for slot in ["safe_wall", "safe_floor", "stairs_open", "stairs_locked"]:
		keys.append("tex:" + slot)
		keys.append("tile:" + slot)
	return keys


func test_every_key_has_a_picture_or_is_on_the_fallback_list() -> void:
	var manifest := _manifest()
	var keys := _required_keys()
	assert_gt(keys.size(), 110)
	for k in keys:
		if FALLBACK_ALLOWED.has(k):
			continue
		assert_true(manifest.has(k), "manifest has " + k)
		assert_true(SpriteArt.has_art(k), "art for " + k)
	# the manifest records where every picture came from
	for k: String in manifest:
		var e: Variant = manifest[k]
		if e is Dictionary:
			assert_true((e as Dictionary).has("origin") and (e as Dictionary).has("licence"), k)
			assert_true(["dcss", "dcss+fill-in", "fill-in"].has((e as Dictionary)["origin"]), k)


func test_sprites_obey_the_art_bible_rules() -> void:
	var colours := {}
	for k in _required_keys():
		var kind := k.get_slice(":", 0)
		if not (kind in ["mon", "boss", "pet", "player", "item", "furn", "fx", "box"]):
			continue
		var img := SpriteArt.supplied(k)
		assert_not_null(img, k)
		if img == null:
			continue
		assert_true(_alpha_is_binary(img), k + " binary alpha")
		if k.begins_with("fx:badge") or k.begins_with("fx:sash"):
			continue                                                 # overlays are smaller pictures, checked in the Act test
		var want := Vector2i(64, 64) if kind == "box_big" else Vector2i(32, 32)
		assert_eq(img.get_size(), want, k)
		var used := img.get_used_rect()
		# a one pixel transparent border on every side (the code draws the outline there)
		assert_true(used.position.x >= 1 and used.position.y >= 1 and used.end.x <= 31 and used.end.y <= 31, "%s border %s" % [k, used])
		# feet on the floor: everything but the floating stairwell arrow and the torch flame stands on the bottom rows
		if not k.begins_with("fx:"):
			assert_eq(used.end.y, 31, k + " stands on the bottom row")
		for y in 32:
			for x in 32:
				var p := img.get_pixel(x, y)
				if p.a > 0.0:
					colours[p.to_html(false)] = true
	assert_lte(colours.size(), PALETTE_SIZE, "sprites use the shared palette only")
	assert_gt(colours.size(), 20)


func test_terrain_textures_tiles_and_boxes_have_their_sizes() -> void:
	for depth in range(1, 7):
		for slot in ["wall_0", "wall_1", "floor", "ceiling"]:
			var img := SpriteArt.supplied("tex:%d:%s" % [depth, slot])
			assert_eq(img.get_size(), Vector2i(64, 64), "tex %d %s" % [depth, slot])
			assert_false(_has_alpha(img), "opaque")
		for slot in ["wall_0", "wall_1", "floor"]:
			var t := SpriteArt.supplied("tile:%d:%s" % [depth, slot])
			assert_eq(t.get_size(), Vector2i(32, 32), "tile %d %s" % [depth, slot])
			assert_false(_has_alpha(t), "opaque")
		# the top-down tile is the first-person texture reduced: every second pixel (art bible section 2)
		var big := SpriteArt.supplied("tex:%d:floor" % depth)
		var small := SpriteArt.supplied("tile:%d:floor" % depth)
		for y in 32:
			for x in 32:
				if big.get_pixel(x * 2, y * 2) != small.get_pixel(x, y):
					fail_test("tile %d floor is not the reduced texture at %d,%d" % [depth, x, y])
					return
	for slot in ["safe_wall", "safe_floor", "stairs_open", "stairs_locked"]:
		assert_eq(SpriteArt.supplied("tex:" + slot).get_size(), Vector2i(64, 64), slot)
		assert_eq(SpriteArt.supplied("tile:" + slot).get_size(), Vector2i(32, 32), slot)
	assert_eq(SpriteArt.supplied("box_big:gold").get_size(), Vector2i(64, 64))


func _has_alpha(img: Image) -> bool:
	for y in img.get_height():
		for x in img.get_width():
			if img.get_pixel(x, y).a < 1.0:
				return true
	return false


func test_every_floor_has_its_own_set_dressing_and_safe_rooms_are_pale() -> void:
	# six themes: the walls of two floors never match, and the safe room is lighter than any stone floor
	var seen := {}
	for depth in range(1, 7):
		var key := SpriteArt.supplied("tex:%d:wall_0" % depth).get_data().hex_encode()
		assert_false(seen.has(key), "floor %d wall differs from the others" % depth)
		seen[key] = true
	var safe := SpriteArt.supplied("tex:safe_floor")
	var lum := 0.0
	for y in 64:
		for x in 64:
			lum += safe.get_pixel(x, y).get_luminance()
	assert_gt(lum / 4096.0, 0.45)
	for depth in range(1, 7):
		var stone := SpriteArt.supplied("tex:%d:floor" % depth)
		var l2 := 0.0
		for y in 64:
			for x in 64:
				l2 += stone.get_pixel(x, y).get_luminance()
		assert_lt(l2 / 4096.0, lum / 4096.0)


func test_acts_wear_a_badge_or_a_sash_over_the_base_body_only() -> void:
	for base in ["goblin", "brute", "skeleton"]:
		var plain := SpriteArt.creature("mon:" + base, [200, 100, 50])
		for tier in ["opening", "featured"]:
			var act := SpriteArt.creature("mon:%s_%s" % [tier, base], [200, 100, 50], tier)
			assert_eq(act.get_used_rect(), plain.get_used_rect(), "%s %s keeps the silhouette" % [tier, base])
			var differs := 0
			for y in 32:
				for x in 32:
					if act.get_pixel(x, y) != plain.get_pixel(x, y):
						differs += 1
			assert_gt(differs, 20, "%s %s has its overlay" % [tier, base])
			# the overlay is clipped to the body: no pixel outside the base's body plus the tier outline
			assert_true(_alpha_is_binary(act))
	# Acts get no sprite of their own (art bible 7.8): the base's picture is what they use
	assert_false(SpriteArt.has_art("mon:opening_goblin"))
	# the overlay pictures are swappable like everything else
	var blank := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	SpriteArt.register("fx:badge_opening", blank)
	var no_badge := SpriteArt.creature("mon:opening_goblin", [120, 190, 80], "opening")
	var base_only := SpriteArt.creature("mon:goblin", [120, 190, 80], "opening")
	assert_eq(no_badge.get_data(), base_only.get_data())


func test_there_is_one_player_picture_per_race() -> void:
	var races: Array = Content.table("races").keys()
	assert_eq(races.size(), 6)
	var datas := {}
	for r: String in races:
		var img := SpriteArt.player(r)
		assert_eq(img.get_size(), Vector2i(32, 32), r)
		assert_true(img.get_used_rect().size.y > 14, r)
		datas[img.get_data().hex_encode()] = true
	assert_eq(datas.size(), 6, "six different pictures")
	assert_ne(SpriteArt.player("").get_data(), SpriteArt.player("human").get_data())    # before a race is chosen
	var white := SpriteArt.player("elf")                                                  # you wear a white outline
	var used := white.get_used_rect()
	assert_true(white.get_pixel(used.position.x + used.size.x / 2, used.position.y).is_equal_approx(Color.WHITE)
			or white.get_pixel(used.position.x + used.size.x / 2, used.position.y + 1).is_equal_approx(Color.WHITE)
			or white.get_pixel(used.position.x + used.size.x / 2, used.position.y - 1).is_equal_approx(Color.WHITE))


func test_art_sets_switch_and_fall_back_to_the_default_then_the_placeholders() -> void:
	assert_eq(SpriteArt.available_sets()[0], "default")
	assert_eq(SpriteArt.available_sets()[-1], "placeholder")
	# a set under a temporary folder with one picture: it answers that key, the default answers the rest
	var dir := TestHelpers.tmp_dir("art_sets")
	var set_dir := dir + "mine/"
	DirAccess.make_dir_recursive_absolute(set_dir)
	var red := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	red.fill_rect(Rect2i(8, 8, 16, 22), Color8(255, 0, 0))
	red.save_png(set_dir + "tonic.png")
	var f := FileAccess.open(set_dir + "manifest.json", FileAccess.WRITE)
	f.store_string(JSON.stringify({"item:tonic": {"file": "tonic.png"}}))
	f.close()
	SpriteArt.sets_dir = dir
	assert_true(SpriteArt.available_sets().has("mine"))
	assert_eq(SpriteArt.use_set("mine"), "mine")
	assert_eq(SpriteArt.item("tonic").get_pixel(16, 16), Color8(255, 0, 0))               # the set's own picture
	assert_true(SpriteArt.has_art("item:brew"))                                            # the default fills the gaps
	assert_ne(SpriteArt.item("brew").get_pixel(16, 16), Color8(255, 0, 0))
	var gen := SpriteArt.generation
	assert_eq(SpriteArt.use_set("placeholder"), "placeholder")
	assert_gt(SpriteArt.generation, gen)                                                  # views notice and rebuild
	assert_false(SpriteArt.has_art("item:tonic"))
	assert_eq(SpriteArt.item_scale("tonic"), 0.32)
	assert_eq(SpriteArt.item("tonic").get_size(), Vector2i(32, 32))                       # the code-drawn shape
	assert_eq(SpriteArt.use_set("no_such_set"), "default")                                # unknown names fall back
	assert_true(SpriteArt.has_art("item:tonic"))
	var names: Array[String] = []
	for _i in SpriteArt.available_sets().size():
		names.append(SpriteArt.cycle_set())
	assert_eq(names[-1], "default")                                                       # a full lap returns to the start


func test_registered_images_beat_every_set() -> void:
	var blue := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
	blue.fill_rect(Rect2i(8, 8, 16, 22), Color8(0, 0, 255))
	SpriteArt.register("item:tonic", blue)
	assert_eq(SpriteArt.item("tonic").get_pixel(16, 16), Color8(0, 0, 255))
	SpriteArt.use_set("placeholder")
	assert_eq(SpriteArt.item("tonic").get_pixel(16, 16), Color8(0, 0, 255))


func test_first_person_materials_follow_the_art_set() -> void:
	var mats := FpMaterials.new()
	var a := mats.for_depth(2)
	assert_true(mats.for_depth(2) == a)                                                   # cached
	var real: Image = (a["wall_a"] as StandardMaterial3D).albedo_texture.get_image()
	SpriteArt.use_set("placeholder")
	var b := mats.for_depth(2)
	assert_false(b == a)                                                                  # rebuilt for the new set
	var plain: Image = (b["wall_a"] as StandardMaterial3D).albedo_texture.get_image()
	assert_ne(real.get_data(), plain.get_data())


func test_menu_pictures_are_off_unless_asked_for() -> void:
	var w := World.new(3)
	w.inventory = ["tonic", "sock"]
	var st := HudStyle.new()
	var plain := MenuModels.build_inventory(st, w, 0)
	for it: Dictionary in plain.items:
		assert_ne(it["k"], "i")                                                           # pygame's glyph layout
	assert_true(plain.strings().has("!"))
	st.icons = true
	var art := MenuModels.build_inventory(st, w, 0)
	var icons := 0
	for it: Dictionary in art.items:
		if it["k"] == "i":
			icons += 1
	assert_eq(icons, w.inventory.size() + _equipped(w))
	assert_false(art.strings().has("!"))                                                  # the glyph is replaced
	var title := ScreenModels.build_title(st, false)
	assert_true(" ".join(title.strings()).contains("Dungeon Crawl Stone Soup"))           # the art credit shows with art on
	st.icons = false
	assert_false(" ".join(ScreenModels.build_title(st, false).strings()).contains("Stone Soup"))


func _equipped(w: World) -> int:
	var n := 0
	for slot: String in w.equipment:
		if PyMath.truthy(w.equipment[slot]):
			n += 1
	return n


func test_credits_name_every_source_tile_and_the_licence() -> void:
	var text := FileAccess.get_file_as_string("res://assets/CREDITS.md")
	assert_true(text.contains("Dungeon Crawl Stone Soup") and text.contains("CC0 1.0") and text.contains("crawl/tiles"))
	for k: String in _manifest():
		var e: Variant = _manifest()[k]
		if e is Dictionary:
			assert_true(text.contains("`%s`" % k), "CREDITS lists " + k)
			for src: String in (e as Dictionary).get("source", []):
				assert_true(text.contains(src.get_file()), "CREDITS names " + src)

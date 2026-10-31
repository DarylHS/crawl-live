extends TestCase
## P9 verifier fixes: map tiles are the original 32 px pictures, loot box tiers differ, the credits screen and its
## key, menus with pictures stay inside their frame whatever the length, and an art switch redraws the weapon.

const K := preload("res://tools/key_events.gd")


func after_each() -> void:
	SpriteArt.use_set(SpriteArt.DEFAULT_SET)
	SpriteArt.reset()


func test_map_tiles_are_the_original_32_px_pictures_not_a_reduction() -> void:
	for depth in range(1, 7):
		for slot in ["wall_0", "wall_1", "floor"]:
			var big := SpriteArt.supplied("tex:%d:%s" % [depth, slot])
			var small := SpriteArt.supplied("tile:%d:%s" % [depth, slot])
			var hazard: bool = depth == 3 and slot == "wall_1"            # floor 3's second wall: the half with the tape
			var from := Vector2i(0, 32) if hazard else Vector2i.ZERO
			assert_true(big.get_region(Rect2i(from, Vector2i(32, 32))).get_data() == small.get_data(), "tile %d %s" % [depth, slot])
			if not hazard:
				assert_true(big.get_region(Rect2i(32, 32, 32, 32)).get_data() == small.get_data(), "texture repeats tile %d %s" % [depth, slot])
	# a brick tile keeps its mortar lines: neighbouring pixels agree far more often than the old every-second-pixel static
	var tile := SpriteArt.supplied("tile:1:wall_0")
	var same := 0
	for y in 32:
		for x in 31:
			if tile.get_pixel(x, y).is_equal_approx(tile.get_pixel(x + 1, y)):
				same += 1
	assert_gt(same, 32 * 31 / 4)


func test_loot_box_tiers_look_different() -> void:
	var seen := {}
	for tier: String in Content.table("loot_boxes"):
		var img := SpriteArt.supplied("box:" + tier)
		var body := img.get_pixel(9, 22).to_html(false)
		assert_false(seen.has(body), "%s box has its own colour" % tier)
		seen[body] = true


func test_credits_screen_lists_the_source_and_the_artists() -> void:
	var data := ScreenModels.credits_data()
	assert_gt((data["artists"] as Array).size(), 40)
	for n: String in data["artists"]:
		assert_false(n.contains("@") or n.ends_with("-") or n.begins_with("-") or n.contains("()"), "clean name: " + n)
	var st := HudStyle.new()
	var text := " ".join(ScreenModels.build_credits(st).strings())
	assert_true(text.contains("Dungeon Crawl Stone Soup") and text.contains("crawl/tiles") and text.contains("CC0"))
	assert_true(text.contains("Eino Keskitalo") and text.contains("Esc to close"))
	st.icons = true
	assert_true(" ".join(ScreenModels.build_title(st, false).strings()).contains("github.com/crawl/tiles"))
	var app := AppState.new({"settings_path": "", "runs_dir": ""})
	app.handle_key(K.letter("c"))                                    # C on the title opens it, Enter or Esc closes it
	assert_true(app.show_credits)
	app.handle_key(K.key(KEY_ENTER))
	assert_false(app.show_credits)
	assert_eq(app.scene, AppState.TITLE)
	assert_true(InputMap.has_action(&"credits"))


func _check_frame(list: HudList, label: String, limit: int) -> void:
	for it: Dictionary in list.items:
		if it["k"] == "i":
			assert_lte((it["r"] as Rect2i).end.y, limit, label + ": picture inside the frame")
		elif it["k"] == "t" and (it["f"] == "font") and (it["y"] as int) > 100 and (it["y"] as int) < limit:
			assert_lte((it["y"] as int) + 18, limit, label + ": text inside the frame")


func test_a_full_pack_and_the_box_list_stay_inside_their_frames() -> void:
	var st := HudStyle.new()
	st.icons = true
	var w := World.new(3)
	var keys: Array = Items.items().keys()
	for n in [0, 1, 6, 12, 14, 16]:
		w.inventory.clear()
		for i in n:
			w.inventory.append(keys[i % keys.size()])
		w.equipment["weapon"] = "katana"
		w.equipment["armour"] = "jersey"
		var rows := MenuModels.inventory_rows(w).size()
		var list := MenuModels.build_inventory(st, w, rows - 1)
		var icons := 0
		var last := 0
		for it: Dictionary in list.items:
			if it["k"] == "i":
				icons += 1
				last = maxi(last, (it["r"] as Rect2i).end.y)
		assert_eq(icons, rows)
		assert_lte(last, 556, "pack of %d (%d rows): the last picture ends above the footer" % [n, rows])
		_check_frame(list, "pack of %d" % n, 560)
	assert_eq(MenuModels.inventory_step(18), 23)
	assert_eq(MenuModels.inventory_step(3), 34)
	w.boxes = ["bronze", "silver", "gold", "platinum", "legendary"]
	_check_frame(MenuModels.build_safe_menu(st, w, 0), "safe menu", 505)


func test_the_weapon_redraws_after_an_art_switch() -> void:
	var vm := ViewModel.new()
	add_child_autofree(vm)
	vm.size = Vector2(1024, 640)
	vm.set_weapon("katana", "blade")
	await get_tree().process_frame
	var first := vm._texture()
	SpriteArt.use_set(SpriteArt.PLACEHOLDER_SET)
	var redraws := [0]
	vm.draw.connect(func() -> void: redraws[0] += 1)
	vm.forget_textures()
	await get_tree().process_frame
	assert_gt(redraws[0], 0, "forget_textures asks for a redraw")
	assert_false(vm._texture() == first)

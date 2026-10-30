extends TestCase
## The menu and screen models (P7): the fit and wording tests of tests/test_render.py
## (`test_attributes_and_shop_text_fit_their_panel`, `test_help_lists_the_controls_for_the_view`,
## `test_contract_text_fits_its_panel`, `test_help_fits_the_map_area`,
## `test_inventory_names_clear_the_stats_column`, the `_fit` half of `test_skills_screen_draws`,
## `test_report_is_opaque_and_its_caption_sits_inside`, the inventory over the tracker of
## `test_combat_tracker_and_screens_in_both_views`) and `test_screenshot_sweep_of_every_screen_in_both_views`
## through tools/menu_sweep.gd, plus what each screen says (odds, prices, forecasts, report charts).

const GAME := preload("res://scenes/game_view.tscn")
const HUD := preload("res://scenes/hud.tscn")
const K := preload("res://tools/key_events.gd")

var style := HudStyle.new()


func _world(seed_value: int = 1) -> World:
	var hero := {"name": "Crawler", "gender": Content.table("genders").keys()[0],
			"backstory": Content.table("backstories").keys()[0]}
	return World.new(seed_value, [Content.table("pets").keys()[0], ""], hero)


func _strings(list: HudList) -> String:
	return "\n".join(list.strings())


func _texts_of(list: HudList) -> Array:
	var out: Array = []
	for it: Dictionary in list.items:
		if it["k"] == "t":
			out.append(it)
	return out


# --- The sweep ---------------------------------------------------------------------------------------

func test_screenshot_sweep_of_every_screen_in_both_views() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(holder)
	var seen: Array = []
	var shot := func(shot_name: String, app: AppState, hud: Hud, g: GameView) -> void:
		for v in ["top", "fp"]:
			if app.scene == AppState.GAME:
				g.set_view(v)
			hud.sync()
			assert_true(hud.menu.list != null or app.scene == AppState.GAME, shot_name)
		seen.append(shot_name)
	var sweep := MenuSweep.new(holder, shot)
	sweep.tmp_dir = TestHelpers.tmp_dir("sweep")
	await sweep.sweep()
	var want: Array = []
	for n in MenuSweep.SWEEP:
		want.append("sweep_" + n)
	assert_eq(seen, want)
	sweep._release()


func test_every_other_screen_of_the_pygame_run_draws_too() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(holder)
	var seen: Array = []
	var shot := func(shot_name: String, app: AppState, hud: Hud, g: GameView) -> void:
		for v in ["top", "fp"]:
			if app.scene == AppState.GAME:
				g.set_view(v)
			hud.sync()
		seen.append(shot_name)
	var sweep := MenuSweep.new(holder, shot)
	sweep.tmp_dir = TestHelpers.tmp_dir("sweep_rest")
	await sweep.scenes()
	await sweep.items()
	await sweep.phase3()
	await sweep.phase4()
	await sweep.attributes()
	await sweep.tab_and_help()
	await sweep.monsters()
	await sweep.skills()
	await sweep.combat()
	await sweep.walking_and_looking()
	await sweep.corner_and_provoke()
	sweep._release()
	assert_true(seen.size() >= 40, "shots: %d" % seen.size())
	for n in ["title", "identity", "backstory", "pet_select", "game", "game_revealed", "help", "death",
			"victory", "game_items", "inventory", "safe_menu", "box_odds", "box_reveal", "death_viewers",
			"class_race", "class_class", "scout_report", "safe_menu_p3", "craft", "title_with_save", "contract",
			"shop_buy", "shop_sell", "box_odds_silver", "reveal_reroll", "report", "attributes",
			"game_attributes_panel", "game_tab", "game_monster", "game_monster_adjacent", "help_game", "skills",
			"shop_remote", "combat_start", "combat_mid", "combat_attacked", "inventory_combat", "help_combat",
			"combat_end", "combat_boss", "game_after_walking", "game_diagonal", "combat_corner", "aoo_warning", "aoo_log"]:
		assert_true(seen.has(n), n)


# --- Fit tests -----------------------------------------------------------------------------------------

func test_attributes_and_shop_text_fit_their_panel() -> void:
	var small := func(s: String) -> int: return style.width("small", s)
	assert_true(MenuModels.ATTR_SOURCE_X + small.call(MenuModels.attr_source(10, 20)) <= MenuModels.WIDTH - 20)
	assert_true(MenuModels.ATTR_SOURCE_X + small.call(MenuModels.attr_source(10, 4)) <= MenuModels.WIDTH - 20)
	var last: Array = MenuModels.SHOP_COLS[-1]
	assert_true(int(last[1]) + small.call(last[0]) <= MenuModels.WIDTH - 30)


func test_help_lists_the_controls_for_the_view() -> void:
	var fp := ScreenModels.help_text("fp")
	var top := ScreenModels.help_text("top")
	assert_true("Q / E" in fp and "strafe" in fp and "hold" in fp and not "Q / E" in top)
	assert_true("numpad" in top and not "Arrows / WASD" in fp)
	assert_true("Tab switch view" in fp and "Tab switch view" in top)


func test_help_has_a_combat_section_in_both_views() -> void:
	for v in ["fp", "top"]:
		var text := ScreenModels.help_text(v)
		assert_true("Combat turn" in text and "Leaving reach" in text, v)
	var list := ScreenModels.build_help(style, "fp")
	assert_eq(list.find_text("Combat turn")["c"], style.colour("DANGER"))     # combat rows in the warning colour
	assert_eq(list.find_text("W / Up")["c"], style.colour("ACCENT"))


func test_contract_text_fits_its_panel() -> void:
	var w := _world()
	for key: String in Contracts.contracts():
		w.pending_offer = key
		var rects: Array = []
		MenuModels.build_contract(style, w, rects)
		var footer: Rect2i = rects[-1]
		for r: Rect2i in rects:
			assert_true(MenuModels.X0 + 10 <= r.position.x and r.end.x <= MenuModels.X0 + MenuModels.WIDTH - 10, key)
		var body_bottom: int = rects[-2].end.y
		assert_true(body_bottom < footer.position.y, key)


func test_help_fits_the_map_area() -> void:
	var right := HudPlace.MAP_W - 10
	for view in ["fp", "top"]:
		var rows := ScreenModels.controls(view)
		for r: Array in rows:
			assert_true(ScreenModels.help_cx() - 20 - style.width("font", r[0]) >= 10, r[0])
			assert_true(ScreenModels.help_cx() + 20 + style.width("font", r[1]) <= right, r[1])
		var y0 := ScreenModels.help_top(rows)
		assert_true(y0 - 70 - style.line_height("big") / 2 >= 0)                           # the title
		var close_bottom := y0 + rows.size() * ScreenModels.HELP_STEP + 14 + style.line_height("font") / 2
		assert_true(close_bottom <= HudPlace.MAP_H - 4, view)                              # above the log


func test_inventory_names_clear_the_stats_column() -> void:
	for it: Dictionary in Items.items().values():
		assert_true(46 + style.width("font", "%s [weapon]" % it["name"]) + 10 <= MenuModels.INV_STATS_X, it["name"])
	assert_eq(MenuKit.fit(style, "a long line of text", 1), "...")                       # never loops for ever


func test_every_practice_effect_line_fits_the_panel() -> void:
	var room := MenuModels.WIDTH - MenuModels.PRACTICE_TEXT_X - 14
	for sk: Dictionary in Practice.skills().values():
		for text: String in [sk["effect"], sk["trains"]]:
			var fitted := MenuKit.fit(style, text, room)
			assert_true(style.width("small", fitted) <= room)
			assert_eq(fitted.left(12), text.left(12))


func test_skills_screen_shows_discovered_skills_and_question_marks() -> void:
	var w := _world()
	var keys := Practice.skills().keys()
	for i in range(0, keys.size(), 2):
		w.training.gain(keys[i], 3 * (i / 2) + 1)
	var list := MenuModels.build_practice(style, w)
	var text := _strings(list)
	assert_true("???" in text and "Not discovered yet" in text and "PRACTICE SKILLS" in text)
	assert_true(Practice.skills()[keys[0]]["name"] in text)
	assert_false(Practice.skills()[keys[1]]["name"] in text)                          # hidden until first used


# --- The report ----------------------------------------------------------------------------------------

func test_report_is_opaque_and_its_caption_sits_inside() -> void:
	var w := _world()
	w.gold = 500
	w.add_box("bronze", "test")
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	w.update_fov()
	assert_true(w.open_box("bronze"))
	assert_false(w.box_log.is_empty())
	w.state = "dead"
	w.death_cause = "Killed by a unit test"
	var rects := {}
	var list := ReportModel.build(style, w, rects)
	var shade: Dictionary = list.items[0]
	assert_true(shade["k"] == "r" and shade["r"] == Rect2i(0, 0, 1280, 768) and shade["c"].a == 1.0)
	assert_eq(shade["c"].r, style.colour("BG").r)
	for p in [Vector2i(435, 200), Vector2i(845, 300), Vector2i(600, 400), Vector2i(20, 200)]:
		for it: Dictionary in list.items.slice(1):                                    # between and under the panels
			if it["k"] == "r" or it["k"] == "f":
				assert_false((it["r"] as Rect2i).has_point(p), "%s %s" % [p, it["r"]])
	var caption: Rect2i = rects["caption"]
	assert_true(caption.end.y < 90 + 300 - 2 and caption.position.y > 90)
	assert_true(_strings(list).contains("than average."))


func test_report_with_no_boxes_and_no_deals_says_so() -> void:
	var w := _world()
	w.state = "dead"
	w.death_cause = "Killed by a unit test"
	var text := _strings(ReportModel.build(style, w))
	assert_true("No boxes opened this run." in text and "None signed." in text and "Damage taken by floor" in text)
	assert_true("Viewers over time" in text and "Enter or Esc: back" in text)
	assert_true("Boxes opened: 0   Rerolls: 0" in text)


func test_report_charts_have_lines_and_floor_markers() -> void:
	var w := _world(4)
	for _i in 30:
		w.wait()
	w.add_box("bronze", "a")
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	w.update_fov()
	w.open_box("bronze")
	w.new_floor(2)
	for _i in 10:
		w.wait()
	w.state = "dead"
	w.death_cause = "x"
	var list := ReportModel.build(style, w)
	var lines := 0
	for it: Dictionary in list.items:
		if it["k"] == "pl":
			lines += 1
	assert_true(lines >= 2, "the viewer curve and the box lines")


# --- What the menus say --------------------------------------------------------------------------------

func test_box_odds_list_the_real_table_and_the_expected_value() -> void:
	var w := _world()
	w.boxes = ["silver", "silver", "silver"]
	var text := _strings(MenuModels.build_box_info(style, w, "silver"))
	var ev: float = Loot.box_stats("silver")[0]
	assert_true("SILVER BOX" in text)
	assert_true("Expected value %s gold" % PyFmt.fixed(ev, 1) in text)
	assert_true("T: trade 3 for one Gold box (you have 3)." in text)
	assert_true("Rerolling a Silver box after opening costs %d gold." % w.reroll_fee("silver") in text)
	for row: Array in Loot.odds("silver"):
		assert_true(Items.items()[row[0]]["name"] in text)
		assert_true("%s%%" % PyFmt.fixed(row[1] * 100.0, 0) in text)
	var legend := _strings(MenuModels.build_box_info(style, w, "legendary"))
	assert_false("T: trade" in legend)                                                 # nothing above legendary


func test_the_reveal_compares_with_the_average_and_offers_the_reroll() -> void:
	var w := _world()
	w.gold = 300
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	w.update_fov()
	w.add_box("bronze", "Beat the Goblin.")
	assert_true(w.open_box("bronze"))
	var text := _strings(MenuModels.build_reveal(style, w))
	assert_true("BRONZE BOX" in text and "Earned for: Beat the Goblin." in text)
	assert_true("R: hand it back and reroll for %d gold (you have 300)." % w.reroll_fee("bronze") in text)
	assert_true("Enter: keep it" in text)
	var key: String = w.last_reveal[1]
	var ev: float = Loot.box_stats("bronze")[0]
	var v: int = Items.value(key)
	assert_true(("Worth %d gold: %s" % [v, "above" if v > ev else ("below" if v < ev else "exactly")]) in text)
	w.inventory.erase(key)                                                              # no item, no reroll offer
	assert_false("R: hand it back" in _strings(MenuModels.build_reveal(style, w)))


func test_the_shop_shows_prices_stock_and_notes() -> void:
	var w := _world()
	w.gold = 90
	var buy := _strings(MenuModels.build_shop(style, w, 0, "buy"))
	assert_true("SAFE ROOM SHOP" in buy and "BUY   sell" in buy and "Your gold: 90" in buy)
	for h: Array in MenuModels.SHOP_COLS:
		assert_true(h[0] in buy)
	assert_true("Stock arrives one floor after it's ordered." in buy)
	assert_true("/floor" in buy)
	w.inventory = ["sock", "pan"]
	var sell := _strings(MenuModels.build_shop(style, w, 0, "sell"))
	assert_true("buy   SELL" in sell and "They pay" in sell and "The shop pays 40% of an item's value. Junk sells too." in sell)
	w.inventory = []
	assert_true("Nothing to sell." in _strings(MenuModels.build_shop(style, w, 0, "sell")))
	w.remote_shop = true
	assert_true("SUPPLY DROP" in _strings(MenuModels.build_shop(style, w, 0, "buy")))


func test_the_safe_menu_lists_rest_revive_boxes_shop_craft_and_save() -> void:
	var w := _world()
	assert_eq(MenuModels.menu_actions(w), ["rest", "shop", "craft", "save"])
	w.pet.downed = true
	w.boxes = ["gold", "bronze", "bronze"]
	var opts := MenuModels.menu_options(w)
	assert_eq(MenuModels.menu_actions(w), ["rest", "revive", "box", "box", "shop", "craft", "save"])
	assert_eq(opts[2][2], "Bronze boxes (x2): odds, open, trade")                        # tier order, not pickup order
	assert_eq(opts[3][2], "Gold boxes (x1): odds, open, trade")
	assert_true(String(opts[1][2]).begins_with("Revive "))


func test_the_chooser_wraps_long_descriptions_inside_its_panel() -> void:
	var w := _world()
	for step in ["race", "class"]:
		for i in MenuModels.class_rows(step).size():
			var list := MenuModels.build_class_select(style, w, step, "human", i)
			for it: Dictionary in _texts_of(list):
				if it["x"] >= 140 + 360:
					assert_true(it["x"] + style.width(it["f"], it["s"]) <= 140 + 1000 - 20, it["s"])


func test_attributes_screen_numbers() -> void:
	var w := _world()
	var text := _strings(MenuModels.build_attributes(style, w, 0))
	assert_true("ATTRIBUTES" in text and "Strength" in text and "Constitution" in text)
	assert_true("%d points to spend" % w.player.stat_points in text)
	assert_true("Armour Class %d" % w.player.ac in text and "Bomb save DC %d" % w.save_dc() in text)
	w.player.stat_points = 0
	assert_true("No points to spend. You get 2 more each level." in _strings(MenuModels.build_attributes(style, w, 0)))
	w.player.stat_points = 1
	assert_true("1 point to spend" in _strings(MenuModels.build_attributes(style, w, 0)))


func test_the_title_says_how_to_continue_only_with_a_save() -> void:
	assert_false("L to continue your saved run" in _strings(ScreenModels.build_title(style, false)))
	assert_true("L to continue your saved run" in _strings(ScreenModels.build_title(style, true)))
	assert_true("Loading your saved run..." in _strings(ScreenModels.build_title(style, true, true)))
	assert_false("L to continue your saved run" in _strings(ScreenModels.build_title(style, true, true)))


# --- The inventory over the tracker (test_combat_tracker_and_screens_in_both_views) ----------------------

func test_the_tracker_over_the_inventory_clears_the_menu() -> void:
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child_autofree(holder)
	var g: GameView = GAME.instantiate()
	g.settings_path = ""
	g.runs_dir = ""
	g.input_enabled = false
	holder.add_child(g)
	g.size = Vector2(1024, 640)
	var h: Hud = HUD.instantiate()
	holder.add_child(h)
	g.start(_world())
	h.bind(g)
	var w := g.world
	w.monsters.clear()
	w.pet.downed = true
	w.player.max_hp = 999
	w.player.hp = 999
	var m := Entities.spawn_monster("goblin", w.player.x + 1, w.player.y)
	m.hp = 999
	m.max_hp = 999
	m.stunned = 99
	w.monsters.append(m)
	w.update_fov()
	assert_true(w.join_combat(m))
	w.combat.round = 1
	w.inventory.append("tonic")
	g.app.open_overlay("inventory")
	for v in ["top", "fp"]:
		g.set_view(v)
		h.sync()
		var box := h.last_tracker
		assert_true(box.size.x > 0, v)                                                   # the pips show over the inventory
		assert_true(box.end.x < MenuModels.X0 and w.combat.has("bonus"), v)
		assert_true(tracker_shows(h), v)
		assert_eq(h.tracker.list.items.size(), 0)                                         # not under the shade
	g.app.overlay = ""
	h.sync()
	assert_true(h.tracker_over.list.items.is_empty())


func tracker_shows(h: Hud) -> bool:
	return h.tracker_over.list != null and not h.tracker_over.list.items.is_empty()


func test_text_ending_in_an_overhanging_glyph_is_a_pixel_wider() -> void:
	assert_eq(style.width("big", "INVENTORY"), 118)               # Y overhangs its advance
	assert_eq(style.width("big", "SAFE ROOM"), 117)
	assert_eq(style.width("font", "Q / E, Left / Right"), 19 * 9)
	assert_eq(style.width("font", "W / Up, S"), 9 * 9)
	assert_eq(style.width("font", "show"), 4 * 9 + 1)             # w
	assert_eq(style.width("small", "RW"), 2 * 8)                  # the small face has none

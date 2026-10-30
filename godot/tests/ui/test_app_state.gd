extends TestCase
## AppState (P7): the menu and screen tests of tests/test_render.py run on the real GameView and Hud
## with the keys the pygame tests press (`test_all_scenes_draw`, `test_item_screens_draw`,
## `test_phase3_screens_draw`, `test_phase4_screens_draw`, `test_attribute_screen_spends_points`,
## `test_tab_still_cycles_gender_and_species`, `test_menus_in_first_person_leave_you_where_you_were`,
## the load part of `test_new_runs_and_floors_face_the_most_open_way`, `test_end_screens_ignore_tab`,
## the Tab part of `test_tab_toggles_and_remembers_the_view`), plus the key routing this port adds:
## text entry, R meaning rest / reroll / report, Esc, save and load with the loading state.

const GAME := preload("res://scenes/game_view.tscn")
const HUD := preload("res://scenes/hud.tscn")
const K := preload("res://tests/support/test_keys.gd")

var _n: int = 0


## A GameView with a Hud over it and its AppState, nothing written to the player's files. Returns
## [app, hud, game_view].
func _screen(seed_value: int = 1, save_path: String = "", settings_path: String = "") -> Array:
	_n += 1
	var holder := Control.new()
	holder.size = Vector2(1280, 768)
	add_child_autofree(holder)
	var g: GameView = GAME.instantiate()
	g.settings_path = settings_path
	g.runs_dir = ""
	g.input_enabled = false
	g.app.seed_value = seed_value
	g.app.save_path = save_path if save_path != "" else TestHelpers.tmp_dir("app_state_%d" % _n) + "slot.json"
	holder.add_child(g)
	g.size = Vector2(1024, 640)
	var h: Hud = HUD.instantiate()
	holder.add_child(h)
	h.bind(g)
	return [g.app, h, g]


## Python `_start`: Enter four times (title, identity, backstory, companion) and the world.
func _start(app: AppState) -> World:
	for _i in 4:
		app.handle_key(K.key(KEY_ENTER))
	return app.world


func _empty(w: World, x: int, y: int) -> bool:
	return w.floor.walkable(x, y) and w.monster_at(x, y) == null and w.pet_at(x, y) == null


func _type(app: AppState, text: String) -> void:
	for ch in text:
		app.handle_key(K.letter(ch))


## Draw both views of the current screen (the Hud lists for each), returns the menu strings of the last.
func _shot(app: AppState, h: Hud, g: GameView) -> PackedStringArray:
	var shown := g.view
	var texts := PackedStringArray()
	for v in ["top", "fp"]:
		if app.scene == AppState.GAME:
			g.set_view(v)
		h.sync()
		texts = h.menu_texts.duplicate()
		if h.help.list != null:
			texts.append_array(h.help.list.strings())
	if app.scene == AppState.GAME:
		g.set_view(shown)
	return texts


func _record(w: World, event_name: String) -> Array:
	var seen: Array = []
	w.events.subscribe(event_name, func(_n2: String, d: Dictionary) -> void: seen.append(d))
	return seen


func _joined(texts: PackedStringArray) -> String:
	return "\n".join(texts)


# --- Scenes and character creation (test_all_scenes_draw) ------------------------------------------

func test_all_scenes_draw() -> void:
	for view in ["top", "fp"]:
		var sc := _screen()
		var app: AppState = sc[0]
		var h: Hud = sc[1]
		var g: GameView = sc[2]
		g.set_view(view)
		var t := _shot(app, h, g)
		assert_true("CRAWL LIVE!" in _joined(t) and "Press Enter to start" in _joined(t))
		app.handle_key(K.key(KEY_ENTER))
		assert_eq(app.scene, "identity")
		_type(app, "Daz")
		app.handle_key(K.key(KEY_RIGHT))                         # Man
		t = _shot(app, h, g)
		assert_true("Daz_" in t)
		assert_true("The System will call you 'sir'. Cosmetic only: no stat differences." in t)
		app.handle_key(K.key(KEY_ENTER))
		assert_eq(app.scene, "backstory")
		for _i in 5:
			app.handle_key(K.key(KEY_DOWN))                       # Tradie
		t = _shot(app, h, g)
		assert_true("Tradie" in t)
		app.handle_key(K.key(KEY_ENTER))
		assert_eq(app.scene, "pet_select")
		_type(app, "Rex")
		app.handle_key(K.key(KEY_RIGHT))
		t = _shot(app, h, g)
		assert_true("Rex_" in t)
		app.handle_key(K.key(KEY_ENTER))
		assert_eq(app.scene, "game")
		var w := app.world
		assert_true(w.pet.name == "Rex" and w.pet.species == "dog")
		assert_true(w.hero_name == "Daz" and w.gender == "male" and w.backstory == "tradie")
		g.set_view("top")                                         # the walk below uses absolute arrows
		for _i in 4:
			app.handle_key(K.key(KEY_RIGHT))
		g.set_view(view)
		_shot(app, h, g)
		for row in w.floor.explored:                              # reveal the whole map
			row.fill(1)
		_shot(app, h, g)

		app.handle_key(K.question())
		assert_true(app.show_help)
		t = _shot(app, h, g)
		assert_true("CONTROLS" in t)
		app.handle_key(K.question())
		assert_false(app.show_help)

		w.state = "dead"
		w.death_cause = "Killed by a unit test on floor 1"
		h.sync()
		assert_true(h.end.list.find_text("YOU DIED").size() > 0)
		w.state = "victory"
		h.sync()
		assert_true(h.end.list.find_text("YOU SURVIVED").size() > 0)

		app.handle_key(K.key(KEY_ENTER))                          # new run from the end screen
		assert_eq(app.scene, "identity")
		for _i in 3:
			app.handle_key(K.key(KEY_ENTER))
		assert_true(app.world.state == "playing" and app.world.pet != null and app.view == view)


func test_character_creation_keys_and_text_entry() -> void:
	var app: AppState = _screen()[0]
	app.handle_key(K.key(KEY_ENTER))
	_type(app, "Mr. T3x")                                          # the full stop is not a name character
	assert_eq(app.hero_name, "Mr T3x")
	app.handle_key(K.key(KEY_BACKSPACE))
	assert_eq(app.hero_name, "Mr T3")
	app.handle_key(K.key(KEY_SPACE, " "))
	app.handle_key(K.key(KEY_APOSTROPHE, "'"))
	app.handle_key(K.key(KEY_MINUS, "-"))
	assert_eq(app.hero_name, "Mr T3 '-")
	for _i in 20:
		app.handle_key(K.letter("a"))
	assert_eq(app.hero_name.length(), 16)                          # the name stops at 16 characters
	app.handle_key(K.key(KEY_LEFT))
	assert_eq(app.gender_idx, 2)                                   # wraps round
	app.handle_key(K.key(KEY_ESCAPE))
	assert_eq(app.scene, "title")
	app.handle_key(K.key(KEY_ENTER))
	app.handle_key(K.key(KEY_ENTER))
	assert_eq(app.scene, "backstory")
	app.handle_key(K.key(KEY_UP))                                  # up from the first wraps to the last
	assert_eq(app.backstory_idx, Content.table("backstories").size() - 1)
	app.handle_key(K.key(KEY_W, "w"))
	assert_eq(app.backstory_idx, Content.table("backstories").size() - 2)
	app.handle_key(K.key(KEY_ESCAPE))
	assert_eq(app.scene, "identity")
	app.handle_key(K.key(KEY_ENTER))
	app.handle_key(K.key(KEY_ENTER))
	assert_eq(app.scene, "pet_select")
	_type(app, "Bo")
	assert_eq(app.pet_name, "Bo")
	app.handle_key(K.key(KEY_ESCAPE))
	assert_eq(app.scene, "backstory")
	app.handle_key(K.key(KEY_ENTER))
	assert_eq(app.pet_name, "")                                    # a fresh companion name each time
	app.handle_key(K.key(KEY_ENTER))
	assert_eq(app.scene, "game")
	assert_eq(app.world.hero_name, "Mr T3 '-aaaaaaaaa".left(16))
	assert_eq(app.world.pet.name, Content.table("pets")["cat"]["default_name"])


func test_the_title_keys_and_help() -> void:
	var sc := _screen()
	var app: AppState = sc[0]
	var h: Hud = sc[1]
	app.handle_key(K.letter("l"))                                  # no save: nothing happens
	assert_eq(app.scene, "title")
	app.handle_key(K.question())
	h.sync()
	assert_true(app.show_help)
	assert_true(h.help.list.find_text("CONTROLS").size() > 0)
	app.handle_key(K.key(KEY_ENTER))                               # help swallows keys
	assert_eq(app.scene, "title")
	app.handle_key(K.key(KEY_ESCAPE))
	assert_false(app.show_help)
	assert_true(app.running)
	app.handle_key(K.key(KEY_ESCAPE))
	assert_false(app.running)                                      # Esc on the title quits


# --- Items, boxes and the safe room (test_item_screens_draw) -----------------------------------------

func test_item_screens_draw() -> void:
	for view in ["top", "fp"]:
		var sc := _screen()
		var app: AppState = sc[0]
		var h: Hud = sc[1]
		var g: GameView = sc[2]
		var w := _start(app)
		g.set_view(view)
		w.inventory = ["pan", "jersey", "tonic", "popper", "sock", "elixir"]
		w.equip(0)
		w.floor_items[Vector2i(w.player.x + 1, w.player.y)] = ["brew"]
		w.add_box("bronze", "Show Stopper: The Shrink-Wrapped Colossus. Took down floor 5's Headliner, The Shrink-Wrapped Colossus.")
		w.add_box("legendary", "test")
		w.toasts.append([w.turn, "Achievement: First Blood", "silver", "Silver box. Open it in a safe room."])
		_shot(app, h, g)

		app.handle_key(K.letter("i"))
		assert_eq(app.overlay, "inventory")
		app.handle_key(K.key(KEY_DOWN))
		var t := _shot(app, h, g)
		assert_true("INVENTORY" in t)
		app.handle_key(K.letter("d"))                              # drop the selected item
		assert_eq(w.inventory.size(), 4)
		app.handle_key(K.key(KEY_ESCAPE))
		assert_true(app.overlay == "" and app.scene == "game")

		app.handle_key(K.letter("m"))                              # not in a safe room
		assert_eq(app.overlay, "")
		w.player.x = w.floor.safe_room.centre().x
		w.player.y = w.floor.safe_room.centre().y
		w.update_fov()
		app.handle_key(K.letter("m"))
		assert_eq(app.overlay, "safe")
		app.handle_key(K.key(KEY_DOWN))
		_shot(app, h, g)
		app.handle_key(K.key(KEY_ENTER))                           # bronze box odds
		assert_eq(app.overlay, "box")
		t = _shot(app, h, g)
		assert_true("BRONZE BOX" in t and "The System is legally required to show you the odds." in t)
		app.handle_key(K.key(KEY_ENTER))                           # open it
		assert_true(app.overlay == "reveal" and w.last_reveal != null)
		_shot(app, h, g)
		app.handle_key(K.key(KEY_ENTER))
		assert_eq(app.overlay, "safe")
		app.handle_key(K.key(KEY_ESCAPE))

		w.state = "dead"
		w.death_cause = "Killed by a unit test"
		_shot(app, h, g)


# --- Class picker, crafting, saving and loading (test_phase3_screens_draw) ---------------------------

func test_phase3_screens_draw() -> void:
	for view in ["top", "fp"]:
		var dir := TestHelpers.tmp_dir("phase3_" + view)
		var sc := _screen(3, dir + "slot.json")
		var app: AppState = sc[0]
		var h: Hud = sc[1]
		var g: GameView = sc[2]
		_start(app)
		g.set_view(view)
		var w := app.world
		w.new_floor(3)
		app.handle_key(K.key(KEY_PERIOD, "."))                     # any key opens the class picker
		assert_eq(app.overlay, "class")
		var t := _shot(app, h, g)
		assert_true("CHOOSE YOUR RACE" in t)
		app.handle_key(K.key(KEY_DOWN))
		app.handle_key(K.key(KEY_ENTER))                           # elf
		app.handle_key(K.key(KEY_DOWN))
		app.handle_key(K.key(KEY_DOWN))
		t = _shot(app, h, g)
		assert_true("CHOOSE YOUR CLASS" in t)
		app.handle_key(K.key(KEY_ENTER))                           # analyst
		assert_eq(w.cls, "analyst")
		if app.overlay == "contract":                              # floor 3 may come with a sponsor offer
			app.handle_key(K.letter("n"))
		assert_eq(app.overlay, "")

		for row in w.floor.explored:
			row.fill(1)
		for m: Monster in w.monsters:
			w.visible[Vector2i(m.x, m.y)] = true
		w.scout_turns = 20
		_shot(app, h, g)

		w.pet.downed = true
		w.inventory = ["sock", "mug", "trophy", "pan"]
		w.player.x = w.floor.safe_room.centre().x
		w.player.y = w.floor.safe_room.centre().y
		w.update_fov()
		app.handle_key(K.letter("m"))
		_shot(app, h, g)
		app.cursor = MenuModels.menu_actions(w).find("craft")
		app.handle_key(K.key(KEY_ENTER))
		assert_eq(app.overlay, "craft")
		_shot(app, h, g)
		app.handle_key(K.key(KEY_ENTER))                           # sock tea
		assert_true(w.inventory.has("tonic"))
		app.handle_key(K.key(KEY_ESCAPE))
		assert_eq(app.overlay, "safe")
		app.cursor = MenuModels.menu_actions(w).find("save")       # crafting earned a box, so rows moved
		app.handle_key(K.key(KEY_ENTER))
		assert_true(app.scene == "title" and FileAccess.file_exists(dir + "slot.json"))
		t = _shot(app, h, g)
		assert_true("L to continue your saved run" in t)
		app.handle_key(K.letter("l"))
		assert_true(app.loading)                                   # the loading note first ...
		h.sync()
		assert_true("Loading your saved run..." in h.menu_texts)
		app.update(0.0)                                            # ... and the load on the next frame
		assert_true(app.scene == "game" and app.world.cls == "analyst" and app.world.pet.downed)
		assert_false(app.loading)


func test_loading_a_missing_or_broken_save_keeps_the_title() -> void:
	var dir := TestHelpers.tmp_dir("broken_save")
	var app: AppState = _screen(1, dir + "slot.json")[0]
	assert_false(app.load_run())                                   # no file: SaveGame logs the error and returns null
	assert_eq(app.scene, "title")
	assert_true(app.load_failed)
	var fa := FileAccess.open(dir + "slot.json", FileAccess.WRITE)
	fa.store_string("{ not json")
	fa.close()
	app.handle_key(K.letter("l"))
	assert_true(app.loading)
	app.update(0.0)
	assert_eq(app.scene, "title")
	assert_false(app.loading)
	assert_push_error_count(2)


# --- Sponsor offer, shop, trade up, reroll, report (test_phase4_screens_draw) ----------------------------

func test_phase4_screens_draw() -> void:
	for view in ["top", "fp"]:
		var sc := _screen(5)
		var app: AppState = sc[0]
		var h: Hud = sc[1]
		var g: GameView = sc[2]
		var w := _start(app)
		g.set_view(view)
		w.new_floor(2)
		w.pending_offer = "hazard_pay"
		app.handle_key(K.key(KEY_PERIOD, "."))
		assert_eq(app.overlay, "contract")
		var t := _shot(app, h, g)
		assert_true("SPONSOR OFFER" in t)
		app.handle_key(K.letter("y"))
		assert_true(w.contract == "hazard_pay" and app.overlay == "")

		w.gold = 200
		w.boxes = ["silver", "silver", "silver", "silver"]
		w.player.x = w.floor.safe_room.centre().x
		w.player.y = w.floor.safe_room.centre().y
		w.update_fov()
		app.handle_key(K.letter("m"))
		app.cursor = MenuModels.menu_actions(w).find("shop")
		app.handle_key(K.key(KEY_ENTER))
		assert_eq(app.overlay, "shop")
		app.handle_key(K.key(KEY_ENTER))                           # buy a tonic
		assert_true(w.inventory.has("tonic") and w.gold < 200)
		_shot(app, h, g)
		app.handle_key(K.key(KEY_TAB))                             # Tab in the shop is buy/sell, not the view
		assert_true(app.shop_mode == "sell" and g.view == view and app.overlay == "shop")
		t = _shot(app, h, g)
		assert_true("They pay" in t)
		app.handle_key(K.key(KEY_ESCAPE))
		assert_eq(app.overlay, "safe")

		app.cursor = MenuModels.menu_actions(w).find("box")
		app.handle_key(K.key(KEY_ENTER))
		assert_true(app.overlay == "box" and app.box_tier == "silver")
		_shot(app, h, g)
		app.handle_key(K.letter("t"))                              # trade 3 silver for a gold
		assert_true(w.boxes.count("gold") == 1 and w.boxes.count("silver") == 1)
		app.handle_key(K.key(KEY_ENTER))                           # open the remaining silver
		assert_eq(app.overlay, "reveal")
		_shot(app, h, g)
		var gold := w.gold
		app.handle_key(K.letter("r"))                              # reroll
		assert_true(w.gold < gold and w.box_log.size() == 2)

		w.state = "dead"
		w.death_cause = "Killed by a unit test on floor 2"
		app.overlay = ""
		app.handle_key(K.letter("r"))
		assert_eq(app.overlay, "report")
		t = _shot(app, h, g)
		assert_true("RUN REPORT" in t)
		app.handle_key(K.key(KEY_ESCAPE))
		assert_eq(app.overlay, "")


func test_attribute_screen_spends_points() -> void:
	for view in ["top", "fp"]:
		var sc := _screen()
		var app: AppState = sc[0]
		var h: Hud = sc[1]
		var g: GameView = sc[2]
		var w := _start(app)
		g.set_view(view)
		var pts: int = w.player.stat_points
		app.handle_key(K.letter("l"))
		assert_eq(app.overlay, "attributes")
		_shot(app, h, g)
		app.handle_key(K.key(KEY_ENTER, "\r"))                     # first row: Strength
		assert_true(w.player.stat_points == pts - 1 and w.player.attrs["str"] == 11)
		app.handle_key(K.letter("d"))                              # D spends too (Python: Right or D)
		assert_eq(w.player.stat_points, pts - 2)
		app.handle_key(K.key(KEY_RIGHT))
		assert_eq(w.player.stat_points, pts - 3 if pts >= 3 else 0)
		app.handle_key(K.letter("l"))
		assert_eq(app.overlay, "")
		_shot(app, h, g)


# --- Tab, Esc, end screens and keys ------------------------------------------------------------------

func test_tab_cycles_gender_and_species() -> void:
	var app: AppState = _screen()[0]
	app.handle_key(K.key(KEY_ENTER))
	var gi := app.gender_idx
	app.handle_key(K.key(KEY_TAB))
	assert_true(app.scene == "identity" and app.gender_idx != gi and app.view == "fp")
	app.handle_key(K.key(KEY_ENTER))
	app.handle_key(K.key(KEY_ENTER))
	var pet := app.pet_idx
	app.handle_key(K.key(KEY_TAB))
	assert_true(app.scene == "pet_select" and app.pet_idx != pet and app.view == "fp")


func test_an_open_menu_swallows_tab_and_the_end_screens_ignore_it() -> void:
	var path := TestHelpers.tmp_dir("app_tab") + "settings.json"
	var sc := _screen(1, "", path)
	var app: AppState = sc[0]
	var w := _start(app)
	app.handle_key(K.letter("i"))
	app.handle_key(K.key(KEY_TAB))                                 # an open menu swallows Tab
	assert_true(app.view == "fp" and app.overlay == "inventory")
	app.handle_key(K.key(KEY_ESCAPE))
	var turn := w.turn
	app.handle_key(K.key(KEY_TAB))
	assert_true(app.view == "top" and w.turn == turn)
	assert_eq(UserSettings.load(path)["view"], "top")
	assert_eq(AppState.new({"settings_path": path, "runs_dir": ""}).view, "top")
	app.handle_key(K.key(KEY_TAB))
	assert_eq(app.view, "fp")
	w.state = "dead"
	w.death_cause = "Killed by a unit test"
	app.handle_key(K.key(KEY_TAB))
	assert_true(app.view == "fp" and app.scene == "game")
	app.handle_key(K.key(KEY_ENTER))
	assert_eq(app.scene, "identity")


func test_esc_in_play_goes_to_the_title_and_the_end_screen_keys() -> void:
	var app: AppState = _screen()[0]
	var w := _start(app)
	app.handle_key(K.key(KEY_ESCAPE))
	assert_eq(app.scene, "title")
	app.scene = "game"
	w.state = "dead"
	w.death_cause = "Killed by a unit test"
	app.handle_key(K.greater())                                    # ">" does not restart: Enter only
	assert_eq(app.scene, "game")
	app.handle_key(K.key(KEY_KP_ENTER))
	assert_eq(app.scene, "identity")
	app.scene = "game"
	app.handle_key(K.letter("r"))                                  # R opens the report
	assert_eq(app.overlay, "report")
	app.handle_key(K.key(KEY_ENTER))
	assert_eq(app.overlay, "")
	app.handle_key(K.letter("r"))
	app.handle_key(K.letter("k"))                                  # K also closes it, as Python
	assert_eq(app.overlay, "")


func test_play_keys_route_to_the_rules() -> void:
	var app: AppState = _screen()[0]
	var w := _start(app)
	w.monsters.clear()
	var msgs := w.messages.lines.size()
	app.handle_key(K.letter("m"))                                  # not in a safe room
	assert_eq(app.overlay, "")
	assert_eq(w.messages.lines.size(), msgs + 1)
	assert_eq(w.messages.lines[-1][0], "The menu is only available in a safe room.")
	var seen := _record(w, "item_pickup")
	w.floor_items[Vector2i(w.player.x, w.player.y)] = ["tonic"]
	app.handle_key(K.letter("g"))
	assert_true(w.inventory.has("tonic"))
	assert_eq(seen.size(), 1)
	var turn := w.turn
	app.handle_key(K.key(KEY_SPACE, " "))                          # wait
	assert_eq(w.turn, turn + 1)
	app.handle_key(K.letter("c"))                                  # command pet: toggles its mode
	app.handle_key(K.letter("k"))
	assert_eq(app.overlay, "skills")
	app.handle_key(K.letter("k"))
	assert_eq(app.overlay, "")
	app.handle_key(K.key(KEY_1, "1"))                              # no class yet: the skill does nothing
	assert_eq(app.overlay, "")
	app.handle_key(K.key(KEY_F1))                                  # F1 is help too
	assert_true(app.show_help)
	app.handle_key(K.key(KEY_ESCAPE))
	assert_false(app.show_help)


func test_rest_in_the_safe_room_and_the_menu_row() -> void:
	var app: AppState = _screen()[0]
	var w := _start(app)
	w.monsters.clear()
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	w.update_fov()
	w.player.hp = 1
	app.handle_key(K.letter("r"))                                  # R rests in play
	assert_eq(w.player.hp, w.player.max_hp)
	w.player.hp = 1
	app.handle_key(K.letter("m"))
	app.handle_key(K.key(KEY_ENTER))                               # the first row: Rest to full HP
	assert_true(app.overlay == "" and w.player.hp == w.player.max_hp)


func test_f2_asks_for_the_next_render_scale_unless_a_menu_is_open() -> void:
	var app: AppState = _screen()[0]
	var seen: Array = []
	app.render_scale_requested.connect(func() -> void: seen.append(1))
	_start(app)
	app.handle_key(K.key(KEY_F2))
	assert_eq(seen.size(), 1)
	app.handle_key(K.letter("i"))
	app.handle_key(K.key(KEY_F2))
	assert_eq(seen.size(), 1)


# --- Menus in first-person leave you where you were -------------------------------------------------

func test_menus_in_first_person_leave_you_where_you_were() -> void:
	var sc := _screen()
	var app: AppState = sc[0]
	var h: Hud = sc[1]
	var w := _start(app)
	assert_eq(app.view, "fp")
	w.monsters.clear()
	var v := app.fp.view
	var p := w.player

	var check := func(opened: Array, closing: Array, cursor_keys: bool = true) -> void:
		## Open with the first key, W/S the cursor, close with the rest: no move, no turn.
		var pos := Vector2i(p.x, p.y)
		var facing := v.facing
		var turn := w.turn
		app.handle_key(opened[0])
		assert_true(app.overlay != "" or app.show_help)
		h.sync()
		if cursor_keys:
			app.handle_key(K.letter("s"))
			app.handle_key(K.letter("w"))
		for k in closing:
			app.handle_key(k)
		assert_true(app.overlay == "" and not app.show_help)
		assert_eq(Vector2i(p.x, p.y), pos)
		assert_eq(v.facing, facing)
		assert_eq(w.turn, turn)

	w.inventory = ["tonic", "pan"]
	app.handle_key(K.letter("i"))
	app.handle_key(K.letter("s"))                                  # S moves the cursor, not the player
	assert_eq(app.cursor, 1)
	app.handle_key(K.key(KEY_ESCAPE))
	check.call([K.letter("i")], [K.key(KEY_ESCAPE)])
	check.call([K.letter("i")], [K.letter("i")])
	check.call([K.letter("k")], [K.letter("k")], false)
	check.call([K.letter("l")], [K.letter("l")])
	check.call([K.question()], [K.question()])

	w.remote_shop = true                                           # a Supply Drop out in the dungeon
	app.overlay = "shop"
	app.cursor = 0
	app.shop_mode = "buy"
	h.sync()
	assert_true("SUPPLY DROP" in h.menu_texts)
	app.handle_key(K.key(KEY_TAB))                                 # no selling from a Supply Drop
	assert_true(app.shop_mode == "buy" and app.view == "fp")
	app.handle_key(K.key(KEY_ESCAPE))
	assert_true(app.overlay == "" and not w.remote_shop)

	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	w.update_fov()
	v.face_open(w)
	w.add_box("bronze", "test")
	check.call([K.letter("m")], [K.key(KEY_ESCAPE)])
	var labels := MenuModels.menu_actions(w)
	for action in ["shop", "craft", "box"]:
		app.handle_key(K.letter("m"))
		app.cursor = labels.find(action)
		app.handle_key(K.key(KEY_ENTER))
		assert_eq(app.overlay, action)
		var spot := Vector2i(p.x, p.y)
		var facing := v.facing
		h.sync()
		for _i in 2:
			app.handle_key(K.key(KEY_ESCAPE))
		assert_true(app.overlay == "" and Vector2i(p.x, p.y) == spot and v.facing == facing)


func test_camera_lands_on_the_tile_under_a_menu_through_the_app() -> void:
	var app: AppState = _screen()[0]
	var w := _start(app)
	w.monsters.clear()
	var v := app.fp.view
	app.fp.update(1.0, [])
	for _i in 8:
		var d := v.relative("forward")
		if _empty(w, w.player.x + d.x, w.player.y + d.y):
			break
		v.tap_turn(1)
	app.handle_key(K.letter("w"))
	app.update(1.0 / 30.0, [])
	assert_true(v.glide_left(w) > 0 and v.glide_left(w) < 1)
	app.handle_key(K.letter("i"))                                  # a menu opens mid-glide
	for _i in 30:
		app.update(1.0 / 30.0, [&"walk_forward"])                  # a held W does not walk under the menu
	assert_eq(v.glide_left(w), 0.0)
	assert_false(app.animating())


# --- Saving, loading and the open way (test_new_runs_and_floors_face_the_most_open_way, load part) ---------

func _open_run(floor_: DungeonFloor, x: int, y: int, d: int) -> int:
	var s: Vector2i = FpLogic.DIRS[d]
	var n := 0
	while floor_.walkable(x + s.x * (n + 1), y + s.y * (n + 1)):
		n += 1
	return n


func test_new_runs_and_floors_face_the_most_open_way_and_a_load_does_too() -> void:
	var dir := TestHelpers.tmp_dir("open_way")
	var app: AppState = _screen(1, dir + "slot.json")[0]
	var w := _start(app)
	var v := app.fp.view
	var facing_is_open := func() -> bool:
		var best := 0
		for d in 4:
			best = maxi(best, _open_run(w.floor, w.player.x, w.player.y, d))
		var here := _open_run(w.floor, w.player.x, w.player.y, v.facing)
		return here == best and best > 0
	assert_true(facing_is_open.call())
	v.turn(1)
	w.new_floor(2)                                                 # what descend does
	app.handle_key(K.key(KEY_PERIOD, "."))
	assert_true(facing_is_open.call())
	v.turn(1)
	assert_true(SaveGame.save(w, app.save_path))
	assert_true(app.load_run())
	w = app.world
	v = app.fp.view
	assert_true(facing_is_open.call())


func test_save_and_quit_then_continue_keeps_the_run() -> void:
	var dir := TestHelpers.tmp_dir("save_quit")
	var app: AppState = _screen(2, dir + "slot.json")[0]
	var w := _start(app)
	w.monsters.clear()
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	w.update_fov()
	w.gold = 77
	app.handle_key(K.letter("m"))
	app.cursor = MenuModels.menu_actions(w).find("save")
	app.handle_key(K.key(KEY_ENTER))
	assert_true(app.scene == "title" and app.overlay == "")
	app.handle_key(K.letter("l"))
	app.update(0.0)
	assert_true(app.scene == "game" and app.world != w)
	assert_eq(app.world.gold, 77)
	assert_eq(app.world.seed, 2)


func test_a_run_that_ends_is_logged_once() -> void:
	var dir := TestHelpers.tmp_dir("app_runs")
	var app := AppState.new({"seed": 3, "runs_dir": dir, "settings_path": "", "save_path": dir + "slot.json"})
	for _i in 4:
		app.handle_key(K.key(KEY_ENTER))
	assert_true(app.telemetry != null)
	app.world.state = "dead"
	app.world.death_cause = "Killed by a unit test"
	app.update(0.0)
	assert_eq(app.logged_runs, 1)
	app.update(0.0)
	assert_eq(app.logged_runs, 1)
	assert_true(DirAccess.get_files_at(dir).size() > 1)

class_name MenuSweep
extends RefCounted
## Every screen of the pygame screenshot sweep (tests/test_render.py with CRAWL_SCREENSHOTS): the
## scenes and menus of `test_all_scenes_draw`, `test_item_screens_draw`, `test_phase3_screens_draw`,
## `test_phase4_screens_draw`, the attribute, skills, tab, monster, combat and attack of opportunity
## screens, and `test_screenshot_sweep_of_every_screen_in_both_views` (names prefixed "sweep_"),
## driven with the same keys on the same seeds through the real GameView, Hud and AppState.
##
## `shot` is called with (name, app, hud, game_view) at each screen and may be a coroutine: the
## screenshot tool (tools/screenshots.gd) saves the window in both views for each, the headless test
## (tests/ui/test_menus.gd) only checks that every screen builds. Names are pygame's, so the PNGs
## pair up by file name in scripts/fp_compare_shots.py.

const K := preload("res://tools/key_events.gd")
## The thirty screens of the pygame sweep, in its order.
const SWEEP: Array[String] = ["title", "identity", "backstory", "pet_select", "game", "game_revealed", "help",
		"inventory", "safe_room", "safe", "box", "reveal", "shop_buy", "shop_sell", "craft",
		"skills", "attributes", "contract", "class_race", "class_class", "shop_remote",
		"combat_start", "combat_mid", "aoo_warning", "aoo_log", "inventory_combat",
		"help_combat", "report", "death", "victory"]

var parent: Node = null              ## where each run's GameView and Hud are put
var shot: Callable                   ## (name, app, hud, game_view), may be a coroutine
var names: Array[String] = []        ## every shot taken, in order
var tmp_dir: String = "user://sweep_tmp/"
var _holder: Control = null
var _prefix: String = ""
var app: AppState = null
var hud: Hud = null
var gv: GameView = null


func _init(parent_node: Node, shot_callable: Callable) -> void:
	parent = parent_node
	shot = shot_callable


# --- Helpers ----------------------------------------------------------------------------------------

## A fresh GameView with a Hud over it and its AppState, nothing written to the player's files.
func _new(seed_value: int, save_name: String = "slot.json") -> void:
	if _holder != null:
		_holder.queue_free()
		await parent.get_tree().process_frame
	_holder = Control.new()
	_holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	_holder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(_holder)
	gv = (load("res://scenes/game_view.tscn") as PackedScene).instantiate()
	gv.settings_path = ""
	gv.runs_dir = ""
	gv.input_enabled = false
	gv.app.seed_value = seed_value
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	gv.app.save_path = tmp_dir + save_name
	_holder.add_child(gv)
	gv.set_anchors_preset(Control.PRESET_TOP_LEFT)
	gv.size = Vector2(1024, 640)
	hud = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	_holder.add_child(hud)
	hud.bind(gv)
	app = gv.app


func _release() -> void:
	if _holder != null:
		_holder.queue_free()
		_holder = null


func _shot(shot_name: String) -> void:
	var full := _prefix + shot_name
	names.append(full)
	gv.set_shown(app.scene == AppState.GAME)
	await shot.call(full, app, hud, gv)


func _key(keycode: Key, typed: String = "") -> void:
	app.handle_key(K.key(keycode, typed))


func _letter(ch: String) -> void:
	app.handle_key(K.letter(ch))


func _type(text: String) -> void:
	for ch in text:
		_letter(ch)


## Python `_start`: Enter four times, the world.
func _begin() -> World:
	for _i in 4:
		_key(KEY_ENTER)
	return app.world


func _empty(w: World, x: int, y: int) -> bool:
	return w.floor.walkable(x, y) and w.monster_at(x, y) == null and w.pet_at(x, y) == null


## Python `_corridor`: a tile and a direction (0-7) with exactly n empty tiles ahead, then solid.
func _corridor(w: World, n: int, dirs: Array = [0, 1, 2, 3, 4, 5, 6, 7]) -> Array:
	var f := w.floor
	for y in f.height:
		for x in f.width:
			if not _empty(w, x, y) or f.is_safe(x, y):
				continue
			for d: int in dirs:
				var s: Vector2i = FpLogic.DIRS8[d]
				var run := 0
				while _empty(w, x + s.x * (run + 1), y + s.y * (run + 1)):
					run += 1
				if run == n and not f.walkable(x + s.x * (n + 1), y + s.y * (n + 1)):
					return [Vector2i(x, y), d]
	push_error("MenuSweep: no corridor of %d" % n)
	return [Vector2i.ZERO, 0]


## Python `_place`: stand there, look 10 degrees off the line, snap the camera.
func _place(spot: Vector2i, d: int) -> void:
	var w := app.world
	w.player.x = spot.x
	w.player.y = spot.y
	w.update_fov()
	app.fp.view.angle = d * 45 + 10
	app.fp.view.reset_camera()
	gv.fp_view.refresh(0.0)


func _to_safe_room(w: World) -> void:
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	w.update_fov()


## Python `_combat`: a sturdy, stunned monster `gap` tiles down a straight corridor, a fight on.
func _combat(gap: int = 2, boss: bool = false) -> Array:
	var w := app.world
	w.monsters.clear()
	w.pet.downed = true
	w.player.max_hp = 999
	w.player.hp = 999
	var found := _corridor(w, 3, [0, 2, 4, 6])
	var spot: Vector2i = found[0]
	var d: int = found[1]
	_place(spot, d)
	var s: Vector2i = FpLogic.DIRS8[d]
	var m := Bosses.spawn_boss(w.depth, spot.x + gap * s.x, spot.y + gap * s.y) if boss \
			else Entities.spawn_monster("goblin", spot.x + gap * s.x, spot.y + gap * s.y)
	m.hp = 999
	m.max_hp = 999
	w.monsters.append(m)
	w.update_fov()
	w.join_combat(m)
	w.combat.round = 1
	m.stunned = 99
	app.fp.view.angle = d * 45
	return [m, s]


# --- Every scenario ---------------------------------------------------------------------------------

## Run every scenario (the individual tests' shots, then the sweep). Returns when the last shot is taken.
func run_all() -> void:
	await scenes()
	await items()
	await phase3()
	await phase4()
	await attributes()
	await tab_and_help()
	await monsters()
	await skills()
	await combat()
	await sweep()
	_release()


## test_all_scenes_draw
func scenes() -> void:
	_prefix = ""
	await _new(1)
	await _shot("title")
	_key(KEY_ENTER)
	_type("Daz")
	_key(KEY_RIGHT)                                                # Man
	await _shot("identity")
	_key(KEY_ENTER)
	for _i in 5:
		_key(KEY_DOWN)                                              # Tradie
	await _shot("backstory")
	_key(KEY_ENTER)
	_type("Rex")
	_key(KEY_RIGHT)
	await _shot("pet_select")
	_key(KEY_ENTER)
	gv.set_view("top")                                              # the walk uses absolute arrows
	for _i in 4:
		_key(KEY_RIGHT)
	gv.set_view("fp")
	await _shot("game")
	for row in app.world.floor.explored:                            # reveal the whole map
		row.fill(1)
	await _shot("game_revealed")
	app.handle_key(K.question())
	await _shot("help")
	app.handle_key(K.question())
	app.world.state = "dead"
	app.world.death_cause = "Killed by a unit test on floor 1"
	await _shot("death")
	app.world.state = "victory"
	await _shot("victory")


## test_item_screens_draw
func items() -> void:
	_prefix = ""
	await _new(1)
	var w := _begin()
	w.inventory = ["pan", "jersey", "tonic", "popper", "sock", "elixir"]
	w.equip(0)
	w.floor_items[Vector2i(w.player.x + 1, w.player.y)] = ["brew"]
	w.add_box("bronze", "Show Stopper: The Shrink-Wrapped Colossus. Took down floor 5's Headliner, The Shrink-Wrapped Colossus.")
	w.add_box("legendary", "test")
	w.toasts.append([w.turn, "Achievement: First Blood", "silver", "Silver box. Open it in a safe room."])
	await _shot("game_items")
	_letter("i")
	_key(KEY_DOWN)
	await _shot("inventory")
	_letter("d")
	_key(KEY_ESCAPE)
	_to_safe_room(w)
	_letter("m")
	_key(KEY_DOWN)
	await _shot("safe_menu")
	_key(KEY_ENTER)                                                 # bronze box odds
	await _shot("box_odds")
	_key(KEY_ENTER)                                                 # open it
	await _shot("box_reveal")
	_key(KEY_ENTER)
	_key(KEY_ESCAPE)
	w.state = "dead"
	w.death_cause = "Killed by a unit test"
	await _shot("death_viewers")


## test_phase3_screens_draw
func phase3() -> void:
	_prefix = ""
	await _new(3)
	var w := _begin()
	w.new_floor(3)
	_key(KEY_PERIOD, ".")                                           # any key opens the class picker
	await _shot("class_race")
	_key(KEY_DOWN)
	_key(KEY_ENTER)                                                 # elf
	_key(KEY_DOWN)
	_key(KEY_DOWN)
	await _shot("class_class")
	_key(KEY_ENTER)                                                 # analyst
	if app.overlay == "contract":
		_letter("n")
	for row in w.floor.explored:
		row.fill(1)
	for m: Monster in w.monsters:
		w.visible[Vector2i(m.x, m.y)] = true
	w.scout_turns = 20
	await _shot("scout_report")
	w.pet.downed = true
	w.inventory = ["sock", "mug", "trophy", "pan"]
	_to_safe_room(w)
	_letter("m")
	await _shot("safe_menu_p3")
	app.cursor = MenuModels.menu_actions(w).find("craft")
	_key(KEY_ENTER)
	await _shot("craft")
	_key(KEY_ENTER)                                                 # sock tea
	_key(KEY_ESCAPE)
	app.cursor = MenuModels.menu_actions(w).find("save")
	_key(KEY_ENTER)
	await _shot("title_with_save")


## test_phase4_screens_draw
func phase4() -> void:
	_prefix = ""
	await _new(5)
	var w := _begin()
	w.new_floor(2)
	w.pending_offer = "hazard_pay"
	_key(KEY_PERIOD, ".")
	await _shot("contract")
	_letter("y")
	w.gold = 200
	w.boxes = ["silver", "silver", "silver", "silver"]
	_to_safe_room(w)
	_letter("m")
	app.cursor = MenuModels.menu_actions(w).find("shop")
	_key(KEY_ENTER)
	_key(KEY_ENTER)                                                 # buy a tonic
	await _shot("shop_buy")
	_key(KEY_TAB)
	await _shot("shop_sell")
	_key(KEY_ESCAPE)
	app.cursor = MenuModels.menu_actions(w).find("box")
	_key(KEY_ENTER)
	await _shot("box_odds_silver")
	_letter("t")                                                    # trade 3 silver for a gold
	_key(KEY_ENTER)                                                 # open the remaining silver
	await _shot("reveal_reroll")
	_letter("r")                                                    # reroll
	w.state = "dead"
	w.death_cause = "Killed by a unit test on floor 2"
	app.overlay = ""
	_letter("r")
	await _shot("report")


## test_attribute_screen_spends_points
func attributes() -> void:
	_prefix = ""
	await _new(1)
	_begin()
	_letter("l")
	await _shot("attributes")
	_key(KEY_ENTER, "\r")
	_letter("l")
	await _shot("game_attributes_panel")


## test_tab_toggles_and_remembers_the_view and test_help_lists_the_controls_for_the_view
func tab_and_help() -> void:
	_prefix = ""
	await _new(1)
	_begin()
	_key(KEY_TAB)
	await _shot("game_tab")
	_key(KEY_TAB)
	app.handle_key(K.question())
	await _shot("help_game")


## test_forward_attacks_and_a_monster_in_view_draws
func monsters() -> void:
	_prefix = ""
	await _new(1)
	var w := _begin()
	w.monsters.clear()
	var v := app.fp.view
	var p := w.player
	var f := Vector2i.ZERO
	for _i in 4:                                                    # face an open tile
		f = v.relative("forward")
		if _empty(w, p.x + f.x, p.y + f.y) and _empty(w, p.x + 2 * f.x, p.y + 2 * f.y):
			break
		v.turn(1)
	w.monsters.append(Entities.spawn_monster("goblin", p.x + 2 * f.x, p.y + 2 * f.y))
	w.update_fov()
	await _shot("game_monster")
	w.monsters.clear()
	w.monsters.append(Entities.spawn_monster("goblin", p.x + f.x, p.y + f.y))
	w.update_fov()
	await _shot("game_monster_adjacent")


## test_skills_screen_draws and the Supply Drop shop of test_menus_in_first_person...
func skills() -> void:
	_prefix = ""
	await _new(1)
	var w := _begin()
	var keys := Practice.skills().keys()
	var i := 0
	for j in range(0, keys.size(), 2):                              # some discovered, some still ???
		w.training.gain(keys[j], 3 * i + 1)
		i += 1
	_letter("k")
	await _shot("skills")
	_letter("k")
	w.remote_shop = true
	app.overlay = "shop"
	app.cursor = 0
	app.shop_mode = "buy"
	await _shot("shop_remote")


## test_combat_tracker_and_screens_in_both_views and test_combat_with_a_boss_draws
func combat() -> void:
	_prefix = ""
	await _new(1)
	_begin()
	var c := _combat()
	var w := app.world
	var goblin: Monster = c[0]
	var s: Vector2i = c[1]
	await _shot("combat_start")
	w.move_player(s.x, s.y)
	await _shot("combat_mid")
	w.wait()
	w.move_player(s.x, s.y)
	await _shot("combat_attacked")
	w.inventory.append("tonic")
	app.open_overlay("inventory")
	await _shot("inventory_combat")
	app.overlay = ""
	app.show_help = true
	await _shot("help_combat")
	app.show_help = false
	w.player.attack = 100
	goblin.hp = 1
	w.wait()
	w.move_player(s.x, s.y)
	await _shot("combat_end")
	await _new(1)
	_begin()
	_combat(2, true)
	await _shot("combat_boss")


## test_screenshot_sweep_of_every_screen_in_both_views
func sweep() -> void:
	_prefix = "sweep_"
	await _new(1)
	await _shot("title")
	for scene_name in ["identity", "backstory", "pet_select"]:
		_key(KEY_ENTER)
		await _shot(scene_name)
	_key(KEY_ENTER)
	var w := app.world
	await _shot("game")
	var explored: Array = []
	for row in w.floor.explored:
		explored.append(row.duplicate())
		row.fill(1)
	await _shot("game_revealed")
	for y in explored.size():
		w.floor.explored[y] = explored[y]
	app.show_help = true
	await _shot("help")
	app.show_help = false
	w.inventory = ["pan", "tonic", "popper", "sock", "elixir"]
	app.open_overlay("inventory")
	await _shot("inventory")

	app.overlay = ""
	_to_safe_room(w)
	var best := Vector2i.ZERO
	var best_d := 1 << 30
	for t: Vector2i in w.floor.furniture:
		var dd := (t.x - w.player.x) * (t.x - w.player.x) + (t.y - w.player.y) * (t.y - w.player.y)
		if dd < best_d:
			best_d = dd
			best = t
	app.fp.view.angle = fposmod(rad_to_deg(atan2(best.x - w.player.x, w.player.y - best.y)), 360.0)
	app.fp.view.reset_camera()
	gv.fp_view.refresh(0.0)
	await _shot("safe_room")                                        # inside, facing the furniture
	w.gold = 300
	app.open_overlay("safe")
	await _shot("safe")
	w.add_box("bronze", "A sweep test.")
	app.overlay = "box"
	app.box_tier = "bronze"
	await _shot("box")
	w.open_box("bronze")
	app.overlay = "reveal"
	await _shot("reveal")
	app.overlay = "shop"
	app.cursor = 0
	app.shop_mode = "buy"
	await _shot("shop_buy")
	app.shop_mode = "sell"
	await _shot("shop_sell")
	for overlay_name in ["craft", "skills", "attributes"]:
		app.open_overlay(overlay_name)
		await _shot(overlay_name)
	w.pending_offer = "hazard_pay"
	app.open_overlay("contract")
	await _shot("contract")
	w.pending_offer = null
	app.open_overlay("class")
	app.class_step = "race"
	app.class_race = ""
	await _shot("class_race")
	app.class_step = "class"
	app.class_race = "human"
	await _shot("class_class")
	app.overlay = ""

	w.monsters.clear()
	w.pet.downed = true
	w.player.max_hp = 999
	w.player.hp = 999
	var found := _corridor(w, 3, [0, 2, 4, 6])
	var spot: Vector2i = found[0]
	var d: int = found[1]
	_place(spot, d)
	app.fp.view.angle = d * 45
	w.remote_shop = true
	app.overlay = "shop"
	app.cursor = 0
	app.shop_mode = "buy"
	await _shot("shop_remote")
	w.remote_shop = false
	app.overlay = ""
	var s: Vector2i = FpLogic.DIRS8[d]
	var g := Entities.spawn_monster("goblin", spot.x + 3 * s.x, spot.y + 3 * s.y)   # down the corridor
	g.hp = 999
	g.max_hp = 999
	w.monsters.append(g)
	w.join_combat(g)
	w.combat.round = 1
	g.stunned = 99                                                  # it waits for the pictures
	app.update(1.0 / 30.0, [])
	await _shot("combat_start")
	w.move_player(s.x, s.y)
	await _shot("combat_mid")                                       # one step taken, move spent
	w.wait()                                                        # next round
	g.x = w.player.x - s.x
	g.y = w.player.y - s.y
	g.stunned = 0                                                   # now right behind you
	w.update_fov()
	await _shot("aoo_warning")
	_letter("w")                                                    # step away: it swings
	await _shot("aoo_log")
	app.open_overlay("inventory")
	await _shot("inventory_combat")
	app.overlay = ""
	app.show_help = true
	await _shot("help_combat")
	app.show_help = false

	w.state = "dead"
	w.death_cause = "Killed by a screenshot sweep on floor 1"
	app.open_overlay("report")
	await _shot("report")
	app.overlay = ""
	await _shot("death")
	w.state = "victory"
	await _shot("victory")

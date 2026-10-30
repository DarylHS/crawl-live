class_name AppState
extends RefCounted
## The game's scene state machine (crawler/game.py `App`, without the drawing): which screen is
## showing (`scene`: title, identity, backstory, pet_select or game), which menu is open over the
## game (`overlay`), the cursor, character creation, the view (first-person or map), settings, saving
## and loading, run logging, and every key and what it does in each of those states.
##
## It is headless (RefCounted): one path takes every key, `handle_key(event)`, and decides by the
## InputMap actions in `tools/input_map.gd` (so the same physical key can mean walk, move the
## cursor, spend a point or type a letter depending on the state, as `App.handle_key` does). Tests
## feed it InputEventKeys; Main feeds it the real ones. Nodes only draw what it says: Hud shows the
## menus from `scene`, `overlay` and `cursor` through MenuModels / ScreenModels / ReportModel.
##
## The first-person and map input of the game scene is delegated to `fp` (FpController) and `top`
## (TopController), which GameView's FpView and TopView use as their own, so there is one World and
## one camera whoever drives it. "" stands for Python's None in `overlay`, `class_race` and `box_tier`.
##
## Held keys (free look, held walking) are not events: `update(dt, held)` takes the held action names.
## L on the title shows "Loading your saved run..." for one frame and loads on the next `update`,
## because parsing a big save takes about 0.1 s.

signal world_started(world: World)       ## a new or loaded run is ready (GameView shows it)
signal view_changed(view: String)        ## Tab or `set_view` changed first-person / map
signal render_scale_requested            ## F2 (GameView cycles the 3D resolution)
signal setting_changed(note: String)     ## F3 or F4 changed the effects or sound setting: the note to show ("Effects: reduced")

const TITLE := "title"
const IDENTITY := "identity"
const BACKSTORY := "backstory"
const PET_SELECT := "pet_select"
const GAME := "game"

var scene: String = TITLE
var world: World = null
var show_help: bool = false
var overlay: String = ""           ## "" | inventory | safe | reveal | box | shop | craft | class | contract | report | skills | attributes
var cursor: int = 0
var pet_idx: int = 0
var pet_name: String = ""
var hero_name: String = ""
var gender_idx: int = 0
var backstory_idx: int = 0
var class_step: String = "race"    ## the class picker's step: "race" then "class"
var class_race: String = ""
var box_tier: String = ""          ## the box whose odds are showing
var shop_mode: String = "buy"      ## "buy" | "sell"
var running: bool = true           ## false after Esc on the title (Main quits)
var loading: bool = false          ## L pressed: the save loads on the next update
var seed_value: Variant = null     ## fixed seed for the first run only (Python `seed`)
var save_path: String = SaveGame.slot_path()
var runs_dir: String = "user://runs"      ## "" turns off logging your runs
var settings_path: String = UserSettings.DEFAULT_PATH   ## "" turns off remembering settings
var settings: Dictionary = UserSettings.DEFAULTS.duplicate()
var view: String = "fp"            ## "fp" (first-person) | "top" (map)
var blocked: bool = false          ## something outside (a test, a window dialog) covers the view
var fp := FpController.new()
var top := TopController.new()
var telemetry: Telemetry = null    ## the current run's telemetry, held for the run (the bus keeps no reference)
var logged_runs: int = 0           ## runs written to runs_dir so far
var load_failed: bool = false      ## the last load found no usable save (Python only prints it, and so do we)


## Options (all optional): "seed", "save_path", "runs_dir", "settings_path" (Python's App arguments).
## Settings load at once, as Python's `settings.load(settings_path)`.
func _init(options: Dictionary = {}) -> void:
	seed_value = options.get("seed")
	save_path = options.get("save_path", save_path)
	runs_dir = options.get("runs_dir", runs_dir)
	settings_path = options.get("settings_path", settings_path)
	load_settings()


## Read the settings file (defaults when `settings_path` is "" or unreadable).
func load_settings() -> void:
	settings = UserSettings.load(settings_path)
	view = settings["view"]


func save_settings() -> void:
	if not UserSettings.save(settings, settings_path):
		push_warning("Could not save settings")


## True while a menu or help covers the game (Python `covered` without the end screens).
func covered() -> bool:
	return overlay != "" or show_help


## Tab and F2 do nothing while this is true: a menu or help is open, or `blocked` is set.
func is_blocked() -> bool:
	return blocked or covered()


# --- Effects and sound settings (P8) ----------------------------------------------------------------

## F3: Effects on, reduced, off, on ... Remembered in the settings file. Works on any screen.
func cycle_effects() -> String:
	settings["effects"] = FxSettings.next_mode(String(settings.get("effects", "on")))
	save_settings()
	setting_changed.emit(FxSettings.describe_effects(settings["effects"]))
	return settings["effects"]


## F4: master volume 100, 70, 40, 10, muted, 100 ... Remembered in the settings file.
func cycle_volume() -> Dictionary:
	var nxt := FxSettings.next_volume(int(settings.get("volume", 70)), bool(settings.get("muted", false)))
	settings["volume"] = nxt["volume"]
	settings["muted"] = nxt["muted"]
	save_settings()
	setting_changed.emit(FxSettings.describe_sound(nxt["volume"], nxt["muted"]))
	return nxt


# --- Starting, loading, the view -------------------------------------------------------------------

## Show `new_world`: the camera faces its open side, run logging starts, and the game screen shows.
func attach_world(new_world: World) -> void:
	world = new_world
	_attach_telemetry()
	fp.start(world)
	top.start(world)
	scene = GAME
	show_help = false
	overlay = ""
	world_started.emit(world)


## Python `start_run`: a world from the creation screens (hero, then the companion).
func start_run(pet: Variant = null) -> void:
	var genders: Array = Content.table("genders").keys()
	var stories: Array = Content.table("backstories").keys()
	var hero := {"name": hero_name.strip_edges() if hero_name.strip_edges() != "" else "Crawler",
			"gender": genders[gender_idx], "backstory": stories[backstory_idx]}
	var w := World.new(seed_value, pet, hero)
	seed_value = null                  # only the first run uses a fixed seed
	attach_world(w)


## Python `load_run`: replace the world with the saved one (the title stays up if there is none).
func load_run() -> bool:
	load_failed = false
	var w := SaveGame.load(save_path)
	if w == null:
		load_failed = true
		print("Could not load save: %s" % save_path)
		return false
	attach_world(w)
	return true


## What L on the title does: show the loading note now, load on the next `update`.
func request_load() -> void:
	loading = true


func _attach_telemetry() -> void:
	telemetry = Telemetry.new(world, "player") if runs_dir != "" else null


## Write your finished run to runs_dir/player_*.csv once, for the analysis notebooks.
func log_run_if_over() -> void:
	if telemetry == null or world == null or world.state == "playing":
		return
	if runs_dir != "":
		DirAccess.make_dir_recursive_absolute(runs_dir)
		if PyCsv.write_tables(telemetry.tables(), runs_dir, "player_"):
			logged_runs += 1
	telemetry = null


## Tab: swap first-person and map, remembered for next time. A menu swallows it and the end screens
## ignore it. Returns true when the view changed.
func toggle_view() -> bool:
	if is_blocked() or world == null or world.state != "playing":
		return false
	set_view("top" if view == "fp" else "fp")
	return true


## Show "fp" or "top" and remember it (Python `toggle_view` after its checks): the camera snaps, with
## no stale hurt flash, since you may have moved or been hit meanwhile.
func set_view(choice: String) -> void:
	view = choice if UserSettings.VIEWS.has(choice) else "fp"
	fp.view.reset_camera()
	settings["view"] = view
	save_settings()
	view_changed.emit(view)


# --- Per frame -----------------------------------------------------------------------------------

## True while the first-person camera still needs frames to settle.
func animating() -> bool:
	return scene == GAME and view == "fp" and world != null and fp.view.animating(world)


## Per-frame work between key presses: a pending load, then free look and walking while keys are held
## in the first-person view and the camera glide. `held` (Array of action names) replaces the held set
## when given. Returns true when something changed that needs a redraw.
func update(dt: float, held: Variant = null) -> bool:
	if loading:
		loading = false
		load_run()
		return true
	fp.blocked = scene != GAME or view != "fp" or covered() or blocked
	if world == null or scene != GAME:
		return false
	var changed := fp.update(dt, held)
	log_run_if_over()
	return changed


## Fire a menu or play action by name without a key (tests and GameView.press): Tab and F2 are
## handled here, anything else goes to the controller of the view that is showing. Returns true when
## it was used.
func press(action: StringName) -> bool:
	var used := false
	if action == &"toggle_view":
		used = toggle_view()
	elif action == &"cycle_effects":
		cycle_effects()
		used = true
	elif action == &"cycle_volume":
		cycle_volume()
		used = true
	elif action == &"cycle_render_scale":
		if not is_blocked():                                   # menus swallow F2 as they do Tab
			render_scale_requested.emit()
			used = true
	elif world != null:
		if view == "fp":
			used = fp.press(action)
		else:
			used = top.press(action)
			fp.after_action()                                  # a new floor is faced the open way from the arrival tile
	log_run_if_over()
	return used


# --- Keys ----------------------------------------------------------------------------------------

## The character a key types, or "" for a key that types nothing (Enter, Esc, arrows).
static func char_of(ev: InputEventKey) -> String:
	return char(ev.unicode) if ev.unicode >= 32 else ""


## Python `ch.isalnum() or ch in " -'"`: what a name may contain.
static func is_name_char(ch: String) -> bool:
	if ch == "":
		return false
	return ch in " -'" or ch.is_valid_int() or ch.to_upper() != ch.to_lower()


## Python `App.handle_key`: one key press in any scene.
func handle_key(ev: InputEventKey) -> void:
	var ch := char_of(ev)
	if ch == "?" or ev.is_action(&"help"):
		show_help = not show_help
		return
	if show_help:
		if ev.is_action(&"back"):
			show_help = false
		return
	if ev.is_action(&"cycle_render_scale"):
		if not is_blocked():
			render_scale_requested.emit()
		return
	if ev.is_action(&"cycle_effects"):
		cycle_effects()
		return
	if ev.is_action(&"cycle_volume"):
		cycle_volume()
		return
	match scene:
		TITLE:
			_title_key(ev)
		IDENTITY:
			_identity_key(ev, ch)
		BACKSTORY:
			_backstory_key(ev)
		PET_SELECT:
			_pet_select_key(ev, ch)
		_:
			_game_key(ev, ch)


func _title_key(ev: InputEventKey) -> void:
	if ev.is_action(&"confirm"):
		scene = IDENTITY
	elif ev.is_action(&"attributes") and SaveGame.has_save(save_path):
		request_load()
	elif ev.is_action(&"back"):
		running = false


func _identity_key(ev: InputEventKey, ch: String) -> void:
	var n: int = Content.table("genders").size()
	if ev.is_action(&"back"):
		scene = TITLE
	elif ev.is_action(&"menu_left") or ev.is_action(&"menu_right") or ev.is_action(&"toggle_view"):
		gender_idx = posmod(gender_idx + (-1 if ev.is_action(&"menu_left") else 1), n)
	elif ev.is_action(&"confirm"):
		scene = BACKSTORY
	elif ev.is_action(&"erase"):
		hero_name = hero_name.left(-1) if hero_name.length() > 0 else ""
	elif is_name_char(ch) and hero_name.length() < ScreenModels.NAME_MAX:
		hero_name += ch


func _backstory_key(ev: InputEventKey) -> void:
	var n: int = Content.table("backstories").size()
	if ev.is_action(&"back"):
		scene = IDENTITY
	elif ev.is_action(&"menu_up"):
		backstory_idx = posmod(backstory_idx - 1, n)
	elif ev.is_action(&"menu_down"):
		backstory_idx = posmod(backstory_idx + 1, n)
	elif ev.is_action(&"confirm"):
		scene = PET_SELECT
		pet_name = ""


func _pet_select_key(ev: InputEventKey, ch: String) -> void:
	var species: Array = Content.table("pets").keys()
	if ev.is_action(&"back"):
		scene = BACKSTORY
	elif ev.is_action(&"menu_left") or ev.is_action(&"menu_right") or ev.is_action(&"toggle_view"):
		pet_idx = posmod(pet_idx + (-1 if ev.is_action(&"menu_left") else 1), species.size())
	elif ev.is_action(&"confirm"):
		start_run([species[pet_idx], pet_name.strip_edges()])
	elif ev.is_action(&"erase"):
		pet_name = pet_name.left(-1) if pet_name.length() > 0 else ""
	elif is_name_char(ch) and pet_name.length() < ScreenModels.NAME_MAX:
		pet_name += ch


## The game scene: an open menu takes the key, else Esc, the end screens, Tab, and play.
func _game_key(ev: InputEventKey, ch: String) -> void:
	var w := world
	if w == null:
		return
	if overlay != "":
		_overlay_key(ev)
	elif ev.is_action(&"back"):
		scene = TITLE
	elif w.state != "playing":
		if ev.is_action(&"confirm"):
			scene = IDENTITY                # same character, ready to tweak
		elif ev.is_action(&"rest"):
			open_overlay("report")
	elif ev.is_action(&"toggle_view"):
		toggle_view()
	elif ch == ">" or ev.is_action(&"confirm"):
		w.descend()
	elif _move_key(ev):
		pass
	elif ev.is_action(&"wait"):
		w.wait()
	elif ev.is_action(&"rest"):
		w.rest()
	elif ev.is_action(&"pickup"):
		w.pickup()
	elif ev.is_action(&"inventory"):
		open_overlay("inventory")
	elif ev.is_action(&"safe_menu"):
		if w.in_safe_room:
			open_overlay("safe")
		else:
			w.messages.add("The menu is only available in a safe room.", GameConfig.TEXT_DIM)
	elif ev.is_action(&"pet_command"):
		w.command_pet()
	elif ev.is_action(&"practice"):
		open_overlay("skills")
	elif ev.is_action(&"attributes"):
		open_overlay("attributes")
	elif ev.is_action(&"skill_1"):
		if w.use_skill() and w.remote_shop:
			overlay = "shop"
			cursor = 0
			shop_mode = "buy"
	_after_action()


const FP_ACTIONS: Array[StringName] = [&"walk_forward", &"walk_back", &"strafe_left", &"strafe_right",
		&"turn_left", &"turn_right"]
const MOVE_ACTIONS: Array[StringName] = [&"move_n", &"move_s", &"move_e", &"move_w", &"move_ne", &"move_nw",
		&"move_se", &"move_sw"]


## Walking, turning and compass moves: first-person walks and turns first (so W walks rather than
## moves north), then the compass moves. Returns true when the key was one of them.
func _move_key(ev: InputEventKey) -> bool:
	if view == "fp":
		for a in FP_ACTIONS:
			if ev.is_action(a):
				fp.press(a)
				return true
	for a in MOVE_ACTIONS:
		if ev.is_action(a):
			world.move_player(int(FpController.MOVES[a].x), int(FpController.MOVES[a].y))
			return true
	return false


## After any key in the game: log a finished run, face a new floor's open side, and open the class
## picker or a sponsor offer if one is waiting.
func _after_action() -> void:
	var w := world
	log_run_if_over()
	fp.after_action()
	if w.state == "playing" and overlay == "":
		if w.pending_choice:
			open_overlay("class")
			class_step = "race"
			class_race = ""
		elif PyMath.truthy(w.pending_offer):
			open_overlay("contract")


func open_overlay(name: String) -> void:
	overlay = name
	cursor = 0


## A key with a menu open.
func _overlay_key(ev: InputEventKey) -> void:
	var w := world
	var up := ev.is_action(&"menu_up")
	var down := ev.is_action(&"menu_down")
	var confirm := ev.is_action(&"confirm")
	var back := ev.is_action(&"back")
	match overlay:
		"attributes":
			var keys := Attributes.keys()
			if back or ev.is_action(&"attributes"):
				overlay = ""
			elif up:
				cursor = posmod(cursor - 1, keys.size())
			elif down:
				cursor = posmod(cursor + 1, keys.size())
			elif confirm or ev.is_action(&"menu_right") or ev.is_action(&"strafe_right"):
				w.spend_point(keys[cursor])
			return
		"report", "skills":
			if confirm or back or ev.is_action(&"practice"):
				overlay = ""
			return
		"contract":
			if ev.is_action(&"accept_deal") or confirm:
				w.accept_contract()
			elif ev.is_action(&"decline_deal") or back:
				w.decline_contract()
			else:
				return
			overlay = ""
			if w.pending_choice:
				open_overlay("class")
			return
		"reveal":
			if ev.is_action(&"reroll"):
				w.reroll()
			elif confirm or back:
				overlay = "safe" if w.in_safe_room else ""
			return
		"box":
			if back:
				overlay = "safe"
				cursor = 0
			elif ev.is_action(&"trade_up"):
				w.trade_up(box_tier)
				if not w.boxes.has(box_tier):
					overlay = "safe"
					cursor = 0
			elif confirm and w.open_box(box_tier):
				overlay = "reveal"
			return
		"shop":
			_shop_key(ev, up, down, confirm, back)
			return
		"class":
			_class_key(up, down, confirm)
			return
		"craft":
			var n := Crafting.recipes().size()
			if back:
				overlay = "safe"
				cursor = 0
			elif up:
				cursor = posmod(cursor - 1, n)
			elif down:
				cursor = posmod(cursor + 1, n)
			elif confirm:
				w.craft(cursor)
			if w.state != "playing":
				overlay = ""
			return
	# The inventory and the safe-room menu.
	if back or ev.is_action(&"inventory") or ev.is_action(&"safe_menu"):
		overlay = ""
		return
	var rows := MenuModels.inventory_rows(w) if overlay == "inventory" else MenuModels.menu_options(w)
	if up and not rows.is_empty():
		cursor = posmod(cursor - 1, rows.size())
	elif down and not rows.is_empty():
		cursor = posmod(cursor + 1, rows.size())
	elif rows.is_empty() or w.state != "playing":
		return
	elif overlay == "inventory":
		var row: Array = rows[cursor]
		if confirm and row[0] == "pack":
			w.use_item(row[1])
		elif ev.is_action(&"unequip") and row[0] == "equip":
			w.unequip(row[1])
		elif ev.is_action(&"drop") and row[0] == "pack":
			w.drop(row[1])
		cursor = mini(cursor, maxi(0, MenuModels.inventory_rows(w).size() - 1))
	elif confirm:
		var o: Array = rows[cursor]
		match o[0]:
			"rest":
				w.rest()
				overlay = ""
			"revive":
				w.revive_pet()
			"craft":
				overlay = "craft"
				cursor = 0
				return
			"box":
				overlay = "box"
				box_tier = o[1]
				return
			"shop":
				overlay = "shop"
				cursor = 0
				shop_mode = "buy"
				return
			"save":
				if SaveGame.save(w, save_path):
					scene = TITLE
					overlay = ""
				else:
					w.messages.add("Could not save your run.", GameConfig.DANGER)
				return
		cursor = mini(cursor, MenuModels.menu_options(w).size() - 1)
	if w.state != "playing":
		overlay = ""


func _shop_key(ev: InputEventKey, up: bool, down: bool, confirm: bool, back: bool) -> void:
	var w := world
	var rows := MenuModels.shop_rows(w, shop_mode)
	var remote := not w.in_safe_room
	if back:
		overlay = "" if remote else "safe"
		cursor = 0
		w.remote_shop = false                  # closing a Supply Drop ends it
	elif ev.is_action(&"toggle_view") and not remote:
		shop_mode = "sell" if shop_mode == "buy" else "buy"
		cursor = 0
	elif up and not rows.is_empty():
		cursor = posmod(cursor - 1, rows.size())
	elif down and not rows.is_empty():
		cursor = posmod(cursor + 1, rows.size())
	elif confirm and not rows.is_empty():
		if shop_mode == "buy":
			w.shop_buy(rows[cursor])
			if remote and not w.remote_shop:
				overlay = ""
		else:
			w.shop_sell(rows[cursor])
			cursor = mini(cursor, maxi(0, w.inventory.size() - 1))


func _class_key(up: bool, down: bool, confirm: bool) -> void:
	var rows := MenuModels.class_rows(class_step)
	if up:
		cursor = posmod(cursor - 1, rows.size())
	elif down:
		cursor = posmod(cursor + 1, rows.size())
	elif confirm:
		if class_step == "race":
			class_race = rows[cursor]
			class_step = "class"
			cursor = 0
		else:
			world.choose_class(class_race, rows[cursor])
			overlay = ""

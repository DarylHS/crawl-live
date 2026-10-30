class_name Main
extends Control
## Main scene (P7): the whole game from the title screen to the end screens, as `python main.py`.
##
##   godot --path godot                                    # title screen; Enter starts character creation
##   godot --path godot -- --seed 1234 --pet dog           # a fixed seed for the first run; dog preselected
##   godot --path godot -- --quick --seed 1 --pet dog      # skip the title and creation: straight into a run
##   godot --path godot -- --save-dir DIR --runs-dir DIR   # where the save, settings and run logs go
##
## Scene tree:
##   Main (Control, this script)
##     Background (ColorRect)
##     GameView (the first-person view and the map; owns the AppState)
##     Hud (side panel, log, tracker, toasts, and the menu and help canvases)
##
## This node is only the wiring: real key presses go to `app.handle_key` (one path for every scene and
## menu, ui/app/app_state.gd), held movement actions to `app.update`, and the title, creation screens
## and menus are drawn by the Hud from what the AppState says. Headless (`godot --headless --path godot`)
## it still loads every content table, prints a summary and quits, as the P0 placeholder did.

@onready var game_view: GameView = $GameView
@onready var hud: Hud = $Hud

var app: AppState = null
var note: Label = null                    ## the "Effects: reduced" note F3 and F4 flash at the top (P8)
var _note_tween: Tween = null
var _quitting: bool = false
var summary_on_headless: bool = true      ## tests turn this off to run the real scene headless
var options: Dictionary = {}              ## extra options merged over the command line (tests)
var _shown: bool = true


func _ready() -> void:
	if DisplayServer.get_name() == "headless" and summary_on_headless:
		_print_content_summary()
		return
	var args := _parse_args(OS.get_cmdline_user_args())
	args.merge(options, true)
	app = game_view.app
	configure(app, args)
	app.load_settings()
	game_view.set_input_enabled(false)       # Main takes the keys and routes them through the AppState
	game_view.fp_view.set_render_scale(app.settings["render_scale"])
	hud.bind(game_view)
	_make_note()
	app.setting_changed.connect(show_note)
	_apply_scene()
	if args.has("quick"):
		app.pet_name = ""
		app.start_run(_quick_pet(args))
		print("Crawl Live! seed %d" % app.world.seed)


## Point the app at the player's files (user://settings.json, user://runs, user://saves/slot1.json) and apply
## the command line options (`--seed`, `--pet`, `--save-dir`, `--runs-dir`) over them.
static func configure(target: AppState, args: Dictionary) -> void:
	target.settings_path = UserSettings.DEFAULT_PATH      # the real player's files unless told otherwise
	target.runs_dir = "user://runs"
	target.save_path = SaveGame.slot_path()
	if args.has("seed"):
		target.seed_value = int(args["seed"])
	if args.has("save-dir"):
		var dir: String = args["save-dir"]
		target.save_path = SaveGame.slot_path(dir)
		target.settings_path = UserSettings.settings_path(dir)
	if args.has("runs-dir"):
		target.runs_dir = args["runs-dir"]
	if args.has("pet"):
		var idx: int = Content.table("pets").keys().find(args["pet"])
		if idx >= 0:
			target.pet_idx = idx


## The companion for `--quick`: `--pet` (or the first), "none" for no companion.
static func _quick_pet(args: Dictionary) -> Variant:
	var species: String = args.get("pet", Content.table("pets").keys()[0])
	return null if species == "none" else [species, ""]


func _unhandled_input(event: InputEvent) -> void:
	if app == null:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	var before := _menu_state()
	hud.on_key()
	game_view.fx_director.on_key()           # a key press finishes moving effects: input never waits on an animation
	app.handle_key(key)
	if _menu_state() != before:
		game_view.fx_director.ui_select()    # a menu opened, closed or moved
	get_viewport().set_input_as_handled()
	_apply_scene()


## What the menus show: changes when a key moved a cursor, opened or closed a menu or went to another screen.
func _menu_state() -> Array:
	return [app.scene, app.overlay, app.cursor, app.show_help, app.pet_idx, app.gender_idx, app.backstory_idx]


## A line of text at the top of the window that fades after a moment ("Effects: reduced").
func _make_note() -> void:
	note = Label.new()
	note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	note.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	note.offset_top = 8.0
	note.offset_bottom = 40.0
	note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	note.add_theme_font_override("font", UiFonts.mono(true))
	note.add_theme_font_size_override("font_size", 20)
	note.add_theme_color_override("font_color", Color8(255, 196, 64))
	note.add_theme_color_override("font_outline_color", Color8(14, 12, 18))
	note.add_theme_constant_override("outline_size", 6)
	note.modulate.a = 0.0
	add_child(note)


## Show `text` at the top, then fade it out. A Tween is Godot's built-in animator: this one waits, then
## fades the label's alpha; starting a new note stops the old tween first.
func show_note(text: String) -> void:
	if note == null:
		return
	game_view.fx_director.ui_select()
	note.text = text
	note.modulate.a = 1.0
	if _note_tween != null:
		_note_tween.kill()
	_note_tween = create_tween()
	_note_tween.tween_interval(1.3)
	_note_tween.tween_property(note, "modulate:a", 0.0, 0.5)


func _process(delta: float) -> void:
	if app == null:
		return
	var held: Array[StringName] = []
	for a in FpView.HELD_ACTIONS:
		if Input.is_action_pressed(a):
			held.append(a)
	app.update(delta, held)
	_apply_scene()
	if not app.running and not _quitting:
		quit_game()


## Leave the game: stop the sounds and give the audio thread a moment to let go of them, then quit
## (a sound playing at exit is reported as a leaked audio object).
func quit_game() -> void:
	_quitting = true
	game_view.fx_director.sfx.stop_all()
	await get_tree().create_timer(0.25).timeout
	get_tree().quit()


## Show the game view only on the game scene (the other screens cover the window).
func _apply_scene() -> void:
	var on := app.scene == AppState.GAME
	if on != _shown:
		_shown = on
		game_view.set_shown(on)


## --key value pairs (and bare --flag) from the user arguments after `--`.
static func _parse_args(args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < args.size():
		var a := args[i]
		if a.begins_with("--"):
			var k := a.substr(2)
			if "=" in k:
				out[k.get_slice("=", 0)] = k.get_slice("=", 1)
			elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
				out[k] = args[i + 1]
				i += 1
			else:
				out[k] = ""
		i += 1
	return out


func _print_content_summary() -> void:
	var names := Content.names()
	var bad := 0
	for n in names:
		if Content.table(n) == null:
			bad += 1
	print("Crawl Live! content: %d tables (%d failed), %d monsters, %d achievements, %d lines events, manifest commit %s" % [
		names.size(), bad, Content.table("monsters").size(), Content.table("achievements").size(),
		Content.table("lines").size(), String(Content.manifest()["source_commit"]).left(8)])
	get_tree().quit(1 if bad > 0 else 0)

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
var summary_on_headless: bool = true      ## tests turn this off to run the real scene headless
var _shown: bool = true


func _ready() -> void:
	if DisplayServer.get_name() == "headless" and summary_on_headless:
		_print_content_summary()
		return
	var args := _parse_args(OS.get_cmdline_user_args())
	app = game_view.app
	configure(app, args)
	app.load_settings()
	game_view.set_input_enabled(false)       # Main takes the keys and routes them through the AppState
	game_view.fp_view.set_render_scale(app.settings["render_scale"])
	hud.bind(game_view)
	_apply_scene()
	if args.has("quick"):
		app.pet_name = ""
		app.start_run(_quick_pet(args))
		print("Crawl Live! seed %d" % app.world.seed)


## Apply the command line options (`--seed`, `--pet`, `--save-dir`, `--runs-dir`) to the app.
static func configure(target: AppState, args: Dictionary) -> void:
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
	app.handle_key(key)
	get_viewport().set_input_as_handled()
	_apply_scene()


func _process(delta: float) -> void:
	if app == null:
		return
	var held: Array[StringName] = []
	for a in FpView.HELD_ACTIONS:
		if Input.is_action_pressed(a):
			held.append(a)
	app.update(delta, held)
	_apply_scene()
	if not app.running:
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

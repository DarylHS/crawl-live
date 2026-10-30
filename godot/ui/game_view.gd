class_name GameView
extends Control
## The game screen's map area (scenes/game_view.tscn): the first-person 3D view and the top-down
## map on top of each other, one showing at a time, plus the parts of crawler/game.py `App` that
## belong to the pair: Tab switching (remembered in the settings file), the Graphics render scale
## (F2 cycles it, also remembered) and logging a finished run.
##
## Scene tree:
##   GameView (Control, this script)
##     FpView (scenes/fp_view.tscn)      the 3D view, minimap and "Facing X"
##     TopView (scenes/top_view.tscn)    the 16 px glyph map
##
## Both views read the same World. The hidden one does no work (the 3D viewport stops rendering).
## `settings_path` "" turns off the settings file and `runs_dir` "" turns off run logging, as the
## Python App's settings_path=None and runs_dir=None do for tests. P7's AppState will own the
## scene, overlays and menus; until then this node routes keys to the view that is showing.

signal new_run_requested           ## Enter pressed after the run ended
signal view_changed(view: String)

@onready var fp_view: FpView = $FpView
@onready var top_view: TopView = $TopView

var settings_path: String = UserSettings.DEFAULT_PATH   ## "" = do not read or write settings
var runs_dir: String = "user://runs"                    ## "" = do not log runs
var settings: Dictionary = UserSettings.DEFAULTS.duplicate()
var view: String = "fp"            ## "fp" | "top" (UserSettings.VIEWS)
var blocked: bool = false          ## a menu or help covers the view (P7): Tab does nothing
var input_enabled: bool = true     ## read the keyboard (off for tests and the screenshot tool)
var telemetry: Telemetry = null    ## the current run's telemetry, held for the run (the bus keeps no reference)
var logged_runs: int = 0           ## runs written to runs_dir so far


func _ready() -> void:
	settings = UserSettings.load(settings_path)
	view = settings["view"]
	fp_view.set_render_scale(settings["render_scale"])
	fp_view.input_enabled = input_enabled
	top_view.input_enabled = input_enabled
	fp_view.new_run_requested.connect(func() -> void: new_run_requested.emit())
	top_view.new_run_requested.connect(func() -> void: new_run_requested.emit())
	_show_view()


## The world being played, or null before start.
var world: World:
	get:
		return fp_view.world


## Show a new or loaded run in whichever view is current and start logging it.
func start(new_world: World) -> void:
	telemetry = Telemetry.new(new_world, "player") if runs_dir != "" else null
	fp_view.start(new_world)
	top_view.start(new_world)
	_show_view()


## Turn the keyboard on or off for both views.
func set_input_enabled(on: bool) -> void:
	input_enabled = on
	fp_view.input_enabled = on
	top_view.input_enabled = on


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled:
		return
	if event.is_action_pressed(&"toggle_view") and not (event as InputEventKey).echo:
		if toggle_view():
			get_viewport().set_input_as_handled()
	elif event.is_action_pressed(&"cycle_render_scale") and not (event as InputEventKey).echo:
		cycle_render_scale()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	log_run_if_over()


## An action name from the keyboard (or a test), routed to the view that is showing. Tab and F2
## are handled here; everything else goes to that view's controller. Returns true when it was used.
func press(action: StringName) -> bool:
	var used := false
	if action == &"toggle_view":
		used = toggle_view()
	elif action == &"cycle_render_scale":
		cycle_render_scale()
		used = true
	elif world != null:
		used = fp_view.controller.press(action) if view == "fp" else top_view.controller.press(action)
	log_run_if_over()
	return used


## Tab: swap first-person and map and remember the choice. Menus swallow it and the end screens
## ignore it (Python). Returns true when the view changed.
func toggle_view() -> bool:
	if blocked or world == null or world.state != "playing":
		return false
	set_view("top" if view == "fp" else "fp")
	return true


## Show "fp" or "top" and remember it (no menu or end-screen checks: Tab does those).
func set_view(choice: String) -> void:
	view = choice if UserSettings.VIEWS.has(choice) else "fp"
	settings["view"] = view
	_save_settings()
	_show_view()
	view_changed.emit(view)


## F2: Retro, Sharp, Full, Retro ... Remembered in the settings file.
func cycle_render_scale() -> String:
	var all := UserSettings.RENDER_SCALES
	var next: String = all[(all.find(fp_view.render_scale) + 1) % all.size()]
	set_render_scale(next)
	return next


## Choose the 3D resolution and remember it.
func set_render_scale(choice: String) -> void:
	fp_view.set_render_scale(choice)
	settings["render_scale"] = fp_view.render_scale
	_save_settings()


func _show_view() -> void:
	fp_view.set_active(view == "fp")
	top_view.set_active(view == "top")


func _save_settings() -> void:
	if not UserSettings.save(settings, settings_path):
		push_warning("Could not save settings")


## Write your finished run to runs_dir/player_*.csv once, for the analysis notebooks.
func log_run_if_over() -> void:
	var w := world
	if telemetry == null or w == null or w.state == "playing":
		return
	if runs_dir != "":
		DirAccess.make_dir_recursive_absolute(runs_dir)
		if PyCsv.write_tables(telemetry.tables(), runs_dir, "player_"):
			logged_runs += 1
	telemetry = null

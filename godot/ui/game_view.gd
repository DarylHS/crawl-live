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
## Python App's settings_path=None and runs_dir=None do for tests. P7's AppState (ui/app/app_state.gd)
## owns the scene, overlays, menus, settings and run logging; this node shows its world.

signal new_run_requested           ## Enter pressed after the run ended (standalone use; Main routes keys through AppState)
signal view_changed(view: String)

@onready var fp_view: FpView = $FpView
@onready var top_view: TopView = $TopView

## The scene state machine this view shows (crawler/game.py `App`): the two views share its
## controllers, view, settings and run logging. Made here so a GameView works on its own (tests, the
## screenshot tool); Main keys it by calling `app.handle_key`.
var app := AppState.new({"settings_path": "", "runs_dir": ""})
var input_enabled: bool = true     ## read the keyboard itself (off for Main, tests and the screenshot tool)


## "" = do not read or write settings (set before the node enters the tree).
var settings_path: String:
	get:
		return app.settings_path
	set(v):
		app.settings_path = v

## "" = do not log runs.
var runs_dir: String:
	get:
		return app.runs_dir
	set(v):
		app.runs_dir = v

var settings: Dictionary:
	get:
		return app.settings

var view: String:                  ## "fp" | "top" (UserSettings.VIEWS)
	get:
		return app.view

## A menu or help covers the view: Tab and F2 do nothing.
var blocked: bool:
	get:
		return app.blocked
	set(v):
		app.blocked = v

var telemetry: Telemetry:          ## the current run's telemetry, held for the run
	get:
		return app.telemetry

var logged_runs: int:              ## runs written to runs_dir so far
	get:
		return app.logged_runs


func _ready() -> void:
	app.load_settings()
	fp_view.controller = app.fp
	top_view.controller = app.top
	fp_view.set_render_scale(settings["render_scale"])
	fp_view.input_enabled = input_enabled
	top_view.input_enabled = input_enabled
	fp_view.new_run_requested.connect(func() -> void: new_run_requested.emit())
	top_view.new_run_requested.connect(func() -> void: new_run_requested.emit())
	top_view.acted.connect(_after_top_action)
	app.world_started.connect(_on_world_started)
	app.view_changed.connect(_on_view_changed)
	app.render_scale_requested.connect(cycle_render_scale)
	_show_view()


## The world being played, or null before start.
var world: World:
	get:
		return fp_view.world


## Show a new or loaded run in whichever view is current and start logging it.
func start(new_world: World) -> void:
	app.attach_world(new_world)


func _on_world_started(_w: World) -> void:
	fp_view.refresh(0.0)
	top_view.refresh()
	_show_view()


func _on_view_changed(v: String) -> void:
	_show_view()
	view_changed.emit(v)


## Show or hide the whole game screen (the title and creation screens cover it): hidden, neither view
## renders or updates.
func set_shown(on: bool) -> void:
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on:
		_show_view()
	else:
		fp_view.set_active(false)
		top_view.set_active(false)


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
	elif event.is_action_pressed(&"cycle_render_scale") and not (event as InputEventKey).echo and not blocked:
		cycle_render_scale()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	app.log_run_if_over()


## An action name from the keyboard (or a test), routed to the view that is showing. Tab and F2
## are handled by the AppState; everything else goes to that view's controller. Returns true when
## it was used.
func press(action: StringName) -> bool:
	return app.press(action)


## Tab: swap first-person and map and remember the choice. Menus swallow it and the end screens
## ignore it (Python). Returns true when the view changed.
func toggle_view() -> bool:
	return app.toggle_view()


## Show "fp" or "top" and remember it (no menu or end-screen checks: Tab does those).
func set_view(choice: String) -> void:
	app.set_view(choice)


## F2: Retro, Sharp, Full, Retro ... Remembered in the settings file.
func cycle_render_scale() -> String:
	var all := UserSettings.RENDER_SCALES
	var next: String = all[(all.find(fp_view.render_scale) + 1) % all.size()]
	set_render_scale(next)
	return next


## Choose the 3D resolution and remember it.
func set_render_scale(choice: String) -> void:
	fp_view.set_render_scale(choice)
	app.settings["render_scale"] = fp_view.render_scale
	app.save_settings()


## After any key used in the map view (real key events on a standalone GameView): what Python's
## handle_key does whatever the view, so a new floor is faced the open way from the arrival tile,
## whatever you do on the map before Tab back, then log the run if it ended.
func _after_top_action() -> void:
	fp_view.controller.after_action()
	app.log_run_if_over()


func _show_view() -> void:
	fp_view.set_active(view == "fp")
	top_view.set_active(view == "top")


## Write your finished run to runs_dir/player_*.csv once, for the analysis notebooks.
func log_run_if_over() -> void:
	app.log_run_if_over()

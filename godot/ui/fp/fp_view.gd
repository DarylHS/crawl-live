class_name FpView
extends Control
## The first-person 3D view (scenes/fp_view.tscn): the dungeon from the player's eyes.
##
## Scene tree:
##   FpView (Control, this script)
##     Viewport (SubViewport 320 x 200, its own 3D world)
##       Environment (WorldEnvironment: black background, dim ambient light, depth fog to LIGHT)
##       Level (Node3D: FloorMesh, rebuilt by FloorMeshBuilder when the floor changes)
##       Markers (FpMarkers: P4 placeholder sprites for monsters, pet, items, stairs, furniture)
##       Rig (FpCameraRig: Camera3D and the OmniLight3D torch)
##     Screen (TextureRect showing the viewport, scaled up with nearest filtering: hard pixels)
##     Flash (ColorRect: the red hurt flash)
##
## The rules never run here: input becomes InputMap action names for FpController, which calls
## World.move_player / wait / descend; this script only shows the result. `input_enabled` false
## lets a parent (P5-P7 menus, the screenshot tool) drive it instead.

signal new_run_requested           ## Enter pressed after the run ended (P7 replaces it with the end screens)

## Actions a press may mean, in the order App.handle_key tried them (">" before wait, first-person
## walks and turns before compass moves, so W walks rather than moving north).
const PRESS_ORDER: Array[StringName] = [&"descend", &"walk_forward", &"walk_back", &"strafe_left",
		&"strafe_right", &"turn_left", &"turn_right", &"move_n", &"move_s", &"move_e", &"move_w",
		&"move_ne", &"move_nw", &"move_se", &"move_sw", &"wait"]
## Actions read every frame while held (free look and walking).
const HELD_ACTIONS: Array[StringName] = [&"walk_forward", &"walk_back", &"strafe_left",
		&"strafe_right", &"turn_left", &"turn_right"]
const FLASH_ALPHA := 110.0 / 255.0   ## Python: red at alpha 110 times the flash strength

@onready var viewport: SubViewport = $Viewport
@onready var level: Node3D = $Viewport/Level
@onready var markers: FpMarkers = $Viewport/Markers
@onready var rig: FpCameraRig = $Viewport/Rig
@onready var screen: TextureRect = $Screen
@onready var flash_rect: ColorRect = $Flash

var controller := FpController.new()
var materials := FpMaterials.new()
var input_enabled: bool = true     ## read the keyboard (off for the screenshot tool and tests)
var hud: bool = true               ## false while a menu or end screen covers the view
var floor_mesh: MeshInstance3D = null
var build_ms: float = 0.0          ## time the last floor mesh took to build
var materials_ms: float = 0.0      ## time the last floor's textures took (0 when cached)
var _stairs_slot: int = -1
var _stairs_locked: bool = false


func _ready() -> void:
	screen.texture = viewport.get_texture()


## The world being shown, or null before start.
var world: World:
	get:
		return controller.world


## The camera maths (angle, glide, combat lock).
var logic: FpLogic:
	get:
		return controller.view


## Show a new or loaded run: face the most open way and snap the camera there.
func start(new_world: World) -> void:
	controller.start(new_world)
	refresh(0.0)


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or world == null:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if world.state != "playing":
		if event.is_action_pressed(&"descend"):
			new_run_requested.emit()
			get_viewport().set_input_as_handled()
		return
	var action := &""
	if key.unicode == 62:              # ">" on any layout
		action = &"descend"
	else:
		for a in PRESS_ORDER:
			if event.is_action_pressed(a):
				action = a
				break
	if action != &"" and controller.press(action):
		get_viewport().set_input_as_handled()


func _process(delta: float) -> void:
	if world == null:
		return
	if input_enabled:
		var held: Array[StringName] = []
		for a in HELD_ACTIONS:
			if Input.is_action_pressed(a):
				held.append(a)
		controller.update(delta, held)
	refresh(delta)


## Bring the 3D scene up to date with the world and the camera: rebuild the floor mesh on a new
## floor, place the eye, swap the stairs grate when the lock changes, sync the markers and fade
## the hurt flash. dt only fades the flash (the glide runs in FpController.update).
func refresh(dt: float) -> void:
	var w := world
	if w == null:
		return
	controller.view.follow_floor(w)
	controller.sync_combat()
	if logic.prepare_floor(w) or floor_mesh == null:
		_build_floor(w)
	if logic.cam.is_empty():
		logic.update_camera(w)          # snap, as Python's render does with no camera yet
	rig.follow(logic.cam)
	var locked := w.stairs_locked or w.exit_sealed
	if _stairs_slot >= 0 and locked != _stairs_locked:
		_set_stairs_material(w, locked)
	markers.sync(w)
	logic.note_hp(w, hud)
	flash_rect.color.a = FLASH_ALPHA * logic.flash if logic.flash > 0.02 else 0.0
	logic.fade_flash(dt)
	screen.modulate = Color.WHITE if hud else Color(0.65, 0.65, 0.65)


func _build_floor(w: World) -> void:
	if floor_mesh != null:
		level.remove_child(floor_mesh)
		floor_mesh.free()
	var t0 := Time.get_ticks_usec()
	var mats := materials.for_depth(w.depth)
	var t1 := Time.get_ticks_usec()
	floor_mesh = FloorMeshBuilder.build(w.floor, mats)
	build_ms = (Time.get_ticks_usec() - t1) / 1000.0
	materials_ms = (t1 - t0) / 1000.0
	level.add_child(floor_mesh)
	_stairs_slot = (floor_mesh.mesh as ArrayMesh).surface_find_by_name("stairs")
	_stairs_locked = false
	if _stairs_slot >= 0:
		_set_stairs_material(w, w.stairs_locked or w.exit_sealed)


func _set_stairs_material(w: World, locked: bool) -> void:
	_stairs_locked = locked
	var mats := materials.for_depth(w.depth)
	floor_mesh.set_surface_override_material(_stairs_slot, mats["stairs_locked"] if locked else null)


## The 320 x 200 frame as an Image (call after a frame has been drawn).
func capture() -> Image:
	return viewport.get_texture().get_image()

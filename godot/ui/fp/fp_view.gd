class_name FpView
extends Control
## The first-person 3D view (scenes/fp_view.tscn): the dungeon from the player's eyes.
##
## Scene tree:
##   FpView (Control, this script)
##     Viewport (SubViewport 320 x 200, its own 3D world)
##       Environment (WorldEnvironment: black background, dim ambient light, depth fog to LIGHT)
##       Level (Node3D: FloorMesh, rebuilt by FloorMeshBuilder when the floor changes)
##       Billboards (Billboards: sprites for monsters, pet, items, stairs, furniture)
##       Torches (WallTorches: flickering wall torches and embers, P8)
##       Particles (FxParticles: hit, kill, bomb and heal bursts, P8)
##       Rig (FpCameraRig: Camera3D and the OmniLight3D torch)
##     Screen (TextureRect showing the viewport; nearest filtering at Retro: hard pixels)
##     ViewModel (ViewModel: your hands and the equipped weapon, P8)
##     Fx (FxCanvas: floating damage numbers, P8)
##     Minimap (Minimap: the corner map and "Facing X", drawn at full resolution over the 3D)
##     Flash (ColorRect: the red hurt flash)
##
## Light: ambient 0.6 plus a torch of 0.4 with no distance attenuation, so a wall face-on at any
## range is lit at most about 1x its texture, as Python (which only ever darkens); the depth fog
## does the falloff to black at LIGHT, and the torch's angle to each face adds gentle shading.
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
## Render scale choices (Graphics setting): the 3D viewport's size. Retro is Python's 320 x 200 with hard
## pixels; Sharp doubles it; Full matches the on-screen size of this view. The camera, field of view and
## aspect do not change, only the resolution, and sprites are sized in world units, so they scale along.
const RENDER_SIZES := {"retro": Vector2i(320, 200), "sharp": Vector2i(640, 400)}
const FLASH_ALPHA := 110.0 / 255.0   ## Python: red at alpha 110 times the flash strength

@onready var viewport: SubViewport = $Viewport
@onready var level: Node3D = $Viewport/Level
@onready var billboards: Billboards = $Viewport/Billboards
@onready var rig: FpCameraRig = $Viewport/Rig
@onready var screen: TextureRect = $Screen
@onready var flash_rect: ColorRect = $Flash
@onready var minimap: Minimap = $Minimap
@onready var torches: WallTorches = $Viewport/Torches
@onready var particles: FxParticles = $Viewport/Particles
@onready var view_model: ViewModel = $ViewModel
@onready var fx_canvas: FxCanvas = $Fx

var controller := FpController.new()
var materials := FpMaterials.new()
var _art_gen: int = SpriteArt.generation   ## the SpriteArt.generation the pictures were made from
var input_enabled: bool = true     ## read the keyboard (off for the screenshot tool and tests)
var hud: bool = true               ## false while a menu or end screen covers the view
var floor_mesh: MeshInstance3D = null
var build_ms: float = 0.0          ## time the last floor mesh took to build
var materials_ms: float = 0.0      ## time the last floor's textures took (0 when cached)
var render_scale: String = "retro"   ## "retro" | "sharp" | "full" (UserSettings.RENDER_SCALES)
var active: bool = true            ## false while the map view is showing (nothing renders or updates)
## The effects state (P8) FxDirector fills and this view shows: shake, flicker, bob, flashes, numbers,
## slides, the weapon swing. Null (standalone views and most tests) draws the plain P4 to P7 view.
var fx: FxState = null:
	set(v):
		fx = v
		billboards.fx = v
		fx_canvas.fx = v
		view_model.fx = v
var show_view_model: bool = true   ## false hides the weapon (the pygame side-by-side tools: pygame has no view model)
var walked: float = 0.0            ## tiles the camera has travelled (drives the walking bob)
var moving: float = 0.0            ## 0 to 1: the camera is moving now
var _prev_cam: Array = []
var _stairs_slot: int = -1
var _stairs_locked: bool = false


func _ready() -> void:
	screen.texture = viewport.get_texture()
	resized.connect(_apply_render_scale)
	_apply_render_scale()


## Choose the 3D resolution: "retro", "sharp" or "full" (anything else counts as retro).
func set_render_scale(choice: String) -> void:
	render_scale = choice if UserSettings.RENDER_SCALES.has(choice) else "retro"
	_apply_render_scale()


## The 3D viewport's size for the current render scale.
func viewport_size() -> Vector2i:
	if render_scale == "full":
		return Vector2i(maxi(1, int(size.x)), maxi(1, int(size.y)))
	return RENDER_SIZES[render_scale]


func _apply_render_scale() -> void:
	if viewport == null:
		return
	viewport.size = viewport_size()
	screen.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST if render_scale == "retro" \
			else CanvasItem.TEXTURE_FILTER_LINEAR


## Show or hide the whole view. Hidden, the 3D stops rendering and the world is left alone; shown
## again, the camera snaps to you with no stale hurt flash (Python's toggle_view / reset_camera).
func set_active(on: bool) -> void:
	if on == active:
		return
	active = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if on:
		logic.reset_camera()
		if world != null:
			controller.sync_combat()
			refresh(0.0)


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
## floor, place the eye, swap the stairs grate when the lock changes, sync the billboards and fade
## the hurt flash. dt only fades the flash (the glide runs in FpController.update).
func refresh(dt: float) -> void:
	var w := world
	if w == null:
		return
	controller.view.follow_floor(w)
	controller.sync_combat()
	var art_changed := _art_gen != SpriteArt.generation       # another art set: rebuild every picture
	if art_changed:
		_art_gen = SpriteArt.generation
		billboards.forget_textures()
		torches.forget_textures()
		view_model.forget_textures()
	if logic.prepare_floor(w) or floor_mesh == null or art_changed:
		_build_floor(w)
	if logic.cam.is_empty():
		logic.update_camera(w)          # snap, as Python's render does with no camera yet
	rig.follow(logic.cam)
	var locked := w.stairs_locked or w.exit_sealed
	if _stairs_slot >= 0 and locked != _stairs_locked:
		_set_stairs_material(w, locked)
	billboards.sync(w, logic.cam)
	torches.sync(w, logic.cam, fx)
	minimap.visible = hud
	if hud:
		minimap.update_from(w, logic.angle, logic.compass())
	logic.note_hp(w, hud)
	var flash_scale := float(fx.profile["flash"]) if fx != null else 1.0   # "off" and "reduced" soften the hurt flash
	flash_rect.color.a = FLASH_ALPHA * logic.flash * flash_scale if logic.flash > 0.02 else 0.0
	logic.fade_flash(dt)
	screen.modulate = Color.WHITE if hud else Color(0.65, 0.65, 0.65)
	_apply_fx(w, dt)


## Show the effects state: the torch flicker, the camera shake and walking bob, and the weapon view model.
## Nothing here reads or changes the rules beyond which weapon is equipped.
func _apply_fx(w: World, dt: float) -> void:
	var cam := logic.cam
	if dt > 0.0 and not cam.is_empty():
		var d := 0.0
		if not _prev_cam.is_empty():
			d = Vector2(cam[0] - _prev_cam[0], cam[1] - _prev_cam[1]).length()
			if d < 1.5:
				walked += d
		moving = 1.0 if d > 0.0004 else maxf(0.0, moving - dt * 6.0)
		_prev_cam = cam.duplicate()
	var wkey: Variant = w.equipment["weapon"]
	view_model.set_weapon(String(wkey) if PyMath.truthy(wkey) else "", w.weapon_style())
	view_model.walked = walked
	view_model.moving = moving
	view_model.dim = not hud
	view_model.visible = show_view_model and w.state == "playing"
	if fx == null:
		return
	var prof := fx.profile
	rig.set_flicker(fx.time, float(prof["flicker"]))
	var bob := float(prof["bob"]) * moving
	rig.set_camera_fx(fx.shake_offset(), 0.012 * sin(walked * TAU) * bob, 0.5 * sin(walked * PI) * bob)


## A short orange flash of light at a world point (a bomb going off): an OmniLight3D whose energy a
## Tween fades out. A Tween is Godot's built-in animator for a property: `tween_property(node, "x", to,
## seconds)` runs it over time from the main loop, and `kill()` stops it. Visual only.
func bomb_light(pos: Vector3, strength: float = 1.0) -> void:
	var light := OmniLight3D.new()
	light.light_color = Color(1.0, 0.7, 0.35)
	light.light_energy = 3.0 * strength
	light.omni_range = 4.0
	light.shadow_enabled = false
	viewport.add_child(light)
	light.position = pos + Vector3(0.0, 0.3, 0.0)
	var tween := create_tween()
	tween.tween_property(light, "light_energy", 0.0, 0.35)
	tween.tween_callback(light.queue_free)


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


## Screen rectangles (in this view's coordinates, 1024 x 640 at full size) of your pet and the monsters
## in sight, from Camera3D.unproject_position: a sprite stands on its tile and is as wide as it is
## tall. The HUD keeps the initiative tracker clear of them (port plan 10.3).
func actor_rects() -> Array:
	var out: Array = []
	var w := world
	if w == null or rig.camera == null:
		return out
	var cam := rig.camera
	var vp_size := Vector2(viewport.size)
	var to_view := (size if size.x > 0.0 else Vector2(1024, 640)) / vp_size
	for spec: Dictionary in billboards.specs(w):
		var pet_tile: bool = w.active_pet != null and spec["tile"] == Vector2i(w.active_pet.x, w.active_pet.y)
		if not spec.has("monster") and not pet_tile:
			continue
		var tile: Vector2i = spec["tile"]
		var height: float = float(spec["scale"]) * FloorMeshBuilder.WALL_H
		var foot := Vector3(tile.x + 0.5, 0.0, tile.y + 0.5)
		var head := foot + Vector3(0.0, height, 0.0)
		if cam.is_position_behind(foot):
			continue
		var a := cam.unproject_position(foot) * to_view
		var b := cam.unproject_position(head) * to_view
		var h := absf(a.y - b.y)
		out.append(Rect2i(Vector2i(int(a.x - h / 2.0), int(minf(a.y, b.y))), Vector2i(int(h), int(h))))
	return out


## The 320 x 200 frame as an Image (call after a frame has been drawn).
func capture() -> Image:
	return viewport.get_texture().get_image()

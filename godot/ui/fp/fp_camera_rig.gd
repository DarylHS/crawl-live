class_name FpCameraRig
extends Node3D
## The first-person eye: a Camera3D and the torch (an OmniLight3D) that move together.
##
## FpView runs the camera maths (FpController and FpLogic, headless) each frame and hands the
## result to `follow`, which places this node at the player's eye: tile (x, y) centre is world
## (x, EYE_HEIGHT, y), and FpLogic's raycaster angle `a` (0 east, clockwise in tile space) becomes
## a yaw about the Y axis (Godot looks down -Z at yaw 0, which is north here).
##
## Port plan 10.1: eye at half the 0.875-tile wall, 70 degree horizontal field of view (2 atan(PLANE)), the
## torch reaching LIGHT = FOV_RADIUS + 0.5 tiles, where the WorldEnvironment fog turns to black.

const EYE_HEIGHT := FloorMeshBuilder.WALL_H / 2.0   ## 0.4375 tiles: half the wall
const TORCH_ENERGY := 0.4                           ## the steady torch light (fp_view.tscn)
const FLICKER_DIP := 0.3                            ## at full flicker the light dips up to this share (never brighter)
const SHAKE_YAW := 1.2                              ## degrees of camera yaw at full shake
const SHAKE_PITCH := 0.9
const SHAKE_ROLL := 0.8

@onready var camera: Camera3D = $Camera
@onready var torch: OmniLight3D = $Torch


func _ready() -> void:
	camera.keep_aspect = Camera3D.KEEP_WIDTH          # `fov` is the horizontal angle
	camera.fov = rad_to_deg(2.0 * atan(FpLogic.PLANE))
	camera.near = 0.05
	camera.far = FpLogic.LIGHT + 1.5
	torch.omni_range = FpLogic.LIGHT


## Place the eye at FpLogic's cam ([x, y, a] in tiles and raycaster radians).
func follow(cam: Array) -> void:
	if cam.is_empty():
		return
	position = Vector3(cam[0], EYE_HEIGHT, cam[1])
	rotation = Vector3(0.0, -(float(cam[2]) + PI / 2.0), 0.0)


## The world point straight ahead of the eye at `dist` tiles (tests use it to check the yaw).
func ahead(dist: float) -> Vector3:
	return global_position - global_transform.basis.z * dist


## The torch flicker at time `t` seconds, 0 (dimmest) to 1 (steady): three sines that never repeat in
## a way you notice. Deterministic: the game's RNG is not involved.
static func flicker_value(t: float) -> float:
	var n := 0.5 * sin(t * 9.1) + 0.3 * sin(t * 17.3 + 1.7) + 0.2 * sin(t * 31.7 + 0.4)   # -1 to 1
	return 0.5 + 0.5 * n


## Flicker the torch: `amount` 0 (steady, the P4 look) to 1 (full). The light only ever dips below its
## steady level, so walls never come out brighter than their texture, as the P4 lighting rule asks.
func set_flicker(t: float, amount: float) -> void:
	var dip := FLICKER_DIP * amount * (1.0 - flicker_value(t))
	torch.light_energy = TORCH_ENERGY * (1.0 - dip)


## Move and turn the camera on top of the eye: `shake` (x, y in -1 to 1, times the strength already),
## and a walking bob (`bob_y` in tiles, `roll` in degrees). All zero leaves the view exactly as it was.
func set_camera_fx(shake: Vector2, bob_y: float, roll: float) -> void:
	camera.position = Vector3(0.0, bob_y, 0.0)
	camera.rotation_degrees = Vector3(shake.y * SHAKE_PITCH, shake.x * SHAKE_YAW, roll + shake.x * SHAKE_ROLL)

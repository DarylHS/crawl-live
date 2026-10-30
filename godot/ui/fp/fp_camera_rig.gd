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

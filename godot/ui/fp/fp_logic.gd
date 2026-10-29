class_name FpLogic
extends RefCounted
## First-person camera maths (crawler/ui/firstperson.py `FirstPersonView`, minus the drawing).
##
## Headless: no Node, no rendering, so tests/ui/test_fp_logic.gd runs it like the pytest tests.
## You look at a free angle in degrees (0 north, 90 east, clockwise); each step goes to the nearest
## of the 8 neighbouring tiles (`step_for_angle`). `cam` is the point the 3D camera shows:
## [x, y, a] in tile units with `a` the raycaster angle in radians (radians(angle) - pi / 2,
## 0 pointing east, as Python), or [] before the first update (Python's None). It glides towards
## the player's tile centre and look angle at WALK_SPEED and TURN_SPEED. FpCameraRig turns it into
## a Camera3D transform.
##
## Python maths kept exactly: `round(angle / 45) % 8` uses PyMath.round_half_even and PyMath.mod,
## `%` on floats uses PyMath.fmod_py, and cam is an Array of 64-bit floats (a Vector3 would be 32-bit).

const DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]
## N, NE, E, SE, S, SW, W, NW (index = round(angle / 45) % 8).
const DIRS8: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, -1), Vector2i(1, 0), Vector2i(1, 1),
		Vector2i(0, 1), Vector2i(-1, 1), Vector2i(-1, 0), Vector2i(-1, -1)]
const COMPASS8: Array[String] = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
const TURN_SPEED := TAU                ## radians a second the camera turns to catch up with the angle
const RELATIVE := {"forward": 0, "back": 180, "left": -90, "right": 90}

static var _cfg: Dictionary = Content.table("ui_config")["firstperson"]
static var LIGHT: float = _cfg["LIGHT"]               ## tiles: everything fades to black here (FOV_RADIUS + 0.5)
static var PLANE: float = _cfg["PLANE"]               ## camera plane: about a 70 degree horizontal FOV
static var SETTLE: float = _cfg["SETTLE"]             ## tiles / radians: a glide this close just lands
static var WALK_SPEED: float = _cfg["WALK_SPEED"]     ## tiles a second the camera glides along a step
static var DEPTH_TINT: Array = _cfg["DEPTH_TINT"]     ## [r, g, b] per floor, floors 1-6

var angle: float = 90.0                ## where you look, degrees: 0 north, 90 east
var grid: bool = false                 ## combat: 90 degree turns and grid steps only
var cam: Array = []                    ## [x, y, a] gliding towards the player, [] = not placed yet
var flash: float = 0.0                 ## hurt flash strength, 1 on a real hit, fades out
var _floor: DungeonFloor = null        ## the floor the camera was placed on
var _faced_floor: DungeonFloor = null  ## the floor face_open last turned you for
var _last_hp: int = -1                 ## HP missing at the last note_hp, -1 = none yet


# --- Pure helpers ---------------------------------------------------------------

## The tile step nearest to a look angle in degrees (0 north, 90 east).
static func step_for_angle(a: float) -> Vector2i:
	return DIRS8[PyMath.mod(PyMath.round_half_even(a / 45.0), 8)]


## The shortest turn from angle b to angle a, in degrees (-180 to 180).
static func angle_gap(a: float, b: float) -> float:
	return PyMath.fmod_py(a - b + 180.0, 360.0) - 180.0


## The facing (0-3) with the longest straight run of walkable tiles from (x, y), so a new floor
## doesn't start you nose to a wall. Ties keep `prefer`, then go N, E, S, W. `floor` is anything
## with walkable(x, y) (a DungeonFloor, or a stand-in in tests).
static func open_facing(floor: Object, x: int, y: int, prefer: int = 1) -> int:
	var order: Array[int] = [prefer]
	for d in 4:
		if d != prefer:
			order.append(d)
	var best := prefer
	var best_run := -1
	for d in order:
		var step := DIRS[d]
		var n := 0
		while floor.walkable(x + step.x * (n + 1), y + step.y * (n + 1)):
			n += 1
		if n > best_run:
			best = d
			best_run = n
	return best


## The per-floor tint as a Color (floors past 6 wrap round, as Python's `(depth - 1) % 6`).
static func depth_tint(depth: int) -> Color:
	var t: Array = DEPTH_TINT[PyMath.mod(depth - 1, DEPTH_TINT.size())]
	return Color(t[0], t[1], t[2])


# --- Facing and turning -----------------------------------------------------------

## The nearest of the four directions (0 north, 1 east, 2 south, 3 west); setting it looks that way.
var facing: int:
	get:
		return PyMath.mod(PyMath.round_half_even(angle / 90.0), 4)
	set(d):
		angle = PyMath.mod(d, 4) * 90.0


## Turn 90 degrees per step (positive is clockwise).
func turn(step: int) -> void:
	angle = PyMath.fmod_py(angle + 90.0 * step, 360.0)


## A tapped turn key: on to the next 45 degree line that way (45 degrees from one).
func tap_turn(sign_value: int) -> void:
	var a := angle / 45.0
	var k: int = int(floor(a + 1e-6)) + 1 if sign_value > 0 else int(ceil(a - 1e-6)) - 1
	angle = PyMath.fmod_py(k * 45.0, 360.0)


## Combat locks the view to the grid: the angle settles on the nearest of the four directions (the
## camera glides there). Afterwards free look resumes from that angle.
func set_combat(on: bool) -> void:
	grid = on
	if on:
		angle = PyMath.fmod_py(PyMath.round_half_even(angle / 90.0) * 90.0, 360.0)


## Free look: turn by any amount (held turn keys).
func look(degrees: float) -> void:
	angle = PyMath.fmod_py(angle + degrees, 360.0)


## The nearest of the 8 compass points to where you look.
func compass() -> String:
	return COMPASS8[PyMath.mod(PyMath.round_half_even(angle / 45.0), 8)]


# --- Movement helpers (the rules only ever see move_player(dx, dy)) --------------------

## The step W takes: the nearest of the 8 directions to the look angle.
func forward() -> Vector2i:
	return step_for_angle(angle)


## "forward" / "back" / "left" / "right" as a world step for where you look: forward is the nearest
## of the 8 directions, back its opposite, left and right 90 degrees either side.
func relative(move: String) -> Vector2i:
	return step_for_angle(PyMath.round_half_even(angle / 45.0) * 45 + int(RELATIVE[move]))


## The monster this step would attack and the step: the tile straight ahead, else the neighbouring
## tile 45 degrees either side of it, the one nearer your look angle first. [null, null] if none.
func target_ahead(world: World) -> Array:
	var p := world.player
	var ahead: int = PyMath.round_half_even(angle / 45.0) * 45
	var sides: Array = [ahead - 45, ahead + 45]
	if absf(angle_gap(ahead + 45, angle)) < absf(angle_gap(ahead - 45, angle)):
		sides = [ahead + 45, ahead - 45]       # Python's stable sort by the gap
	var at := {}
	for m in world.monsters:                   # a dict comprehension: the last one on a tile wins
		at[Vector2i(m.x, m.y)] = m
	for a in [ahead, sides[0], sides[1]]:
		var d := step_for_angle(a)
		var tile := Vector2i(p.x + d.x, p.y + d.y)
		if at.has(tile):
			return [at[tile], d]
	return [null, null]


# --- Runs and floors ---------------------------------------------------------------

## Forget the camera and the HP it last saw: the next update snaps, with no stale hurt flash.
func reset_camera() -> void:
	cam = []
	_last_hp = -1
	flash = 0.0


## A new run or a loaded one: fresh camera, facing down the longest open line.
func reset(world: World) -> void:
	reset_camera()
	_floor = null
	face_open(world)


## Face the most open direction from the player's tile.
func face_open(world: World) -> void:
	var p := world.player
	facing = open_facing(world.floor, p.x, p.y, facing)
	_faced_floor = world.floor
	cam = []


## On arriving on a new floor, face the most open direction.
func follow_floor(world: World) -> void:
	if _faced_floor != world.floor:
		face_open(world)


## The view's per-floor setup (Python `_prepare_floor`): true when world.floor is new to the
## camera, which then snaps (the scene rebuilds its floor mesh on true).
func prepare_floor(world: World) -> bool:
	if _floor == world.floor:
		return false
	_floor = world.floor
	cam = []
	return true


# --- Camera glide --------------------------------------------------------------------

## Where the camera wants to be: the player's tile centre and look angle.
func cam_target(world: World) -> Array:
	var p := world.player
	return [p.x + 0.5, p.y + 0.5, deg_to_rad(angle) - PI / 2]


## How far the camera still has to go: [dx, dy, shortest turn in radians].
func cam_gap(target: Array) -> Array:
	var da: float = PyMath.fmod_py(target[2] - cam[2] + PI, TAU) - PI
	return [target[0] - cam[0], target[1] - cam[1], da]


## Glide the camera towards the player's tile centre and look angle at a steady speed. dt is
## seconds; dt >= 1 snaps, and so does a jump of more than 2.5 tiles (a new floor, a load).
func update_camera(world: World, dt: float = 1.0) -> void:
	var target := cam_target(world)
	if cam.is_empty() or dt >= 1:
		cam = target
		return
	var gap := cam_gap(target)
	var gx: float = gap[0]
	var gy: float = gap[1]
	var ga: float = gap[2]
	var dist := sqrt(gx * gx + gy * gy)
	if dist > 2.5:
		cam = target
		return
	if maxf(dist, absf(ga)) < SETTLE:
		cam = target                           # close enough: land exactly, so the glide ends
		return
	var k := minf(1.0, WALK_SPEED * dt / dist) if dist != 0.0 else 0.0
	var da := clampf(ga, -TURN_SPEED * dt, TURN_SPEED * dt)
	cam = [cam[0] + gx * k, cam[1] + gy * k, cam[2] + da]


## Tiles the camera still has to travel to reach your tile centre (0 when there).
func glide_left(world: World) -> float:
	if cam.is_empty():
		return 0.0
	var gap := cam_gap(cam_target(world))
	return sqrt(gap[0] * gap[0] + gap[1] * gap[1])


## True while the camera glides or the hurt flash fades: keep redrawing until then.
func animating(world: World) -> bool:
	if flash > 0.02:
		return true
	if cam.is_empty() or _floor != world.floor:
		return false
	var gap := cam_gap(cam_target(world))
	return gap[0] != 0.0 or gap[1] != 0.0 or gap[2] != 0.0


# --- Hurt flash ------------------------------------------------------------------------

## Note the player's HP once per drawn frame: the flash fires only when the HP deficit grows
## (real damage, not a lower max HP). `hud` false (a menu covers the view) clears it.
func note_hp(world: World, hud: bool = true) -> void:
	var p := world.player
	var missing := p.max_hp - p.hp
	if _last_hp >= 0 and missing > _last_hp:
		flash = 1.0
	_last_hp = missing
	if not hud:
		flash = 0.0


## Fade the flash: Python multiplies it by 0.8 per frame at 30 frames a second.
func fade_flash(dt: float) -> void:
	flash *= pow(0.8, dt * 30.0)

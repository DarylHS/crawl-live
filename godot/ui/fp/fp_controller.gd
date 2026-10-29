class_name FpController
extends RefCounted
## First-person input in play (the first-person parts of crawler/game.py `App`): key presses,
## held keys (free look and walking) and the combat grid lock, on top of FpLogic.
##
## Headless like FpLogic: FpView feeds it InputMap action names, and tests feed it the same names
## with a held set, as the pytest tests pass `held={pygame.K_w}`. P7's AppState can own one of
## these for the "game" scene.
##
## Presses (`press`) act at once: a walk key steps (or bumps what target_ahead picks), a turn key
## turns 45 degrees (90 in combat). Held keys (`update`): after HOLD_DELAY a turn key looks round
## at TURN_RATE; a walk key takes the next step when the glide has under NEXT_STEP tiles left and
## STEP_GAP seconds have passed, and stops after a blocked step or an attack until it is let go.
## In combat (`view.grid`) held keys do nothing: one step or quarter turn per press.

## Walk actions and the move they make relative to the view (Python FP_STEPS).
const STEPS := {&"walk_forward": "forward", &"walk_back": "back", &"strafe_left": "left",
		&"strafe_right": "right"}
## Turn actions and their direction (Python FP_TURNS).
const TURNS := {&"turn_left": -1, &"turn_right": 1}
## Absolute moves (numpad) that keep their compass meaning in first-person (Python MOVES).
const MOVES := {&"move_n": Vector2i(0, -1), &"move_s": Vector2i(0, 1), &"move_e": Vector2i(1, 0),
		&"move_w": Vector2i(-1, 0), &"move_ne": Vector2i(1, -1), &"move_nw": Vector2i(-1, -1),
		&"move_se": Vector2i(1, 1), &"move_sw": Vector2i(-1, 1)}

static var _cfg: Dictionary = Content.table("ui_config")["input"]
static var TURN_RATE: float = _cfg["TURN_RATE"]     ## degrees a second while a turn key is held
static var HOLD_DELAY: float = _cfg["HOLD_DELAY"]   ## seconds before a held turn key starts free look
static var NEXT_STEP: float = _cfg["NEXT_STEP"]     ## glide left (tiles) when a held walk steps again
static var STEP_GAP: float = _cfg["STEP_GAP"]       ## seconds between held steps at least
static var MAX_DT: float = _cfg["MAX_DT"]           ## a slow frame counts as this at most

var world: World = null
var view := FpLogic.new()
var blocked: bool = false        ## a menu or help covers the view (P7): held keys do nothing
var held: Dictionary = {}        ## action -> true for actions held right now (insertion order)
var _held_for: Dictionary = {}   ## action -> seconds it has been held
var _walk_wait: float = 0.0      ## seconds until a held walk key may step again
var _walk_stopped: Dictionary = {}   ## walk actions that bumped a wall or attacked: wait for release


## A new or loaded run: face the most open way with a fresh camera and forget held keys.
func start(new_world: World) -> void:
	world = new_world
	view.reset(world)
	held = {}
	_held_for = {}
	_walk_wait = 0.0
	_walk_stopped = {}


## True while held keys drive the view (Python `_fp_input_live`).
func live() -> bool:
	return world != null and world.state == "playing" and not blocked


## A key press in play, as an action name. Returns true when the action was a game action this
## controller handled (descend, wait, a numpad move, or a first-person walk or turn).
func press(action: StringName) -> bool:
	if world == null:
		return false
	if world.state != "playing":
		return false
	var handled := true
	if action == &"descend":
		world.descend()
	elif STEPS.has(action) or TURNS.has(action):
		var res := move_first_person(action)
		_walk_stopped.erase(action)
		if not res[0] or res[1]:
			_walk_stopped[action] = true          # holding on doesn't keep bumping or attacking
	elif MOVES.has(action):
		var d: Vector2i = MOVES[action]
		world.move_player(d.x, d.y)
	elif action == &"wait":
		world.wait()
	else:
		handled = false
	after_action()
	return handled


## W attacks what target_ahead picks (ahead, else 45 degrees either side); a tapped turn key turns
## 45 degrees (90 in combat), for free. Returns [moved, attacked].
func move_first_person(action: StringName) -> Array:
	if TURNS.has(action):
		if view.grid:
			view.turn(TURNS[action])               # combat: a quarter turn per press
		else:
			view.tap_turn(TURNS[action])
		return [false, false]
	var move: String = STEPS[action]
	var target: Variant = null
	var step: Variant = null
	if move == "forward":
		var ahead := view.target_ahead(world)
		target = ahead[0]
		step = ahead[1]
	if target == null:                            # any step (back, strafe) into a monster is a bump
		step = view.relative(move)
		target = world.monster_at(world.player.x + step.x, world.player.y + step.y)
	var ok := world.move_player(step.x, step.y)
	_walk_wait = STEP_GAP
	return [ok, target != null]


## Lock the view to the grid when a fight starts (and stop any held walk, so it can't spend your
## combat move before you've seen the tracker); free it after.
func sync_combat() -> void:
	var fight := world != null and world.combat != null and world.state == "playing"
	if fight and not view.grid:
		view.set_combat(true)
		for k in held:
			if STEPS.has(k):
				_walk_stopped[k] = true
	elif not fight and view.grid:
		view.set_combat(false)


## After any key or held step: face a new floor's open side and sync the combat lock. (Python also
## logs a finished run and opens the class picker or a contract offer here: P7.)
func after_action() -> void:
	if world == null:
		return
	view.follow_floor(world)
	sync_combat()


## Per-frame work: free look and walking while keys are held, then the camera glide. dt is
## seconds (capped at MAX_DT); `held_now` (Array or Dictionary of action names) replaces the held
## set when given. Returns true when something changed that needs a redraw.
func update(dt: float, held_now: Variant = null) -> bool:
	dt = minf(dt, MAX_DT)
	if held_now != null:
		held = {}
		for k in held_now:
			held[StringName(k)] = true
	for k in _held_for.keys():
		if not held.has(k):
			_held_for.erase(k)
	for k in _walk_stopped.keys():
		if not held.has(k):
			_walk_stopped.erase(k)
	_walk_wait = maxf(0.0, _walk_wait - dt)
	if world == null:
		return false
	sync_combat()
	if not live():
		_held_for.clear()
		view.update_camera(world, dt)             # a menu or death mid-glide still lands on the tile
		return view.animating(world)
	if view.grid:                                 # combat: keys act on press only
		view.update_camera(world, dt)
		return view.animating(world)
	var changed := false
	for k in held:
		_held_for[k] = float(_held_for.get(k, 0.0)) + dt
	var spin := 0
	for k in held:
		if TURNS.has(k) and _held_for[k] > HOLD_DELAY:
			spin += int(TURNS[k])
	if spin != 0:
		view.look(clampi(spin, -1, 1) * TURN_RATE * dt)
		changed = true
	var walk: Array = []
	for k in held:
		if STEPS.has(k) and not _walk_stopped.has(k):
			walk.append(k)
	view.update_camera(world, dt)
	if not walk.is_empty() and _walk_wait <= 0 and view.glide_left(world) < NEXT_STEP:
		var key: StringName = walk[0]             # the latest pressed: held the shortest time
		for k in walk:
			if float(_held_for.get(k, 0.0)) < float(_held_for.get(key, 0.0)):
				key = k
		var res := move_first_person(key)
		if not res[0] or res[1]:
			_walk_stopped[key] = true            # a wall or a fight: stop until you let go
		after_action()
		changed = true
	return changed or view.animating(world)


## Seconds an action has been held (tests read it as Python reads `_held_for`).
func held_for(action: StringName) -> float:
	return float(_held_for.get(action, 0.0))

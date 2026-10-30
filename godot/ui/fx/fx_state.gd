class_name FxState
extends RefCounted
## What every running effect looks like right now: screen shake, sprite flashes, floating numbers,
## sprite slides between tiles, the weapon swing and sounds waiting on a delay. Headless (no nodes),
## so the timing and the skip rules are tested without a window; FxDirector feeds it effects from
## FxPlan, advances it with the frame time, and the views (FpView, Billboards, FxCanvas, ViewModel)
## only read it.
##
## Skipping (the brief's "turn-based input never waits on an animation"): effects are wall-clock
## decoration that nothing waits for. `on_key()` is called at the start of every key press, before
## the key is handled: it finishes the shake, flashes, slides and swing at once (the sprite is simply
## where it will be, the camera is still) and drops delayed sounds. Floating numbers keep drifting
## (they are information, and a fight is one key press per action), and a long run of key presses
## can never queue effects up: each kind has a cap.

const MAX_NUMBERS := 8
const SLIDE_DUR := 0.14           ## seconds a monster takes to slide to its new tile
const SHAKE_MAX := 1.0            ## amplitudes add up but never past this
const RISE_PX := 54.0             ## how far a floating number climbs (full-size view pixels)
const MAX_SLIDE_TILES := 2.0      ## a bigger jump (a teleport, a new floor) just snaps

var mode: String = "on"
var profile: Dictionary = FxSettings.profile("on")
var time: float = 0.0             ## seconds since the director started (drives flicker and bob)

var _shake_amp: float = 0.0
var _shake_t: float = 0.0
var _shake_dur: float = 0.0
var _flashes: Dictionary = {}     ## actor id -> [age, dur, strength]
var _slides: Dictionary = {}      ## actor id -> [age, from (Vector2 tiles)]
var _last_tile: Dictionary = {}   ## actor id -> Vector2i, for noticing moves
var _swing_t: float = -1.0        ## seconds into the swing, -1 when idle
var _swing_style: String = "unarmed"
var _delayed: Array = []          ## [[seconds left, sound name]]
var numbers: Array[Dictionary] = []   ## {text, tone, pos (Vector2), age, dur, rise (px offset stacking)}


## Choose the effects level ("on", "reduced", "off"). Going to off clears everything running.
func set_mode(new_mode: String) -> void:
	mode = new_mode if FxSettings.MODES.has(new_mode) else "on"
	profile = FxSettings.profile(mode)
	if mode == "off":
		finish()
		numbers.clear()


# --- Adding effects ---------------------------------------------------------------------------

## Shake the screen: amplitudes add up (clamped to SHAKE_MAX); a longer one extends the time left.
func kick(amp: float, dur: float) -> void:
	if float(profile["shake"]) <= 0.0:
		return
	var left := maxf(0.0, _shake_dur - _shake_t)
	_shake_amp = minf(SHAKE_MAX, _shake_amp * (left / maxf(_shake_dur, 0.001)) + amp)
	_shake_dur = maxf(dur, left)
	_shake_t = 0.0


## Flash an actor's sprite (a monster or the pet, by instance id).
func flash(id: int, strength: float, dur: float) -> void:
	if float(profile["flash"]) <= 0.0:
		return
	_flashes[id] = [0.0, dur, strength]


## A floating number at a screen position (in the view's pixels). Numbers at the same spot stack upward.
func add_number(text: String, tone: String, pos: Vector2, dur: float) -> void:
	if not profile["numbers"]:
		return
	var stack := 0.0
	for n in numbers:
		if (n["pos"] as Vector2).distance_to(pos) < 40.0 and float(n["age"]) < 0.5:
			stack += 22.0
	numbers.append({"text": text, "tone": tone, "pos": pos, "age": 0.0, "dur": dur, "stack": stack})
	while numbers.size() > MAX_NUMBERS:
		numbers.pop_front()


## Start the weapon swing for a weapon style ("blade", "blunt", "unarmed"); a new swing restarts it.
func start_swing(style: String) -> void:
	if not profile["swing"]:
		return
	_swing_style = style
	_swing_t = 0.0


## Play `sound_name` after `delay` seconds (dropped by `on_key`).
func delay_sound(sound_name: String, delay: float) -> void:
	_delayed.append([delay, sound_name])


## Tell the state where an actor stands (called by Billboards for every sprite it places). When an
## actor has moved one or two tiles since last time it starts a slide from the old tile.
func track_actor(id: int, tile: Vector2i) -> void:
	if _last_tile.has(id):
		var old: Vector2i = _last_tile[id]
		if old != tile and profile["slides"]:
			var from := Vector2(old - tile)
			if from.length() <= MAX_SLIDE_TILES:
				# a move in the middle of a slide continues from where the sprite is drawn now
				_slides[id] = [0.0, from + slide_offset(id)]
	_last_tile[id] = tile


## Forget where actors were (a new floor or a new run): nothing slides across the change.
func forget_actors() -> void:
	_last_tile.clear()
	_slides.clear()
	_flashes.clear()


# --- Reading them -----------------------------------------------------------------------------

## Shake offset for this frame, in units of "amp": x and y in -amp..amp, a fast deterministic wobble
## that decays to nothing by the end. (0, 0) when idle.
func shake_offset() -> Vector2:
	if _shake_dur <= 0.0 or _shake_t >= _shake_dur:
		return Vector2.ZERO
	var k := 1.0 - _shake_t / _shake_dur
	var amp := _shake_amp * k * k
	return Vector2(sin(_shake_t * 83.0), sin(_shake_t * 61.0 + 1.9)) * amp


func shaking() -> bool:
	return _shake_dur > 0.0 and _shake_t < _shake_dur


## White flash strength (0 to 1) of an actor's sprite: strongest at the start, linear fade.
func flash_of(id: int) -> float:
	if not _flashes.has(id):
		return 0.0
	var f: Array = _flashes[id]
	return clampf(1.0 - float(f[0]) / float(f[1]), 0.0, 1.0) * float(f[2])


## How far from its tile a sliding actor is drawn, in tiles (x, then the floor's y), easing to 0.
func slide_offset(id: int) -> Vector2:
	if not _slides.has(id):
		return Vector2.ZERO
	var s: Array = _slides[id]
	var k := clampf(float(s[0]) / SLIDE_DUR, 0.0, 1.0)
	return (s[1] as Vector2) * (1.0 - k * k * (3.0 - 2.0 * k))     # smoothstep


## Swing progress 0 to 1, or -1 when the weapon is idle.
func swing_progress() -> float:
	if _swing_t < 0.0:
		return -1.0
	return clampf(_swing_t / ViewModelPose.duration(_swing_style), 0.0, 1.0)


func swing_style() -> String:
	return _swing_style


## A number's drawn position (it climbs RISE_PX with an ease-out) and its opacity (full, then fading
## over the last 40%).
static func number_pos(n: Dictionary) -> Vector2:
	var k := clampf(float(n["age"]) / float(n["dur"]), 0.0, 1.0)
	var up := RISE_PX * (1.0 - (1.0 - k) * (1.0 - k)) + float(n["stack"])
	return (n["pos"] as Vector2) - Vector2(0.0, up)


static func number_alpha(n: Dictionary) -> float:
	var k := clampf(float(n["age"]) / float(n["dur"]), 0.0, 1.0)
	return 1.0 if k < 0.6 else clampf((1.0 - k) / 0.4, 0.0, 1.0)


## True while any timed effect is still running (tests, and a hint that frames matter).
func busy() -> bool:
	return shaking() or not _flashes.is_empty() or not _slides.is_empty() or _swing_t >= 0.0 \
			or not _delayed.is_empty() or not numbers.is_empty()


# --- Time and skipping -----------------------------------------------------------------------

## Move every effect on by `dt` seconds. Returns the delayed sounds that are now due.
func advance(dt: float) -> Array[String]:
	time += dt
	if _shake_dur > 0.0:
		_shake_t += dt
		if _shake_t >= _shake_dur:
			_shake_amp = 0.0
			_shake_dur = 0.0
			_shake_t = 0.0
	for id in _flashes.keys():
		var f: Array = _flashes[id]
		f[0] = float(f[0]) + dt
		if float(f[0]) >= float(f[1]):
			_flashes.erase(id)
	for id in _slides.keys():
		var s: Array = _slides[id]
		s[0] = float(s[0]) + dt
		if float(s[0]) >= SLIDE_DUR:
			_slides.erase(id)
	if _swing_t >= 0.0:
		_swing_t += dt
		if _swing_t >= ViewModelPose.duration(_swing_style):
			_swing_t = -1.0
	var i := numbers.size() - 1
	while i >= 0:
		numbers[i]["age"] = float(numbers[i]["age"]) + dt
		if float(numbers[i]["age"]) >= float(numbers[i]["dur"]):
			numbers.remove_at(i)
		i -= 1
	var due: Array[String] = []
	var keep: Array = []
	for d: Array in _delayed:
		d[0] = float(d[0]) - dt
		if float(d[0]) <= 0.0:
			due.append(d[1])
		else:
			keep.append(d)
	_delayed = keep
	return due


## A key was pressed: finish what moves the picture (see the class comment). Numbers carry on.
func on_key() -> void:
	finish()


## Finish the shake, flashes, slides, swing and delayed sounds at once (not the floating numbers).
func finish() -> void:
	_shake_amp = 0.0
	_shake_dur = 0.0
	_shake_t = 0.0
	_flashes.clear()
	_slides.clear()
	_swing_t = -1.0
	_delayed.clear()

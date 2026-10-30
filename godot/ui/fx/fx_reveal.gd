class_name FxReveal
extends RefCounted
## The animated loot box reveal (P8), as a headless timeline: the box rattles and shakes harder
## (SHAKE_END seconds), the lid flies open with a burst of light (OPEN_END), and the item shows. The
## real result is already decided and in the menu text: the animation only hides that text for the first
## SHAKE_END seconds (`item_hidden`) and decorates the box. Any key press calls `skip()`, which ends it at
## once, and the key is handled as always, so nobody waits for a box.
##
## RevealCanvas draws it from `shake_offset`, `lid_lift` and `light`; the sounds are FxPlan's
## ("box_shake" now, "box_open" at BOX_OPEN_DELAY, which is SHAKE_END).

const SHAKE_END := 0.75
const OPEN_END := 1.1

var t: float = 0.0
var running: bool = false
var opened: bool = false         ## the lid has popped this reveal (RevealCanvas fires the sparkles once)


## Begin a reveal (a box was opened, or rerolled).
func start() -> void:
	t = 0.0
	running = true
	opened = false


## End it now (a key press, or Effects off).
func skip() -> void:
	t = OPEN_END
	running = false
	opened = true


func advance(dt: float) -> void:
	if not running:
		return
	t += dt
	if t >= OPEN_END:
		running = false
		t = OPEN_END


func is_done() -> bool:
	return not running


## True while the menu should hide the item text (the box has not opened yet).
func item_hidden() -> bool:
	return running and t < SHAKE_END


## True once the lid is off and the sparkles should fire (the first time `t` passes SHAKE_END).
func should_burst() -> bool:
	if running and t >= SHAKE_END and not opened:
		opened = true
		return true
	return false


## How far the box is shaken, in pixels, at this moment: a rattle that grows towards the opening.
func shake_offset() -> Vector2:
	if not running or t >= SHAKE_END:
		return Vector2.ZERO
	var k := t / SHAKE_END
	var amp := 2.0 + 8.0 * k * k
	return Vector2(sin(t * 90.0), sin(t * 70.0 + 1.3)) * amp


## How far the lid has lifted, 0 (shut) to 1 (gone), eased out after the shake.
func lid_lift() -> float:
	if not running and t >= OPEN_END:
		return 1.0
	if t < SHAKE_END:
		return 0.0
	var k := clampf((t - SHAKE_END) / (OPEN_END - SHAKE_END), 0.0, 1.0)
	return 1.0 - (1.0 - k) * (1.0 - k)


## The burst of light, 0 to 1 and back to 0 over the opening.
func light() -> float:
	if t < SHAKE_END or t >= OPEN_END:
		return 0.0
	var k := (t - SHAKE_END) / (OPEN_END - SHAKE_END)
	return sin(k * PI)

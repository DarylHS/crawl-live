class_name TopController
extends RefCounted
## Input in the top-down map view (the map half of crawler/game.py `App.handle_key`): arrows, WASD
## and the numpad move by the compass, "." or Space waits, ">" or Enter descends. Presses only:
## the map has no free look and no held walking. Headless, like FpController, and fed the same
## InputMap action names.

const MOVES := FpController.MOVES
## Actions a press may mean, in the order App.handle_key tried them.
const ORDER: Array[StringName] = [&"descend", &"move_n", &"move_s", &"move_e", &"move_w",
		&"move_ne", &"move_nw", &"move_se", &"move_sw", &"wait"]

var world: World = null
var blocked: bool = false        ## a menu or help covers the view (P7)


func start(new_world: World) -> void:
	world = new_world


## A key press as an action name. Returns true when it was a game action handled here.
func press(action: StringName) -> bool:
	if world == null or world.state != "playing":
		return false
	if action == &"descend":
		world.descend()
	elif MOVES.has(action):
		var d: Vector2i = MOVES[action]
		world.move_player(d.x, d.y)
	elif action == &"wait":
		world.wait()
	else:
		return false
	return true

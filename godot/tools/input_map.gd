extends SceneTree
## Writes the game's InputMap actions into project.godot (port plan 10.5), so they show in
## Project Settings > Input Map and every scene reads them by name.
##
##   godot --headless --path godot -s res://tools/input_map.gd
##
## Edit ACTIONS and re-run; actions not listed here are left alone. Letters, arrows and the numpad
## use physical keys (the same positions on any layout, as WASD should be); punctuation and Enter
## use the key's meaning, so ">" is Shift + Period. Where one key has several actions (W walks in
## first-person and moves north on the map), the scene decides which applies, as App.handle_key did.

const ACTIONS := {
	# First-person (P4)
	"walk_forward": [KEY_W, KEY_UP],
	"walk_back": [KEY_S, KEY_DOWN],
	"strafe_left": [KEY_A],
	"strafe_right": [KEY_D],
	"turn_left": [KEY_Q, KEY_LEFT],
	"turn_right": [KEY_E, KEY_RIGHT],
	# Compass moves (numpad in first-person; arrows and WASD on the map, P5)
	"move_n": [KEY_UP, KEY_W, KEY_KP_8],
	"move_s": [KEY_DOWN, KEY_S, KEY_KP_2],
	"move_e": [KEY_RIGHT, KEY_D, KEY_KP_6],
	"move_w": [KEY_LEFT, KEY_A, KEY_KP_4],
	"move_ne": [KEY_KP_9],
	"move_nw": [KEY_KP_7],
	"move_se": [KEY_KP_3],
	"move_sw": [KEY_KP_1],
	"wait": ["period", KEY_SPACE, KEY_KP_5],
	"descend": ["shift_period", "enter", "kp_enter"],
	# Views (P5)
	"toggle_view": [KEY_TAB],
	"cycle_render_scale": [KEY_F2],
}


func _init() -> void:
	for action: String in ACTIONS:
		var events: Array = []
		for k in ACTIONS[action]:
			events.append(_event(k))
		ProjectSettings.set_setting("input/" + action, {"deadzone": 0.2, "events": events})
	var err := ProjectSettings.save()
	print("input_map: wrote %d actions (%s)" % [ACTIONS.size(), error_string(err)])
	quit(0 if err == OK else 1)


func _event(k: Variant) -> InputEventKey:
	var e := InputEventKey.new()
	e.device = -1                              # any keyboard, as the editor writes it
	match k:
		"period":
			e.keycode = KEY_PERIOD
		"shift_period":
			e.keycode = KEY_PERIOD
			e.shift_pressed = true
		"enter":
			e.keycode = KEY_ENTER
		"kp_enter":
			e.keycode = KEY_KP_ENTER
		_:
			e.physical_keycode = k
	return e

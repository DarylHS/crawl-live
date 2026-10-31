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
## "?" opens the help by its character (any layout) and F1 by key; ">" descends by its character.

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
	# Play keys and menus (P7). A press means different things by scene (AppState decides which action
	# it tests), so R is both `rest` and `reroll`, D both `drop` and strafing, Enter `confirm` and `descend`.
	"confirm": ["enter", "kp_enter"],
	"back": [KEY_ESCAPE],
	"erase": [KEY_BACKSPACE],
	"menu_up": [KEY_UP, KEY_W],
	"menu_down": [KEY_DOWN, KEY_S],
	"menu_left": [KEY_LEFT],
	"menu_right": [KEY_RIGHT],
	"pickup": [KEY_G],
	"inventory": [KEY_I],
	"rest": [KEY_R],
	"safe_menu": [KEY_M],
	"pet_command": [KEY_C],
	"practice": [KEY_K],
	"attributes": [KEY_L],
	"skill_1": [KEY_1],
	"help": [KEY_F1],
	"accept_deal": [KEY_Y],
	"decline_deal": [KEY_N],
	"unequip": [KEY_U],
	"drop": [KEY_D],
	"reroll": [KEY_R],
	"trade_up": [KEY_T],
	# Views (P5)
	"toggle_view": [KEY_TAB],
	"zoom_map": [KEY_Z],                 # P9: map view, 32 px tiles <-> 16 px glyph overview
	"cycle_render_scale": [KEY_F2],
	# Effects and sound (P8)
	"cycle_effects": [KEY_F3],
	"cycle_volume": [KEY_F4],
	"cycle_art_set": [KEY_F5],           # P9 dev key: next art set (default, sets/*, placeholder)
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

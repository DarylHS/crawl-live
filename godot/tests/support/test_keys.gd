class_name TestKeys
extends RefCounted
## Key events for the AppState tests, as the pygame tests build them (`_key(pygame.K_i, "i")`):
## a pressed InputEventKey with the keycode (as keycode and physical key, so letters, arrows and
## Enter all match their InputMap actions) and the character it types.


## A pressed key. `typed` is the character it types ("" for Enter, arrows, Esc).
static func key(keycode: Key, typed: String = "") -> InputEventKey:
	var e := InputEventKey.new()
	e.keycode = keycode
	e.physical_keycode = keycode
	e.key_label = keycode
	e.pressed = true
	if typed != "":
		e.unicode = typed.unicode_at(0)
	return e


## A letter or digit key typing itself ("d" -> KEY_D typing "d").
static func letter(ch: String) -> InputEventKey:
	return key(OS.find_keycode_from_string(ch.to_upper()) as Key, ch)


## "?" (Shift + slash).
static func question() -> InputEventKey:
	var e := key(KEY_SLASH, "?")
	e.shift_pressed = true
	return e


## ">" (Shift + period).
static func greater() -> InputEventKey:
	var e := key(KEY_PERIOD, ">")
	e.shift_pressed = true
	return e


## Send each of the keys to the app.
static func send(app: AppState, keys: Array) -> void:
	for k in keys:
		app.handle_key(k)

class_name FxSettings
extends RefCounted
## The "Effects: on / reduced / off" and sound settings, as numbers the effect code can read.
##
## Presentation only: the choice lives in settings.json (UserSettings keys `effects`, `volume`,
## `muted`) and never reaches the rules. Every effect asks `profile(mode)` how much of itself to
## show, so there is one place that decides what "reduced" means:
##
##   on       everything: shake, flashes, numbers, particles, slides, torch flicker, weapon swing.
##   reduced  for motion sensitivity and weaker machines: no screen shake, no camera bob, dimmer
##            flashes, a third of the particles, a gentle flicker; numbers and the swing stay (they
##            carry information).
##   off      none of it: no flashes, numbers, particles, shake, slides, flicker or swing. The log
##            and the HUD say everything the effects would. Sound has its own volume and mute.

## Same order as UserSettings.EFFECTS_MODES (F3 walks it).
const MODES: Array[String] = ["on", "reduced", "off"]
## F4 walks these master volumes in percent, then mute.
const VOLUME_STEPS: Array[int] = [100, 70, 40, 10]
## Quietest volume in dB that still plays (at or below this the player is silent).
const SILENT_DB := -60.0


## The knobs for one mode. Unknown modes count as "on".
static func profile(mode: String) -> Dictionary:
	match mode:
		"off":
			return {"shake": 0.0, "bob": 0.0, "flash": 0.0, "numbers": false, "particles": 0.0,
					"slides": false, "flicker": 0.0, "swing": false, "torches": false, "reveal": false}
		"reduced":
			return {"shake": 0.0, "bob": 0.0, "flash": 0.5, "numbers": true, "particles": 0.35,
					"slides": true, "flicker": 0.3, "swing": true, "torches": true, "reveal": true}
		_:
			return {"shake": 1.0, "bob": 1.0, "flash": 1.0, "numbers": true, "particles": 1.0,
					"slides": true, "flicker": 1.0, "swing": true, "torches": true, "reveal": true}


## The mode after `mode` in F3's cycle.
static func next_mode(mode: String) -> String:
	return MODES[(MODES.find(mode) + 1) % MODES.size()]


## The volume after `volume` (percent) in F4's cycle: 100, 70, 40, 10, muted, 100 ...
## Returns {"volume": int, "muted": bool}.
static func next_volume(volume: int, muted: bool) -> Dictionary:
	if muted:
		return {"volume": VOLUME_STEPS[0], "muted": false}
	var i := VOLUME_STEPS.find(volume)
	if i < 0:                                   # an odd hand-edited value: continue from the step below it
		i = 0
		while i < VOLUME_STEPS.size() and VOLUME_STEPS[i] > volume:
			i += 1
		i -= 1
		if i < 0:
			return {"volume": volume, "muted": true}
	if i + 1 >= VOLUME_STEPS.size():
		return {"volume": volume, "muted": true}
	return {"volume": VOLUME_STEPS[i + 1], "muted": false}


## AudioStreamPlayer.volume_db for a master volume in percent (0 to 100). Muted or 0 is silent.
static func volume_db(volume: int, muted: bool) -> float:
	if muted or volume <= 0:
		return SILENT_DB
	return maxf(SILENT_DB, linear_to_db(clampf(volume / 100.0, 0.0, 1.0)))


## The note shown when F3 changes the effects mode, for example "Effects: reduced".
static func describe_effects(mode: String) -> String:
	return "Effects: %s" % mode


## The note shown when F4 changes the sound, for example "Sound: 40%" or "Sound: muted".
static func describe_sound(volume: int, muted: bool) -> String:
	return "Sound: muted" if muted else "Sound: %d%%" % volume

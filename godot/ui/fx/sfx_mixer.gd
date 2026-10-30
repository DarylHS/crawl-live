class_name SfxMixer
extends RefCounted
## The decisions behind playing a sound (headless, so tests need no audio device): whether it plays
## at all (muted or silent volume), whether the same sound played too recently (a bomb that kills five
## monsters asks for five "kill" sounds in one frame; one is plenty), and which of the player's voices
## to use. SfxPlayer does the playing.

## Seconds before the same sound may play again (default MIN_GAP, or the entry here).
const MIN_GAP := 0.05
const GAPS := {"step": 0.12, "hit": 0.06, "kill": 0.1, "select": 0.03}

var volume: int = 70          ## master volume in percent (settings `volume`)
var muted: bool = false       ## settings `muted`
var voices: int = 8           ## how many sounds may play at once
var _last: Dictionary = {}    ## name -> time it last played (seconds on the caller's clock)
var _next_voice: int = 0


func is_silent() -> bool:
	return muted or volume <= 0


## True when `sound_name` should play now (`now` is any steadily increasing clock in seconds). Records it.
func request(sound_name: String, now: float) -> bool:
	if is_silent():
		return false
	var gap: float = GAPS.get(sound_name, MIN_GAP)
	if _last.has(sound_name) and now - float(_last[sound_name]) < gap:
		return false
	_last[sound_name] = now
	return true


## The next voice to use, round robin (the oldest sound is cut off first).
func take_voice() -> int:
	var v := _next_voice
	_next_voice = (_next_voice + 1) % maxi(1, voices)
	return v


## The player volume in dB for the current settings.
func volume_db() -> float:
	return FxSettings.volume_db(volume, muted)

class_name SfxPlayer
extends Node
## Plays the sound effects. An AudioStreamPlayer is Godot's node for playing one AudioStream through
## an audio bus; it can play one sound at a time, so this keeps a small pool of them and hands each
## new sound to the next one (SfxMixer decides which, and whether to play at all). The streams are
## SfxSynth's synthesised placeholders, unless a file res://assets/sfx/<name>.wav (or .ogg) exists, which wins.
##
## Sound is presentation only and never waits on anything: `play` starts a sound and returns. With no
## audio device (a server, the headless tests) Godot uses its dummy audio driver and this still runs.

const OVERRIDE_DIR := "res://assets/sfx/"

var mixer := SfxMixer.new()
var played: Array[String] = []        ## every sound started, newest last (tests read it; capped)
var _players: Array[AudioStreamPlayer] = []
var _overrides: Dictionary = {}       ## name -> AudioStream or false
var _made: Dictionary = {}            ## name -> the synthesised AudioStreamWAV


func _ready() -> void:
	_add_limiter()
	for i in mixer.voices:
		var p := AudioStreamPlayer.new()
		p.bus = &"Master"
		add_child(p)
		_players.append(p)


## Apply the master volume (percent) and mute from the settings.
func configure(volume: int, muted: bool) -> void:
	mixer.volume = volume
	mixer.muted = muted
	for p in _players:
		p.volume_db = mixer.volume_db()


## Start `sound_name` (a key of SfxSynth.SOUNDS) unless muted or just played. Returns true when it started.
func play(sound_name: String, pitch: float = 1.0) -> bool:
	var now := Time.get_ticks_msec() / 1000.0
	if not mixer.request(sound_name, now):
		return false
	var stream := _stream(sound_name)
	if stream == null:
		return false
	played.append(sound_name)
	if played.size() > 64:
		played.remove_at(0)
	if _players.is_empty():
		return true
	var p := _players[mixer.take_voice()]
	p.stream = stream
	p.pitch_scale = pitch
	p.volume_db = mixer.volume_db()
	p.play()
	return true


## Stop everything playing. Quit through `Main.quit_game` or wait a moment after this before `quit()`:
## sounds still playing when the program exits are reported as leaked audio objects.
func stop_all() -> void:
	for p in _players:
		p.stop()


func _stream(sound_name: String) -> AudioStream:
	if not SfxSynth.SOUNDS.has(sound_name):
		return null
	if not _overrides.has(sound_name):
		_overrides[sound_name] = false
		for ext in ["wav", "ogg"]:
			var path: String = OVERRIDE_DIR + sound_name + "." + ext
			if ResourceLoader.exists(path):
				_overrides[sound_name] = load(path)
				break
	if _overrides[sound_name] is AudioStream:
		return _overrides[sound_name]
	if not _made.has(sound_name):
		_made[sound_name] = SfxSynth.stream(sound_name)     # made on first use, kept for the life of this node
	return _made[sound_name]


## Let go of every stream and playback so nothing outlives the node (no leaked audio objects at exit).
func _exit_tree() -> void:
	for p in _players:
		p.stop()
		p.stream = null
	_made.clear()
	_overrides.clear()


## A limiter on the Master bus (once, shared by every SfxPlayer): stacked sounds, such as a bomb that kills three
## monsters at once, are squashed under the ceiling instead of clipping.
static func _add_limiter() -> void:
	var bus := AudioServer.get_bus_index(&"Master")
	if bus < 0:
		return
	for i in AudioServer.get_bus_effect_count(bus):
		if AudioServer.get_bus_effect(bus, i) is AudioEffectLimiter:
			return
	var lim := AudioEffectLimiter.new()
	lim.ceiling_db = -3.0                     # 3 dB of headroom
	lim.threshold_db = -6.0
	AudioServer.add_bus_effect(bus, lim)

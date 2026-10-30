class_name SfxSynth
extends RefCounted
## The game's sound effects, synthesised in code (no audio files, nothing downloaded): tiny placeholders
## made of a few sine, square, saw, triangle and noise voices with a sweep and an envelope each.
## Replace any of them later by dropping a WAV or OGG at res://assets/sfx/<name>.wav or .ogg (SfxPlayer
## looks there first).
##
## `samples(name)` gives the mono float samples (-1 to 1) at MIX_RATE, deterministic (the noise is a
## fixed linear congruential generator, not Godot's RNG, and nothing here touches the game's RNG);
## `stream(name)` wraps them in an AudioStreamWAV, 16-bit mono, which an AudioStreamPlayer plays.
## `godot/tools/export_sfx.gd` writes them out as .wav files to listen to or inspect.
##
## A voice is {w: wave, f0: start Hz, f1: end Hz, t0: start time s, dur: seconds, vol: 0 to 1,
## lp: noise low-pass 0..1 (1 = off), vib: [Hz, depth]}. Waves: "sine", "square", "saw", "tri", "noise".

const MIX_RATE := 22050
## Name -> [peak level 0..1, voices]. The first group is the brief's list (hit, miss, crit, kill, step,
## descend, box open, achievement, UI select); the rest are extras for other events.
const SOUNDS := {
	"hit": [0.7, [{"w": "noise", "f0": 0, "f1": 0, "t0": 0.0, "dur": 0.09, "vol": 1.0, "lp": 0.35},
			{"w": "sine", "f0": 240, "f1": 80, "t0": 0.0, "dur": 0.12, "vol": 0.9}]],
	"miss": [0.3, [{"w": "noise", "f0": 0, "f1": 0, "t0": 0.0, "dur": 0.16, "vol": 1.0, "lp": 0.6, "swell": true}]],
	"crit": [0.8, [{"w": "noise", "f0": 0, "f1": 0, "t0": 0.0, "dur": 0.1, "vol": 1.0, "lp": 0.5},
			{"w": "sine", "f0": 300, "f1": 70, "t0": 0.0, "dur": 0.14, "vol": 0.9},
			{"w": "square", "f0": 880, "f1": 1320, "t0": 0.03, "dur": 0.14, "vol": 0.35},
			{"w": "sine", "f0": 1760, "f1": 1760, "t0": 0.06, "dur": 0.24, "vol": 0.3}]],
	"kill": [0.75, [{"w": "tri", "f0": 420, "f1": 70, "t0": 0.0, "dur": 0.26, "vol": 0.9},
			{"w": "noise", "f0": 0, "f1": 0, "t0": 0.0, "dur": 0.14, "vol": 0.7, "lp": 0.3}]],
	"step": [0.28, [{"w": "noise", "f0": 0, "f1": 0, "t0": 0.0, "dur": 0.05, "vol": 1.0, "lp": 0.12},
			{"w": "sine", "f0": 95, "f1": 60, "t0": 0.0, "dur": 0.06, "vol": 0.7}]],
	"descend": [0.55, [{"w": "tri", "f0": 392, "f1": 392, "t0": 0.0, "dur": 0.11, "vol": 0.9},
			{"w": "tri", "f0": 330, "f1": 330, "t0": 0.1, "dur": 0.11, "vol": 0.9},
			{"w": "tri", "f0": 262, "f1": 262, "t0": 0.2, "dur": 0.11, "vol": 0.9},
			{"w": "tri", "f0": 196, "f1": 130, "t0": 0.3, "dur": 0.3, "vol": 0.9}]],
	"box_shake": [0.4, [{"w": "square", "f0": 110, "f1": 110, "t0": 0.0, "dur": 0.7, "vol": 0.5, "vib": [28.0, 0.6]},
			{"w": "noise", "f0": 0, "f1": 0, "t0": 0.0, "dur": 0.7, "vol": 0.4, "lp": 0.2}]],
	"box_open": [0.6, [{"w": "tri", "f0": 523, "f1": 523, "t0": 0.0, "dur": 0.1, "vol": 0.9},
			{"w": "tri", "f0": 659, "f1": 659, "t0": 0.08, "dur": 0.1, "vol": 0.9},
			{"w": "tri", "f0": 784, "f1": 784, "t0": 0.16, "dur": 0.1, "vol": 0.9},
			{"w": "tri", "f0": 1047, "f1": 1047, "t0": 0.24, "dur": 0.2, "vol": 0.9},
			{"w": "sine", "f0": 2093, "f1": 2637, "t0": 0.26, "dur": 0.4, "vol": 0.35}]],
	"achievement": [0.6, [{"w": "square", "f0": 659, "f1": 659, "t0": 0.0, "dur": 0.1, "vol": 0.6},
			{"w": "square", "f0": 880, "f1": 880, "t0": 0.1, "dur": 0.1, "vol": 0.6},
			{"w": "square", "f0": 1319, "f1": 1319, "t0": 0.2, "dur": 0.32, "vol": 0.6},
			{"w": "sine", "f0": 2637, "f1": 2637, "t0": 0.2, "dur": 0.32, "vol": 0.25}]],
	"select": [0.4, [{"w": "square", "f0": 660, "f1": 660, "t0": 0.0, "dur": 0.04, "vol": 0.7},
			{"w": "square", "f0": 990, "f1": 990, "t0": 0.04, "dur": 0.05, "vol": 0.7}]],
	"hurt": [0.7, [{"w": "saw", "f0": 170, "f1": 70, "t0": 0.0, "dur": 0.2, "vol": 0.8},
			{"w": "noise", "f0": 0, "f1": 0, "t0": 0.0, "dur": 0.1, "vol": 0.6, "lp": 0.4}]],
	"boom": [0.85, [{"w": "noise", "f0": 0, "f1": 0, "t0": 0.0, "dur": 0.5, "vol": 1.0, "lp": 0.18},
			{"w": "sine", "f0": 90, "f1": 28, "t0": 0.0, "dur": 0.45, "vol": 1.0}]],
	"roar": [0.8, [{"w": "saw", "f0": 95, "f1": 55, "t0": 0.0, "dur": 0.8, "vol": 0.8, "vib": [14.0, 0.25]},
			{"w": "noise", "f0": 0, "f1": 0, "t0": 0.0, "dur": 0.6, "vol": 0.5, "lp": 0.15}]],
	"fanfare": [0.65, [{"w": "square", "f0": 392, "f1": 392, "t0": 0.0, "dur": 0.13, "vol": 0.6},
			{"w": "square", "f0": 494, "f1": 494, "t0": 0.13, "dur": 0.13, "vol": 0.6},
			{"w": "square", "f0": 587, "f1": 587, "t0": 0.26, "dur": 0.13, "vol": 0.6},
			{"w": "square", "f0": 784, "f1": 784, "t0": 0.39, "dur": 0.4, "vol": 0.6}]],
	"heal": [0.5, [{"w": "sine", "f0": 523, "f1": 1047, "t0": 0.0, "dur": 0.28, "vol": 0.9},
			{"w": "sine", "f0": 1047, "f1": 1568, "t0": 0.1, "dur": 0.25, "vol": 0.4}]],
	"pickup": [0.45, [{"w": "sine", "f0": 784, "f1": 784, "t0": 0.0, "dur": 0.06, "vol": 0.9},
			{"w": "sine", "f0": 1047, "f1": 1047, "t0": 0.06, "dur": 0.1, "vol": 0.9}]],
	"levelup": [0.6, [{"w": "tri", "f0": 392, "f1": 392, "t0": 0.0, "dur": 0.09, "vol": 0.9},
			{"w": "tri", "f0": 494, "f1": 494, "t0": 0.08, "dur": 0.09, "vol": 0.9},
			{"w": "tri", "f0": 587, "f1": 587, "t0": 0.16, "dur": 0.09, "vol": 0.9},
			{"w": "tri", "f0": 784, "f1": 784, "t0": 0.24, "dur": 0.09, "vol": 0.9},
			{"w": "tri", "f0": 988, "f1": 988, "t0": 0.32, "dur": 0.25, "vol": 0.9}]],
	"death": [0.8, [{"w": "saw", "f0": 220, "f1": 50, "t0": 0.0, "dur": 1.0, "vol": 0.8},
			{"w": "noise", "f0": 0, "f1": 0, "t0": 0.0, "dur": 0.3, "vol": 0.4, "lp": 0.2}]],
	"combat": [0.6, [{"w": "square", "f0": 110, "f1": 100, "t0": 0.0, "dur": 0.13, "vol": 0.8},
			{"w": "square", "f0": 82, "f1": 78, "t0": 0.15, "dur": 0.2, "vol": 0.8}]],
}

static var _streams: Dictionary = {}      ## name -> AudioStreamWAV


## Every sound name.
static func names() -> Array[String]:
	var out: Array[String] = []
	for k: String in SOUNDS:
		out.append(k)
	return out


## Length of a sound in seconds (its last voice to finish).
static func length(sound_name: String) -> float:
	var end := 0.0
	for v: Dictionary in SOUNDS[sound_name][1]:
		end = maxf(end, float(v["t0"]) + float(v["dur"]))
	return end


## The mono samples of a sound, scaled so the loudest is its peak level.
static func samples(sound_name: String) -> PackedFloat32Array:
	var spec: Array = SOUNDS[sound_name]
	var n := int(ceil(length(sound_name) * MIX_RATE)) + 1
	var mix := PackedFloat32Array()
	mix.resize(n)
	var seed_state := 12345 + sound_name.length() * 977
	for v: Dictionary in spec[1]:
		seed_state = _voice(mix, v, seed_state)
	var loudest := 0.0001
	for i in n:
		loudest = maxf(loudest, absf(mix[i]))
	var k := float(spec[0]) / loudest
	for i in n:
		mix[i] = clampf(mix[i] * k, -1.0, 1.0)
	return mix


## An AudioStreamWAV (16-bit mono) for a sound, made once and kept.
static func stream(sound_name: String) -> AudioStreamWAV:
	if _streams.has(sound_name):
		return _streams[sound_name]
	var s := samples(sound_name)
	var data := PackedByteArray()
	data.resize(s.size() * 2)
	for i in s.size():
		data.encode_s16(i * 2, roundi(s[i] * 32767.0))
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	_streams[sound_name] = wav
	return wav


## Write one voice into `mix`. Returns the noise generator state to carry on with.
static func _voice(mix: PackedFloat32Array, v: Dictionary, noise_state: int) -> int:
	var start := int(float(v["t0"]) * MIX_RATE)
	var count := int(float(v["dur"]) * MIX_RATE)
	var wave: String = v["w"]
	var f0 := float(v["f0"])
	var f1 := float(v["f1"])
	var vol := float(v["vol"])
	var lp := float(v.get("lp", 1.0))
	var vib: Array = v.get("vib", [0.0, 0.0])
	var swell: bool = v.get("swell", false)
	var phase := 0.0
	var low := 0.0
	var attack := maxi(1, int(0.004 * MIX_RATE))
	for i in count:
		if start + i >= mix.size():
			break
		var u := float(i) / float(count)
		var env := 1.0 - u
		env *= env
		if swell:
			env = sin(u * PI)                                  # a whoosh rises and falls
		if i < attack:
			env *= float(i) / float(attack)
		var f := lerpf(f0, f1, u)
		if float(vib[0]) > 0.0:
			f *= 1.0 + float(vib[1]) * sin(TAU * float(vib[0]) * float(i) / MIX_RATE)
		phase += f / MIX_RATE
		var x := 0.0
		match wave:
			"sine":
				x = sin(TAU * phase)
			"square":
				x = 1.0 if fmod(phase, 1.0) < 0.5 else -1.0
			"saw":
				x = 2.0 * fmod(phase, 1.0) - 1.0
			"tri":
				x = 4.0 * absf(fmod(phase, 1.0) - 0.5) - 1.0
			_:
				noise_state = (noise_state * 1103515245 + 12345) & 0x7fffffff
				x = float(noise_state) / 1073741823.5 - 1.0
				low += lp * (x - low)
				x = low if lp < 1.0 else x
				if lp < 1.0:
					x *= 1.0 / maxf(lp, 0.1) * 0.5                 # a low-passed noise is quieter: bring it back up
		mix[start + i] += x * env * vol
	return noise_state

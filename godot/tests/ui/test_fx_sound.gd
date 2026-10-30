extends TestCase
## P8 sound: the synthesised placeholder sounds (SfxSynth), the mixer's rules for muting and throttling
## (SfxMixer) and the player node (SfxPlayer). No audio device is needed: Godot's dummy driver takes the
## streams, and the samples themselves are checked.

const BRIEF := ["hit", "miss", "crit", "kill", "step", "descend", "box_open", "achievement", "select"]


func test_every_sound_the_brief_lists_exists_and_every_event_sound_is_defined() -> void:
	for n: String in BRIEF:
		assert_true(SfxSynth.SOUNDS.has(n), n)
	for event in FxPlan.events():
		for e in FxPlan.plan(event, {"hit": false, "crit": true, "damage": 99, "healed": 4, "boss": true}, {"mode": "on", "max_hp": 10}):
			if e["k"] == "sound":
				assert_true(SfxSynth.SOUNDS.has(e["name"]), "%s plays a sound that is not defined: %s" % [event, e["name"]])


func test_samples_are_audible_in_range_deterministic_and_the_right_length() -> void:
	for n in SfxSynth.names():
		var a := SfxSynth.samples(n)
		var b := SfxSynth.samples(n)
		assert_eq(a, b, "%s is the same every time" % n)
		var peak := 0.0
		var energy := 0.0
		for x in a:
			peak = maxf(peak, absf(x))
			energy += x * x
		assert_gt(peak, 0.2, "%s is audible" % n)
		assert_lte(peak, 1.0, "%s does not clip" % n)
		assert_gt(energy / a.size(), 0.0005, "%s has body" % n)
		assert_almost_eq(float(a.size()) / SfxSynth.MIX_RATE, SfxSynth.length(n), 0.01, n)
		assert_lt(SfxSynth.length(n), 1.5, "%s is short" % n)
		assert_lt(absf(a[a.size() - 1]), 0.05, "%s ends quietly (no click)" % n)


func test_the_sounds_differ_from_each_other() -> void:
	var seen := {}
	for n in SfxSynth.names():
		var s := SfxSynth.samples(n)
		var sig := "%d:%s" % [s.size(), str(snappedf(s[s.size() / 3], 0.0001))]
		assert_false(seen.has(sig), "%s sounds like %s" % [n, seen.get(sig, "")])
		seen[sig] = n


func test_streams_are_16_bit_mono_wavs() -> void:
	var w := SfxSynth.stream("hit")
	assert_eq(w.format, AudioStreamWAV.FORMAT_16_BITS)
	assert_eq(w.mix_rate, SfxSynth.MIX_RATE)
	assert_false(w.stereo)
	assert_eq(w.data.size(), SfxSynth.samples("hit").size() * 2)


func test_the_mixer_mutes_throttles_and_rotates_voices() -> void:
	var m := SfxMixer.new()
	assert_true(m.request("hit", 1.0))
	assert_false(m.request("hit", 1.01), "the same sound twice in a frame plays once")
	assert_true(m.request("miss", 1.01), "a different sound is fine")
	assert_true(m.request("hit", 1.2))
	assert_true(m.request("step", 2.0))
	assert_false(m.request("step", 2.1), "steps are spaced further apart")
	m.muted = true
	assert_false(m.request("kill", 5.0))
	assert_true(m.is_silent())
	m.muted = false
	m.volume = 0
	assert_false(m.request("kill", 6.0))
	m.volume = 70
	var voices := []
	for _i in 10:
		voices.append(m.take_voice())
	assert_eq(voices.slice(0, 8), [0, 1, 2, 3, 4, 5, 6, 7])
	assert_eq(voices[8], 0)
	assert_eq(m.volume_db(), FxSettings.volume_db(70, false))


func test_the_player_plays_mutes_and_follows_the_volume() -> void:
	var p := SfxPlayer.new()
	add_child_autofree(p)
	p.configure(40, false)
	assert_true(p.play("hit"))
	assert_eq(p.played, ["hit"] as Array[String])
	assert_almost_eq((p.get_child(0) as AudioStreamPlayer).volume_db, FxSettings.volume_db(40, false), 0.001)
	assert_false(p.play("nonsense"))
	p.configure(40, true)
	assert_false(p.play("kill"), "muted plays nothing")
	assert_eq(p.played.size(), 1)
	p.configure(100, false)
	assert_true(p.play("kill"))
	assert_eq((p.get_child(1) as AudioStreamPlayer).volume_db, 0.0)

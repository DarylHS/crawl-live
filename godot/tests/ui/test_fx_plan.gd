extends TestCase
## P8 effects, the decisions (headless): which effects fire for which World event (FxPlan), what the
## Effects on / reduced / off setting and the sound settings mean (FxSettings), and that the settings
## survive in settings.json beside the view and render scale (UserSettings), with Python's file untouched.


func _kinds(effects: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e in effects:
		out.append(e["k"])
	return out


func _find(effects: Array[Dictionary], kind: String) -> Dictionary:
	for e in effects:
		if e["k"] == kind:
			return e
	return {}


func _sounds(effects: Array[Dictionary]) -> Array[String]:
	var out: Array[String] = []
	for e in effects:
		if e["k"] == "sound":
			out.append(e["name"])
	return out


# --- Which effects fire for which event ---------------------------------------------------------

func test_a_normal_hit_flashes_numbers_and_sparks_but_does_not_shake() -> void:
	var fx := FxPlan.plan("player_hit", {"target": "goblin", "damage": 7, "crit": false})
	assert_eq(_sounds(fx), ["hit"])
	assert_eq(_find(fx, "number")["text"], "-7")
	assert_eq(_find(fx, "number")["at"], "target")
	assert_eq(_find(fx, "flash")["at"], "target")
	assert_eq(_find(fx, "burst")["kind"], "hit")
	assert_true(_find(fx, "shake").is_empty())


func test_a_crit_adds_shake_gold_text_and_more_sparks() -> void:
	var fx := FxPlan.plan("player_hit", {"target": "goblin", "damage": 12, "crit": true})
	assert_eq(_sounds(fx), ["crit"])
	assert_eq(_find(fx, "number")["text"], "CRIT -12!")
	assert_eq(_find(fx, "number")["tone"], "crit")
	assert_gt(float(_find(fx, "shake")["amp"]), 0.4)
	var normal := FxPlan.plan("player_hit", {"target": "goblin", "damage": 12, "crit": false})
	assert_gt(int(_find(fx, "burst")["count"]), int(_find(normal, "burst")["count"]))


func test_a_miss_swings_and_says_miss_without_a_flash() -> void:
	var fx := FxPlan.plan("player_attack", {"target": "goblin", "hit": false, "crit": false})
	assert_true(_kinds(fx).has("swing"))
	assert_eq(_sounds(fx), ["miss"])
	assert_eq(_find(fx, "number")["text"], "miss")
	assert_true(_find(fx, "flash").is_empty())
	var hit := FxPlan.plan("player_attack", {"target": "goblin", "hit": true, "crit": false})
	assert_eq(_kinds(hit), ["swing"])                 # a hit's sound, flash and number come with player_hit


func test_boss_phase_is_the_biggest_shake_and_names_the_phase() -> void:
	var fx := FxPlan.plan("boss_phase", {"boss": "Glorm", "phase": 2})
	assert_eq(float(_find(fx, "shake")["amp"]), 1.0)
	assert_eq(_find(fx, "number")["text"], "PHASE TWO")
	assert_eq(_sounds(fx), ["roar"])
	for event in ["player_hit", "bomb", "kill", "boss_kill", "damage_taken"]:
		for e in FxPlan.plan(event, {"damage": 40, "crit": true, "boss": true}, {"max_hp": 40}):
			if e["k"] == "shake":
				assert_lte(float(e["amp"]), 1.0)


func test_a_bomb_booms_with_particles_and_a_shake() -> void:
	var fx := FxPlan.plan("bomb", {"item": "popper", "kills": 2})
	assert_eq(_sounds(fx), ["boom"])
	assert_eq(_find(fx, "burst")["kind"], "bomb")
	assert_eq(_find(fx, "burst")["at"], "bomb")
	assert_false(_find(fx, "shake").is_empty())


func test_damage_you_take_shakes_only_when_it_is_a_big_share_of_your_hp() -> void:
	var small := FxPlan.plan("damage_taken", {"damage": 3}, {"max_hp": 34})
	var big := FxPlan.plan("damage_taken", {"damage": 9}, {"max_hp": 34})
	assert_true(_find(small, "shake").is_empty())
	assert_false(_find(big, "shake").is_empty())
	assert_eq(_find(small, "number")["tone"], "hurt")
	assert_eq(_find(small, "number")["at"], "player")
	assert_eq(_sounds(small), ["hurt"])


func test_the_brief_sounds_all_have_an_event() -> void:
	# hit, miss, crit, kill, step, descend, box open, achievement (UI select is the menus' own)
	var table := {"player_hit": "hit", "player_attack": "miss", "kill": "kill", "step": "step",
			"descend": "descend", "box_opened": "box_open", "achievement": "achievement"}
	for event: String in table:
		var data := {"hit": false, "crit": false, "damage": 1}
		assert_has(_sounds(FxPlan.plan(event, data, {"mode": "off"})), table[event], event)
	assert_has(_sounds(FxPlan.plan("player_hit", {"crit": true, "damage": 1})), "crit")
	assert_true(SfxSynth.SOUNDS.has("select"))


func test_the_box_opens_a_moment_after_it_starts_to_rattle() -> void:
	var fx := FxPlan.plan("box_opened", {"tier": "gold", "item": "pan", "rerolled": false})
	assert_eq(_sounds(fx), ["box_shake", "box_open"])
	assert_eq(float(fx[1]["delay"]), FxPlan.BOX_OPEN_DELAY)
	assert_eq(FxPlan.BOX_OPEN_DELAY, FxReveal.SHAKE_END)
	var off := FxPlan.plan("box_opened", {}, {"mode": "off"})
	assert_eq(_sounds(off), ["box_open"])               # no animation to wait for
	assert_eq(float(off[0]["delay"]), 0.0)


func test_healing_shows_a_green_plus_and_unknown_events_do_nothing() -> void:
	var fx := FxPlan.plan("item_use", {"item": "tonic", "healed": 8})
	assert_eq(_find(fx, "number")["text"], "+8")
	assert_eq(_find(fx, "number")["tone"], "heal")
	assert_eq(FxPlan.plan("floor_start", {}).size(), 0)
	assert_eq(FxPlan.plan("nonsense", {}).size(), 0)
	for e in FxPlan.events():
		assert_true(e is String)


# --- The Effects setting ---------------------------------------------------------------------

func test_reduced_drops_shake_and_cuts_flashes_and_particles_but_keeps_numbers() -> void:
	var all_events := {"player_attack": {"hit": true}, "player_hit": {"damage": 12, "crit": true}, "nat20": {},
			"damage_taken": {"damage": 20}, "kill": {"boss": true}, "boss_phase": {}, "boss_kill": {}, "bomb": {},
			"pet_hit": {"damage": 3}, "item_use": {"healed": 5}, "player_death": {}}
	for event: String in all_events:
		var on := FxPlan.plan(event, all_events[event], {"mode": "on", "max_hp": 34})
		var reduced := FxPlan.plan(event, all_events[event], {"mode": "reduced", "max_hp": 34})
		assert_true(_find(reduced, "shake").is_empty(), "%s: no shake when reduced" % event)
		assert_eq(_sounds(reduced), _sounds(on), event)
		if not _find(on, "number").is_empty():
			assert_false(_find(reduced, "number").is_empty(), "%s keeps its number" % event)
		if not _find(on, "burst").is_empty():
			assert_lt(int(_find(reduced, "burst")["count"]), int(_find(on, "burst")["count"]), event)
		if not _find(on, "flash").is_empty():
			assert_lt(float(_find(reduced, "flash")["strength"]), float(_find(on, "flash")["strength"]), event)


func test_off_plans_sounds_only() -> void:
	for event in FxPlan.events():
		for e in FxPlan.plan(event, {"hit": true, "crit": true, "damage": 30, "healed": 5, "boss": true}, {"mode": "off", "max_hp": 34}):
			assert_eq(e["k"], "sound", "%s planned a %s with effects off" % [event, e["k"]])


func test_mode_profiles_and_cycles() -> void:
	assert_eq(FxSettings.next_mode("on"), "reduced")
	assert_eq(FxSettings.next_mode("reduced"), "off")
	assert_eq(FxSettings.next_mode("off"), "on")
	assert_eq(FxSettings.next_mode("rubbish"), "on")           # an unknown mode counts as the last: the cycle restarts
	assert_eq(float(FxSettings.profile("on")["shake"]), 1.0)
	assert_eq(float(FxSettings.profile("reduced")["shake"]), 0.0)
	assert_eq(float(FxSettings.profile("off")["particles"]), 0.0)
	assert_eq(FxSettings.profile("rubbish"), FxSettings.profile("on"))
	assert_eq(FxSettings.describe_effects("reduced"), "Effects: reduced")


func test_volume_cycle_and_db() -> void:
	var v := {"volume": 100, "muted": false}
	var seen: Array = []
	for _i in 6:
		v = FxSettings.next_volume(v["volume"], v["muted"])
		seen.append(FxSettings.describe_sound(v["volume"], v["muted"]))
	assert_eq(seen, ["Sound: 70%", "Sound: 40%", "Sound: 10%", "Sound: muted", "Sound: 100%", "Sound: 70%"])
	assert_eq(FxSettings.volume_db(100, false), 0.0)
	assert_lt(FxSettings.volume_db(40, false), FxSettings.volume_db(70, false))
	assert_eq(FxSettings.volume_db(100, true), FxSettings.SILENT_DB)
	assert_eq(FxSettings.volume_db(0, false), FxSettings.SILENT_DB)
	assert_eq(FxSettings.next_volume(55, false)["volume"], 40)    # a hand-edited value steps down


# --- settings.json ----------------------------------------------------------------------------

func test_effects_and_sound_settings_round_trip_and_bad_values_fall_back() -> void:
	var path := TestHelpers.tmp_dir("fx_settings") + "settings.json"
	var s := UserSettings.DEFAULTS.duplicate()
	s["effects"] = "reduced"
	s["volume"] = 40
	s["muted"] = true
	assert_true(UserSettings.save(s, path))
	assert_eq(UserSettings.load(path), s)
	UserSettings.save({"view": "fp", "effects": "loud", "volume": 900, "muted": "yes"}, path)
	var d := UserSettings.load(path)
	assert_eq(d["effects"], "on")
	assert_eq(d["volume"], 70)
	assert_eq(d["muted"], false)
	UserSettings.save({"view": "top"}, path)                       # an old file has none of them
	assert_eq(UserSettings.load(path)["effects"], "on")
	assert_eq(UserSettings.DEFAULTS["effects"], "on")


func test_f3_and_f4_change_the_settings_and_save_them() -> void:
	var path := TestHelpers.tmp_dir("fx_f3") + "settings.json"
	var app := AppState.new({"settings_path": path, "runs_dir": ""})
	var notes: Array[String] = []
	app.setting_changed.connect(func(t: String) -> void: notes.append(t))
	assert_eq(app.cycle_effects(), "reduced")
	assert_eq(UserSettings.load(path)["effects"], "reduced")
	app.handle_key(KeyEvents.key(KEY_F3))                          # the real key, on the title screen
	assert_eq(app.settings["effects"], "off")
	app.handle_key(KeyEvents.key(KEY_F4))
	assert_eq(app.settings["volume"], 40)                          # the default is 70
	app.press(&"cycle_volume")
	assert_eq(app.settings["volume"], 10)
	app.press(&"cycle_volume")
	assert_true(app.settings["muted"])
	var again := AppState.new({"settings_path": path, "runs_dir": ""})
	assert_eq(again.settings["effects"], "off")
	assert_true(again.settings["muted"])
	assert_eq(notes[0], "Effects: reduced")
	assert_eq(notes[-1], "Sound: muted")
	assert_true(InputMap.has_action(&"cycle_effects"))
	assert_true(InputMap.has_action(&"cycle_volume"))

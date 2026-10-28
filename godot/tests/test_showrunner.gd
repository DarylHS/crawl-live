extends TestCase
## tests/test_showrunner.py: the System lines, the viewers model (kill streaks, clutch, decay),
## sponsor gifts, box reactions and the address. The achievement tests of that file (unlock once,
## close call, dressed to kill, deep diver) wait for the real Achievements (T1, docs/port-plan.md
## B.1). Ownership of the Showrunner is in test_s4_standins.gd and test_world.gd.


func after_each() -> void:
	TestHelpers.restore_patches()


func _kill(w: World, hp: int = -1, monster: String = "goblin", by: String = "melee") -> void:
	var p := w.player
	w.events.emit("kill", {"monster": monster, "depth": 1, "turn": w.turn, "by": by,
			"player_hp": p.hp if hp < 0 else hp, "player_max_hp": p.max_hp})


func test_every_event_has_mild_and_spicy_lines_that_format() -> void:
	var w := World.new(1)
	var ctx := {"depth": 1, "name": "x", "level": 2, "tier": "Gold", "sponsor": "S", "achievement": "A",
			"pet": "P", "ability": "B", "boss": "Boss", "title": "Elf Duellist", "item": "Sock", "value": 2,
			"ev": "7", "deal": "Gloop Blitz", "foe": "the goblin", "Foe": "The goblin",
			"why": "Rolled a natural 1.", "reward": "a Bronze box"}
	var lines: Dictionary = Content.table("lines")
	var full := ctx.duplicate()
	full["hero"] = "Daz"
	full["address"] = "madam"
	for kind in lines:
		var pools: Dictionary = lines[kind]
		assert_gte(pools["mild"].size(), 2, kind)
		assert_gte(pools["spicy"].size(), 3, kind)
		assert_gte(pools["mild"].size() + pools["spicy"].size(), 5, kind)
		for line in pools["mild"] + pools["spicy"]:
			var text := PyFmt.format_map(line, full)
			assert_false("{" in text, "%s %s" % [kind, line])
			assert_false("?" in text and not ("?" in line), "%s %s" % [kind, line])   # a missing key gives "?"
	for kind in lines:
		w.showrunner._say(kind, ctx)
	for m in w.messages.recent(200):
		assert_false("{" in m[0])


func test_sass_level_controls_spice(level_expect = use_parameters([[0, "mild"], [10, "spicy"]])) -> void:
	TestHelpers.patch_static(GameConfig, "SASS_LEVEL", level_expect[0])
	var w := World.new(2)
	w.messages.lines.clear()
	for _i in range(20):
		w.showrunner._say("player_death")
	var said := {}
	for m in w.messages.recent(20):
		said[m[0].trim_prefix("SYSTEM: ")] = true
	var pool := {}
	for line in Content.table("lines")["player_death"][level_expect[1]]:
		pool[PyFmt.format_map(line, {"address": w.address, "hero": w.hero_name})] = true
	for s in said:
		assert_true(pool.has(s), s)


func test_box_reactions_follow_the_roll() -> void:
	assert_eq(Showrunner.box_kind("silver", "trophy"), "box_junk")
	assert_eq(Showrunner.box_kind("legendary", "katana"), "box_jackpot")
	assert_eq(Showrunner.box_kind("silver", "brew"), "box_meh")
	assert_eq(Showrunner.box_kind("silver", "vest"), "box_good")          # 22 vs 13.7 +/- 6.1
	assert_eq(Showrunner.box_kind("platinum", "elixir"), "box_meh")       # 30 vs 30.9 +/- 10.0
	assert_eq(Showrunner.box_kind("platinum", "fireworks"), "box_bad")    # 20 < 30.9 - 10.0
	assert_eq(Showrunner.box_kind("legendary", "fireworks"), "box_bad")   # 20 vs 42.5 +/- 13.8
	var w := World.new(3)
	w.events.emit("box_opened", {"tier": "legendary", "item": "katana", "rerolled": false})
	assert_true("Katana" in w.messages.recent(1)[0][0])


func test_address_follows_gender_and_race() -> void:
	var w := World.new(4, null, {"name": "Daz", "gender": "male", "backstory": "veteran"})
	assert_eq(w.address, "sir")
	assert_eq(w.hero_name, "Daz")
	w.new_floor(3)
	w.choose_class("bog_troll", "brawler")
	assert_eq(w.address, "creature")


func test_viewers_rise_on_kills_and_streaks_pay_more() -> void:
	var w := World.new(1)
	assert_eq(w.viewers, Showrunner.START_VIEWERS)
	_kill(w)
	w.turn += 20
	var before := w.viewers
	_kill(w)
	var single := w.viewers - before
	assert_gt(single, 0)
	before = w.viewers
	_kill(w)                                    # same turn: multi-kill
	assert_gt(w.viewers - before, single)


func test_clutch_kill_pays_more() -> void:
	var a := World.new(1)
	var b := World.new(1)
	_kill(a)
	_kill(b, 1)
	assert_gt(b.viewers, a.viewers)


func test_viewers_decay_when_idle_but_not_below_floor() -> void:
	var w := World.new(1)
	for _i in range(40):
		w.wait()
	assert_lt(w.viewers, Showrunner.START_VIEWERS)
	for _i in range(600):
		w.showrunner._idle("turn", {"turn": w.turn + 10})
		w.turn += 10
	assert_eq(w.viewers, Showrunner.MIN_VIEWERS)


func test_sponsor_gift_at_threshold() -> void:
	var w := World.new(1)
	var gifts: Array = []
	w.events.subscribe("sponsor_gift", func(_n: String, d: Dictionary) -> void: gifts.append(d))
	var table := Showrunner.sponsor_gifts()
	w.showrunner._gain(table[0]["viewers"])
	assert_false(gifts.is_empty())
	assert_eq(gifts[0]["tier"], table[0]["tier"])
	assert_true(w.boxes.has(table[0]["tier"]))
	w.showrunner._gain(1)
	assert_eq(gifts.size(), 1)                  # no repeat
	var tiers: Array = []
	for g in table:
		tiers.append(g["tier"])
	assert_eq(tiers, Loot.TIERS)


func test_announcer_does_not_change_the_dungeon() -> void:
	var a := World.new(7)
	var b := World.new(7)
	for _i in range(30):                        # chatter on one side only
		a.showrunner._say("kill", {"name": "x"})
	assert_true(a.floor.tiles == b.floor.tiles)
	assert_true(a.floor_items == b.floor_items)
	assert_eq(a.rng.random(), b.rng.random())


func test_every_monster_has_viewer_value() -> void:
	var monsters: Dictionary = Content.table("monsters")
	for k in monsters:
		assert_true(monsters[k].has("xp"), k)


## Subscription order is RNG order: the announcer before the viewer model, as in Python.
func test_subscription_order_matches_python() -> void:
	var w := World.new(5)
	var kill_names: Array = []
	for c in w.events.subscribers("kill"):
		if c.get_object() == w.showrunner:
			kill_names.append(c.get_method())
	assert_eq(kill_names, [&"_announce", &"_viewers"])
	var box_names: Array = []
	for c in w.events.subscribers("box_opened"):
		if c.get_object() == w.showrunner:
			box_names.append(c.get_method())
	assert_eq(box_names, [&"_box_reaction"])


## World init emits floor_start, so the show stream has already drawn; replaying it from the seed
## and discarding the same number of words gives the same state.
func test_the_show_stream_is_seed_xor_5eed() -> void:
	var w := World.new(77)
	var fresh := PyRandom.new(77 ^ 0x5EED)
	for _i in range(w.showrunner.rng.words_used):
		fresh.genrand_uint32()
	assert_eq(w.showrunner.rng.get_state(), fresh.get_state())

extends TestCase
## tests/test_achievement_loot.py: box reasons stay in order, trade-up gives the new box its own
## reason, monsters drop from their own pockets (S8), and the tests that need the real Achievements
## (T1) and the Showrunner (T2).


func _in_safe_room(w: World) -> void:
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y


func test_a_box_remembers_why_and_the_reveal_says_so() -> void:
	var w := World.new(1)
	w.events.emit("nat1", {"foe": "the goblin", "Foe": "The goblin"})          # Blooper Reel
	assert_true(w.achievements.unlocked.has("blooper_reel"))
	var popped := false
	for t in w.toasts:
		if "Blooper Reel" in t[1] and t.size() == 4:
			popped = true
	assert_true(popped)                                  # pop-up with reward line
	var tier: String = Achievements.table()["blooper_reel"]["tier"]
	assert_true(w.boxes.has(tier))
	assert_true("natural 1" in w.box_reasons[tier][0])
	_in_safe_room(w)
	assert_true(w.open_box(tier))
	assert_true(String(w.last_reason).begins_with("Blooper Reel"))
	assert_eq(w.box_log[-1]["reason"], w.last_reason)


func test_reasons_stay_in_order_per_tier() -> void:
	var w := World.new(2)
	w.add_box("bronze", "first")
	w.add_box("silver", "middle")
	w.add_box("bronze", "second")
	_in_safe_room(w)
	w.open_box("bronze")
	assert_eq(w.last_reason, "first")
	w.open_box("bronze")
	assert_eq(w.last_reason, "second")


func test_sponsor_gift_says_who_sent_it() -> void:
	var w := World.new(4)
	w.showrunner._gain(1000)
	var tier: String = w.boxes[0]
	assert_true("gift from" in w.box_reasons[tier][0].to_lower())


func test_trade_up_gives_the_new_box_its_own_reason() -> void:
	var w := World.new(3)
	for i in range(Loot.TRADE_UP_COST):
		w.add_box("bronze", "b%d" % i)
	_in_safe_room(w)
	assert_true(w.trade_up("bronze"))
	assert_eq(w.box_reasons["bronze"], [])
	assert_true("Traded up" in w.box_reasons["silver"][0])


func test_monsters_drop_from_their_own_pockets() -> void:
	var w := World.new(6)
	w.loot_rng = PyRandom.new(0)
	var drops: Array = []
	for _i in range(60):
		var m := Entities.spawn_monster("goblin", w.player.x + 1, w.player.y)
		w.monsters.append(m)
		m.hp = 0
		w._after_hit(m, "melee")
		var here := Vector2i(m.x, m.y)
		if w.floor_items.has(here):
			drops.append_array(w.floor_items[here])
			w.floor_items.erase(here)
	assert_false(drops.is_empty())
	var pockets: Array = Content.monster("goblin")["drops"]
	for d in drops:
		assert_true(pockets.has(d))
	var rate := float(drops.size()) / 60
	assert_true(0.1 < rate and rate < 0.45)


func test_boxes_only_come_from_achievements_and_sponsors() -> void:
	var w := World.new(5)
	var boss: Monster = null
	for m in w.monsters:
		if m.tier == "headliner":
			boss = m
			break
	boss.hp = 0
	w._after_hit(boss, "melee")
	var reasons: Array = []
	for rs in w.box_reasons.values():
		reasons.append_array(rs)
	assert_false(reasons.is_empty())
	for r in reasons:
		var ok := false
		for prefix in ["Show Stopper", "First Blood", "A gift from"]:
			ok = ok or String(r).begins_with(prefix)
		assert_true(ok, r)


func test_achievement_event_tells_the_system_why_and_what() -> void:
	var w := World.new(7)
	var said: Array = []
	w.events.subscribe("achievement", func(_n: String, d: Dictionary) -> void: said.append(d))
	w.events.emit("nat20", {"foe": "the goblin", "Foe": "The goblin"})
	assert_false(said.is_empty())
	assert_true(PyMath.truthy(said[0]["why"]))
	assert_true(String(said[0]["reward"]).ends_with("box"))

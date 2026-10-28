extends TestCase
## tests/test_achievement_loot.py: the tests that need only World (S8): box reasons stay in order,
## trade-up gives the new box its own reason, and monsters drop from their own pockets. The tests that
## need the real Achievements or Showrunner are listed in docs/port-plan.md B.1 (T1, T2).


func _in_safe_room(w: World) -> void:
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y


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

extends TestCase
## tests/test_floors.py: the parts that need only World A (S6) and the Headliner's key, Act rewards and
## wandering monsters (S7). The timed-stairs test and the `descend` asserts are in docs/port-plan.md B.1 (S8).


func test_floors_are_big_with_three_stairwells() -> void:
	var w := World.new(1)
	assert_eq([w.floor.width, w.floor.height], [GameConfig.MAP_W, GameConfig.MAP_H])
	assert_eq(w.floor.stairs.size(), GameConfig.STAIRS_PER_FLOOR)


func test_timer_bonus_does_not_delay_the_stairs() -> void:
	var a := World.new(3, null, {"name": "R", "gender": "male", "backstory": "rideshare"})
	var b := World.new(3)
	assert_gt(a.timer, b.timer)
	assert_eq(a.stairs_wait, b.stairs_wait)


## First half of test_acts_per_floor_and_rewards (the _after_hit half is test_act_rewards).
func test_acts_per_floor() -> void:
	var w := World.new(5)
	w.new_floor(4)
	var n := Bosses.acts_per_floor(4)
	var acts: Array = []
	var n_open := 0
	var n_feat := 0
	for m in w.monsters:
		if m.tier == "opening" or m.tier == "featured":
			acts.append(m)
			if m.tier == "opening":
				n_open += 1
			else:
				n_feat += 1
	assert_eq(n_open, n.x)
	assert_eq(n_feat, n.y)
	for m in acts:
		assert_true(m.boss)
		assert_true(Entities.monsters().has(m.base))
		assert_gt(m.max_hp, Entities.monsters()[m.base]["hp"])


func _headliner(w: World) -> Monster:
	for m in w.monsters:
		if m.tier == "headliner":
			return m
	fail_test("no headliner")
	return null


## First half of test_headliner_drops_a_key_that_opens_the_stairs (S7: the kill and the key). The
## `descend` asserts at the end of the pytest test wait for slice S8 (B.1).
func test_headliner_drops_a_key() -> void:
	var w := World.new(4)
	var boss := _headliner(w)
	boss.hp = 0
	w._after_hit(boss, "melee")
	assert_true(w.has_key)
	assert_false(w.stairs_locked)
	assert_false(w.floor_items.get(Vector2i(boss.x, boss.y), []).is_empty())     # and a top-shelf item


## Second half of test_acts_per_floor_and_rewards: the Opening Act's map and the Featured Act's haul.
func test_act_rewards() -> void:
	var w := World.new(5)
	w.new_floor(4)
	var opening: Monster = null
	for m in w.monsters:
		if m.tier == "opening":
			opening = m
			break
	for y in range(w.floor.height):
		var blank := PackedByteArray()
		blank.resize(w.floor.width)
		w.floor.explored[y] = blank
	opening.hp = 0
	w._after_hit(opening, "melee")
	var f := w.floor
	var revealed := 0
	for y in range(f.height):
		for x in range(f.width):
			if f.explored[y][x] != 0:
				revealed += 1
				assert_true(absi(x - opening.x) <= Bosses.MAP_RADIUS and absi(y - opening.y) <= Bosses.MAP_RADIUS)
	assert_gt(revealed, 50)

	var featured: Monster = null
	for m in w.monsters:
		if m.tier == "featured":
			featured = m
			break
	featured.hp = 0
	w._after_hit(featured, "melee")
	assert_eq(w.floor_items[Vector2i(featured.x, featured.y)].size(), 2)


func test_monsters_wander_in_out_of_sight_but_bosses_never_return() -> void:
	var w := World.new(6)
	w.player.max_hp = 10000
	w.player.hp = 10000
	var bosses: Array = []
	var keep: Array = []
	for m in w.monsters:
		if m.boss:
			bosses.append(m.name)
			keep.append(m)
	w.monsters = keep
	var spawned: Array = []
	w.events.subscribe("monster_spawned", func(_n: String, d: Dictionary) -> void: spawned.append(d["monster"]))
	for _i in range(400):
		w._tick_clock()
	assert_false(spawned.is_empty())
	for k in spawned:
		assert_true(Entities.monsters().has(k))
	var after: Array = []
	var non_boss := 0
	for m in w.monsters:
		if m.boss:
			after.append(m.name)
		else:
			non_boss += 1
		assert_false(w.floor.is_safe(m.x, m.y))
	bosses.sort()
	after.sort()
	assert_eq(after, bosses)
	assert_lte(non_boss, w._spawn_cap)

extends TestCase
## tests/test_floors.py, the parts that need only World A (slice S6). The rest (timed stairs, the
## Headliner's key, Act rewards, wandering monsters) is listed in docs/port-plan.md B.1.


func test_floors_are_big_with_three_stairwells() -> void:
	var w := World.new(1)
	assert_eq([w.floor.width, w.floor.height], [GameConfig.MAP_W, GameConfig.MAP_H])
	assert_eq(w.floor.stairs.size(), GameConfig.STAIRS_PER_FLOOR)


func test_timer_bonus_does_not_delay_the_stairs() -> void:
	var a := World.new(3, null, {"name": "R", "gender": "male", "backstory": "rideshare"})
	var b := World.new(3)
	assert_gt(a.timer, b.timer)
	assert_eq(a.stairs_wait, b.stairs_wait)


## First half of test_acts_per_floor_and_rewards (the _after_hit half waits for slice S7).
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

extends TestCase
## Dice (crawler/dice.py). No pytest file covers it beyond test_combat.py, so these pin the
## behaviour the rules rely on, then compare exact tables from Python.


func test_d20_draw_counts() -> void:
	var rng := PyRandom.new(1)
	var r := Dice.d20(rng)
	assert_eq(r[1], [r[0]])
	assert_true(rng.words_used >= 1)
	var adv := Dice.d20(rng, 1)
	assert_eq(adv[0], (adv[1] as Array).max())
	assert_true(rng.words_used >= 3)  # rejection sampling can redraw
	var dis := Dice.d20(rng, -1)
	assert_eq(dis[0], (dis[1] as Array).min())
	assert_true(rng.words_used >= 5)


func test_roll_draws_one_word_per_die_for_small_dice() -> void:
	var rng := PyRandom.new(2)
	assert_eq(Dice.roll(rng, 0, 6), 0)
	assert_eq(rng.words_used, 0)
	var total := Dice.roll(rng, 3, 6)
	assert_true(total >= 3 and total <= 18)


func test_fmt_and_average() -> void:
	assert_eq(Dice.fmt(2, 6), "2d6")
	assert_eq(Dice.fmt(2, 6, 3), "2d6+3")
	assert_eq(Dice.fmt(1, 8, -1), "1d8-1")
	assert_eq(Dice.average(2, 6, 3), 10.0)
	assert_eq(Dice.average(1, 4), 2.5)


func test_dice_distribution_is_cached_and_ordered() -> void:
	var a := Dice.dice_distribution(2, 4)
	assert_true(is_same(a, Dice.dice_distribution(2, 4)))
	assert_eq(a.keys(), [2, 3, 4, 5, 6, 7, 8])
	assert_eq(Dice.dice_distribution(0, 6), {0: 1.0})


func test_needed_roll_is_clamped() -> void:
	assert_eq(Dice.needed_roll(100, 11), 2)
	assert_eq(Dice.needed_roll(-100, 11), 20)


func test_tables_match_python() -> void:
	if not S2Support.require(self):
		return
	for row in S2Support.rows("dist"):
		assert_eq(Dice.dice_distribution(row[0], row[1]), row[2], "dist %dd%d" % [row[0], row[1]])
	for row in S2Support.rows("chance_to_hit"):
		var a: Array = row[0]
		assert_eq(Dice.chance_to_hit(a[0], a[1], a[2], a[3]), row[1], "chance_to_hit %s" % str(a))
		assert_eq(Dice.needed_roll(a[0], a[1]), row[2])
	for row in S2Support.rows("average_fmt"):
		var a: Array = row[0]
		assert_eq(Dice.average(a[0], a[1], a[2]), row[1])
		assert_eq(Dice.fmt(a[0], a[1], a[2]), row[2])

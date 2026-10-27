extends TestCase
## Dice combat: d20 + attack bonus vs AC, natural 1s and 20s, damage dice, saves
## (port of tests/test_combat.py). Python's `World(seed=1).player` is S2Support.hero() until World
## is ported (slice S6).


func test_natural_one_misses_and_twenty_hits_whatever_the_numbers() -> void:
	var p := S2Support.hero()
	var m := Entities.spawn_monster("goblin", 1, 0)
	p.attack = 100
	assert_eq(Combat.hit_chance(p, m), 19.0 / 20.0)   # only a natural 1 misses
	p.attack = -100
	assert_eq(Combat.hit_chance(p, m), 1.0 / 20.0)    # only a natural 20 hits


func test_hit_chance_is_five_percent_per_point() -> void:
	# Needing 11+ on a d20 is 50%; each point of bonus is one more face.
	assert_eq(Dice.chance_to_hit(0, 11)[0], 0.5)
	assert_eq(Dice.chance_to_hit(3, 11)[0], 0.65)
	assert_eq(Dice.needed_roll(3, 11), 8)


func test_advantage_matches_two_dice_maths() -> void:
	# Advantage fails only if both dice fail: 1 - (1 - p)^2.
	var p: float = Dice.chance_to_hit(0, 11)[0]
	assert_lt(absf(float(Dice.chance_to_hit(0, 11, 1, 1)[0]) - (1.0 - (1.0 - p) * (1.0 - p))), 1e-12)
	assert_lt(absf(float(Dice.chance_to_hit(0, 11, 1, -1)[0]) - p * p), 1e-12)


func test_wider_crit_range_crits_more() -> void:
	assert_eq(Dice.chance_to_hit(0, 99, 1)[1], 1.0 / 20.0)
	assert_eq(Dice.chance_to_hit(0, 99, 4)[1], 4.0 / 20.0)


func test_dice_distribution_sums_to_one_and_has_the_right_mean() -> void:
	var dist := Dice.dice_distribution(3, 6)
	var probs: Array = dist.values()
	assert_lt(absf(PyMath.fsum_py(probs) - 1.0), 1e-12)
	var weighted: Array = []
	for t in dist:
		weighted.append(t * dist[t])
	assert_lt(absf(PyMath.fsum_py(weighted) - 10.5), 1e-12)


func test_simulated_damage_matches_expected() -> void:
	var rng := PyRandom.new(42)
	var p := S2Support.hero()
	var m := Entities.spawn_monster("skeleton", 1, 0)
	m.max_hp = 1000000000
	var n := 40000
	var total := 0
	for _i in range(n):
		m.hp = m.max_hp
		total += Combat.attack(p, m, rng).damage
	assert_lt(absf(float(total) / n - Combat.expected_damage(p, m)), 0.05)


func test_damage_reduction_never_takes_a_hit_below_one() -> void:
	var rng := PyRandom.new(1)
	var p := S2Support.hero()
	var m := Entities.spawn_monster("goblin", 1, 0)
	m.dr = 999
	p.attack = 100
	for _i in range(50):
		m.hp = m.max_hp
		var res := Combat.attack(p, m, rng)
		assert_true(not res.hit or res.damage == 1)


func test_attack_result_reports_the_roll() -> void:
	var rng := PyRandom.new(3)
	var p := S2Support.hero()
	var m := Entities.spawn_monster("goblin", 1, 0)
	var res := Combat.attack(p, m, rng)
	assert_true(1 <= res.roll and res.roll <= 20 and res.total == res.roll + p.attack and res.target == m.ac)
	assert_true(res.dice_text().contains("vs AC %d" % m.ac))


func test_saving_throw_and_d20_bounds() -> void:
	var rng := PyRandom.new(5)
	for _i in range(200):
		var r := Dice.d20(rng, 1)
		var face: int = r[0]
		var rolls: Array = r[1]
		assert_true(face == rolls.max() and 1 <= face and face <= 20)
	var st := Combat.saving_throw(rng, 100, 10)
	assert_eq(st[0], st[1] != 1)


func test_level_up_gives_attribute_points_not_stats() -> void:
	var p := Entities.new_player(0, 0)
	var pts := p.stat_points
	assert_eq(p.gain_xp(p.xp_to_next()), [2])
	assert_eq(p.stat_points, pts + 2)


# --- Extra pins from reading combat.py (no pytest equivalent) --------------------------------

func test_attack_result_natural_and_text() -> void:
	assert_eq(AttackResult.new(true, true, 3, false, 20, 22, 11).natural(), "20")
	assert_eq(AttackResult.new(false, false, 0, false, 1, 3, 11).natural(), "1")
	assert_eq(AttackResult.new(false, false, 0, false, 7, 9, 11).natural(), "")
	assert_eq(AttackResult.new(true, false, 4, false, 14, 17, 12).dice_text(), "d20 14+3=17 vs AC 12")
	assert_eq(AttackResult.new(false, false, 0, false, 14, 12, 12).dice_text(), "d20 14-2=12 vs AC 12")


func test_advantage_draws_two_dice_and_sure_always_hits() -> void:
	var rng := PyRandom.new(9)
	Dice.d20(rng, 1)
	assert_true(rng.words_used >= 2)
	var p := S2Support.hero()
	p.attack = -100
	var m := Entities.spawn_monster("goblin", 1, 0)
	var res := Combat.attack(p, m, rng, 1, true)
	assert_true(res.hit)
	assert_true(res.damage >= 1)

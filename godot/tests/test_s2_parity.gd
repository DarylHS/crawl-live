extends TestCase
## Per-seed parity for slice S2 against Python: scripts/make_fixtures_s2.py runs, for seeds 0-199,
## a scripted sequence of dice rolls, attacks (player vs every monster kind at depths 1-6, monsters
## vs player, pets, mult / sure / bonus / crit_bonus / advantage variants), saving throws, odds
## (hit_chance, crit_chance, expected_damage), gain_xp and entity helpers. Each step here replays the
## recorded arguments and compares every result field, the PyRandom words_used and the state digest
## (first 16 hex digits) after the step.

var _mismatches := 0
var _steps := 0


## Execute one step on `rng` and return its result list, as run_step in make_fixtures_s2.py does.
func _run_step(rng: PyRandom, step: Array) -> Array:
	match step[0]:
		"d20":
			var r := Dice.d20(rng, step[1])
			return [r[0], r[1]]
		"roll":
			return [Dice.roll(rng, step[1], step[2])]
		"save":
			var st := Combat.saving_throw(rng, step[1], step[2])
			return [st[0], st[1]]
		"attack":
			var a := S2Support.build(step[1])
			var d := S2Support.build(step[2])
			var res := Combat.attack(a, d, rng, float(step[3]), step[4], step[5], step[6], step[7])
			return [res.hit, res.crit, res.damage, res.killed, res.roll, res.total, res.target,
				res.natural(), res.dice_text(), d.hp, d.alive]
		"odds":
			var a := S2Support.build(step[1])
			var d := S2Support.build(step[2])
			return [Combat.hit_chance(a, d), Combat.hit_chance(a, d, step[3]),
				Combat.crit_chance(a), Combat.crit_chance(a, step[3]),
				Combat.expected_damage(a, d), Combat.expected_damage(a, d, float(step[4]), step[5])]
		"xp":
			var e := S2Support.build(step[1])
			var gained: Array = e.gain_xp(step[2])
			var out: Array = [gained, e.level, e.xp, e.xp_to_next()]
			if step[1][0] == "player":
				return out + [e.stat_points]
			return out + [e.max_hp, e.hp, e.attack, e.ac, e.dmg_bonus]
		"entity":
			var e := S2Support.build(step[1])
			var out: Array = [e.to_dict(), e.damage_text(), e.alive]
			if step[1][0] == "monster":
				out += [e.the, e.The, e.a, Entities.init_mod(e)]
			elif step[1][0] == "pet":
				out += [Entities.init_mod(e), e.xp_to_next()]
			else:
				out += [e.xp_to_next()]
			var dealt := e.take_damage(step[2])
			out += [dealt, e.hp, e.alive]
			var healed := e.heal(step[3])
			out += [healed, e.hp]
			return out
	push_error("unknown step kind %s" % str(step[0]))
	return []


func _check_seed(seed_value: int) -> String:
	var node: Dictionary = S2Support.doc()["seeds"][seed_value]
	assert_eq(int(node["seed"]), seed_value)
	var rng := PyRandom.new(seed_value)
	var i := 0
	for enc_step in node["steps"]:
		var rec: Array = PyFixtures.decode(enc_step)
		var step: Array = rec[0]
		var got: Array = [step, _run_step(rng, step), rng.words_used, rng.state_digest().substr(0, 16)]
		_steps += 1
		var diff := TestCase.strict_diff(got, rec)
		if diff != "":
			_mismatches += 1
			return "seed %d step %d (%s): %s" % [seed_value, i, step[0], diff]
		i += 1
	return ""


func test_seeds_0_to_199() -> void:
	if not S2Support.require(self):
		return
	var seeds: Array = S2Support.doc()["seeds"]
	assert_eq(seeds.size(), 200)
	var first_failures: Array = []
	for s in range(seeds.size()):
		var msg := _check_seed(s)
		if msg != "" and first_failures.size() < 5:
			first_failures.append(msg)
	assert_eq(first_failures, [], "mismatching seeds (%d steps checked, %d mismatches)" % [_steps, _mismatches])
	assert_eq(_mismatches, 0)
	assert_eq(_steps, 200 * 48)
	gut.p("S2 parity: %d steps over %d seeds, %d mismatches" % [_steps, seeds.size(), _mismatches])

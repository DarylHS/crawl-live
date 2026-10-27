extends TestCase
## tests/test_loot.py, the parts that need no World (data and odds). The two box-opening tests
## (test_box_opens_only_in_safe_room, test_open_box_needs_space_and_ownership) wait for slice S8.


func test_five_tiers_four_items_each() -> void:
	assert_eq(Loot.TIERS, Content.table("loot_boxes").keys())
	assert_eq(Loot.TIERS.size(), 5)
	for tier in Loot.TIERS:
		var table: Array = Content.box(tier)["table"]
		assert_eq(table.size(), 4)
		for row in table:
			assert_true(Items.items().has(row["item"]) and row["weight"] > 0)
		var ps: Array = []
		for r in Loot.odds(tier):
			ps.append(r[1])
		assert_almost_eq(PyMath.fsum_py(ps), 1.0, 1e-6)


func test_roll_matches_stated_odds() -> void:
	var rng := PyRandom.new(1)
	var n := 20000
	for tier in Loot.TIERS:
		var seen := {}
		for i in range(n):
			var k := Loot.roll_box(tier, rng)
			seen[k] = seen.get(k, 0) + 1
		for r in Loot.odds(tier):
			assert_almost_eq(float(seen.get(r[0], 0)) / n, r[1], 0.02)


func test_higher_tiers_are_better_on_average() -> void:
	var worth := func(k: String) -> float:
		var it: Dictionary = Items.items()[k]
		var dice := 0.0
		if it.has("dice"):
			dice = Dice.average(it["dice"][0], it["dice"][1])
		if it["kind"] == "bomb":
			return dice / 3
		return dice * 2 + it.get("hit", 0) + it.get("ac", 0) * 2 + float(it.get("heal", 0)) / 5
	var ev: Array = []
	for t in Loot.TIERS:
		var terms: Array = []
		for r in Loot.odds(t):
			terms.append(r[1] * worth.call(r[0]))
		ev.append(PyMath.fsum_py(terms))
	var sorted_ev := ev.duplicate()
	sorted_ev.sort()
	assert_eq(ev, sorted_ev)
	assert_lt(ev[0], ev[-1])

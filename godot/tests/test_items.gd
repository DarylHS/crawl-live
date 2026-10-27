extends TestCase
## tests/test_items.py, the part that needs no World: test_item_data_is_consistent. The rest wait
## for slice S8 (docs/port-plan.md B.1).


func test_item_data_is_consistent() -> void:
	var items := Items.items()
	assert_gte(items.size(), 15)
	var kinds := {}
	for k in items:
		kinds[items[k]["kind"]] = true
	var got: Array = kinds.keys()
	got.sort()
	assert_eq(got, ["armour", "bomb", "junk", "potion", "weapon"])
	for depth in range(1, GameConfig.NUM_FLOORS + 1):
		var t := Items.floor_loot_table(depth)
		assert_false((t[0] as Array).is_empty())
		for k in t[0]:
			assert_true(items.has(k))
		for w in t[1]:
			assert_gt(w, 0)

extends TestCase
## tests/test_items.py: test_item_data_is_consistent (S4) and test_new_floors_scatter_items (S6). The
## rest wait for slice S8 (docs/port-plan.md B.1).


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


func test_new_floors_scatter_items() -> void:
	var seen := 0
	for s in range(10):
		seen += World.new(s).floor_items.size()
	assert_gt(seen, 10)

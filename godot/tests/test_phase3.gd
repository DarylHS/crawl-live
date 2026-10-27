extends TestCase
## tests/test_phase3.py, the parts that need no World. The rest (pets, classes, bosses on a floor,
## crafting at the bench, saves) is listed in docs/port-plan.md B.1.


func test_recipes_reference_real_items() -> void:
	var recipes := Crafting.recipes()
	assert_eq(recipes.size(), 4)
	for r in recipes:
		assert_true(Items.items().has(r["makes"]))
		for k in r["needs"]:
			assert_true(Items.items().has(k))


func test_can_craft_counts_duplicates() -> void:
	var recipe: Dictionary = Crafting.recipes()[0]
	assert_true(Crafting.can_craft(recipe, ["mug", "x", "sock"]))
	assert_false(Crafting.can_craft(recipe, ["sock"]))
	var twin := {"needs": ["sock", "sock"]}
	assert_false(Crafting.can_craft(twin, ["sock", "mug"]))
	assert_true(Crafting.can_craft(twin, ["sock", "mug", "sock"]))

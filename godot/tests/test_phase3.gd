extends TestCase
## tests/test_phase3.py: the data tests (S4) and the World init and floor tests (S6). The rest (pet
## and boss fights, skills, crafting at the bench, saves) is listed in docs/port-plan.md B.1.


## Chebyshev distance between two entities (crawler/ai.py cheb; ai.gd arrives with slice S7).
func _cheb(a: Entity, b: Entity) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))



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


# --- Pet ----------------------------------------------------------------------

func test_pet_starts_next_to_player_and_follows_floors() -> void:
	var w := World.new(1, ["dog", "Rex"])
	assert_eq(w.pet.name, "Rex")
	assert_eq(_cheb(w.pet, w.player), 1)
	w.new_floor(2)
	assert_eq(_cheb(w.pet, w.player), 1)


func test_default_pet_name() -> void:
	assert_eq(World.new(1, ["cat", ""]).pet.name, Content.pet("cat")["default_name"])


# --- Classes and skills ---------------------------------------------------------

func test_class_choice_offered_on_floor_three() -> void:
	var w := World.new(8)
	w.new_floor(World.CHOICE_FLOOR - 1)
	assert_false(w.pending_choice)
	w.new_floor(World.CHOICE_FLOOR)
	assert_true(w.pending_choice)
	var p := w.player
	var hp := p.max_hp
	var ac := p.ac
	var hit := p.attack
	assert_true(w.choose_class("elf", "analyst"))      # DEX 10 -> 13, CON 10 -> 8, plus flat bonuses
	var an: Dictionary = Content.klass("analyst")
	assert_false(w.pending_choice)
	assert_eq(p.ac, ac + 1 + an.get("ac", 0))
	assert_eq(p.max_hp, hp - p.level)
	assert_eq(p.attack, hit + an["hit"])
	assert_false(w.choose_class("human", "brawler"))   # only once


# --- Bosses ----------------------------------------------------------------------

func test_one_boss_per_floor_by_the_furthest_stairs(depth = use_parameters(range(1, GameConfig.NUM_FLOORS + 1))) -> void:
	var w := World.new(12)
	w.new_floor(depth)
	var bosses: Array = []
	var tiers: Array = []
	for m in w.monsters:
		if m.tier == "headliner":
			bosses.append(m)
		if m.boss:
			tiers.append(m.tier)
	assert_eq(bosses.size(), 1)
	assert_eq(bosses[0].name, Content.boss(depth)["name"])
	var n := Bosses.acts_per_floor(depth)
	assert_lte(tiers.count("opening"), n.x)
	assert_lte(tiers.count("featured"), n.y)
	assert_gte(tiers.count("opening") + tiers.count("featured"), 1)
	var s: Vector2i = w.floor.stairs[-1]
	var room: DungeonRoom = null
	for r in w.floor.rooms:
		if r.contains(s.x, s.y):
			room = r
			break
	assert_true(room.contains(bosses[0].x, bosses[0].y))


# --- Budgie and mouse (companions) --------------------------------------------------

func test_four_companions_each_with_quips() -> void:
	var species: Array = Content.table("pets").keys()
	species.sort()
	assert_eq(species, ["budgie", "cat", "dog", "mouse"])
	for sp in Content.table("pets"):
		var quips: Dictionary = Content.table("pet_quips")[sp]
		for k in ["kill", "ability", "level_up", "downed"]:
			assert_false((quips[k] as Array).is_empty(), "%s %s" % [sp, k])
		var w := World.new(1, [sp, ""])
		assert_eq(w.pet.name, Content.pet(sp)["default_name"])

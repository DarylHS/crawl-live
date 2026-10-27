extends TestCase
## tests/test_encounter.py, the part that needs no World: initiative ordering with ties. The other
## tests are in docs/port-plan.md B.1 (slices S7, S8, T5, T6).


func test_initiative_ties_go_to_the_higher_modifier_then_the_player() -> void:
	var player: Entity = Entities.new_player(0, 0)
	var a: Entity = Entities.spawn_monster("goblin", 0, 0)
	var b: Entity = Entities.spawn_monster("gnawer", 0, 0)
	var enc := Encounter.new(player)
	enc.add(b, 12, 0)                   # 12, same modifier as you: you go first
	enc.add(player, 10, 2)
	enc.add(a, 8, 4)                    # 12 with a higher modifier: goes first
	assert_eq(enc.entities.size(), 3)
	assert_true(is_same(enc.entities[0], a) and is_same(enc.entities[1], player) and is_same(enc.entities[2], b))
	assert_eq(enc.before(player).size(), 1)
	assert_true(is_same(enc.before(player)[0], a))
	assert_eq(enc.after(player).size(), 1)
	assert_true(is_same(enc.after(player)[0], b))


func test_adding_twice_changes_nothing_and_budget_ends_the_turn() -> void:
	var player: Entity = Entities.new_player(0, 0)
	var g: Entity = Entities.spawn_monster("goblin", 0, 0)
	var enc := Encounter.new(player)
	enc.add(g, 5, 1)
	enc.add(g, 20, 9)
	assert_eq(enc.total(g), 6)
	assert_eq(enc.monsters.size(), 1)
	assert_true(enc.can_react(g))
	enc.react(g)
	assert_false(enc.can_react(g))
	enc.ready(g)
	assert_true(enc.can_react(g))
	assert_false(enc.turn_over)
	enc.spend("move")
	enc.spend("action")
	assert_true(enc.turn_over)
	enc.reset_budget()
	assert_true(enc.has("bonus") and not enc.turn_over)
	enc.remove(g)
	assert_false(enc.has_entity(g))

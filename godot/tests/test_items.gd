extends TestCase
## tests/test_items.py: every test (S4 data, S6 floors, S8 pickup, equip, potions, bombs, drops).


## pytest fixture `w`: World(seed=11) with monsters and floor items cleared.
var w: World


func before_each() -> void:
	w = World.new(11)
	w.monsters.clear()
	w.floor_items.clear()


func after_each() -> void:
	TestHelpers.restore_patches()


func _in_safe() -> void:
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	w.update_fov()


## The first NEIGHBOURS_8 step the player can walk.
func _walkable_step() -> Vector2i:
	for d in DungeonFloor.NEIGHBOURS_8:
		if w.floor.walkable(w.player.x + d.x, w.player.y + d.y):
			return d
	fail_test("player boxed in")
	return Vector2i()


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
		for wt in t[1]:
			assert_gt(wt, 0)


func test_new_floors_scatter_items() -> void:
	var seen := 0
	for s in range(10):
		seen += World.new(s).floor_items.size()
	assert_gt(seen, 10)


func test_pickup_and_drop() -> void:
	var p := w.player
	var here := Vector2i(p.x, p.y)
	w.floor_items[here] = ["tonic", "sock"]
	assert_true(w.pickup())
	assert_eq(w.inventory, ["tonic", "sock"])
	assert_false(w.floor_items.has(here))
	assert_false(w.pickup())                       # nothing left
	assert_true(w.drop(0))
	assert_eq(w.inventory, ["sock"])
	assert_eq(w.floor_items[here], ["tonic"])


func test_pickup_respects_pack_size() -> void:
	w.inventory = []
	for _i in range(GameConfig.INVENTORY_SIZE):
		w.inventory.append("sock")
	w.floor_items[Vector2i(w.player.x, w.player.y)] = ["tonic"]
	assert_false(w.pickup())
	assert_eq(w.inventory.size(), GameConfig.INVENTORY_SIZE)


func test_equip_swaps_and_changes_stats() -> void:
	var p := w.player
	var hit := p.attack
	assert_eq([p.dmg_n, p.dmg_die], [1, 4])           # fists
	w.inventory = ["pan", "katana"]
	w.equip(0)
	assert_eq(p.dmg_die, 6)
	assert_eq(w.equipment["weapon"], "pan")
	w.equip(0)                                       # katana replaces the pan
	assert_eq(p.dmg_die, 10)
	assert_eq(p.attack, hit + Items.items()["katana"]["hit"])
	assert_eq(w.inventory, ["pan"])
	assert_true(w.unequip("weapon"))
	assert_eq(p.dmg_die, 4)
	assert_eq(p.attack, hit)
	var inv := w.inventory.duplicate()
	inv.sort()
	assert_eq(inv, ["katana", "pan"])


func test_potion_heals_and_takes_a_turn() -> void:
	w.player.hp = 5
	w.inventory = ["tonic"]
	var turn := w.turn
	assert_true(w.use_item(0))
	assert_gte(w.player.hp, 5 + Items.items()["tonic"]["heal"])
	assert_eq(w.inventory, [])
	assert_eq(w.turn, turn + 1)


func test_potion_refused_at_full_health() -> void:
	w.inventory = ["tonic"]
	assert_false(w.use_item(0))
	assert_eq(w.inventory, ["tonic"])


func test_bomb_hits_blast_radius_only() -> void:
	var p := w.player
	var near := _walkable_step()
	var a := Entities.spawn_monster("goblin", p.x + near.x, p.y + near.y)
	a.hp = 1                                         # dies even if it makes its save
	var far := Entities.spawn_monster("goblin", a.x + 5, a.y + 5)   # outside the blast; position is never walked
	w.monsters.append(a)
	w.monsters.append(far)
	w.visible = {Vector2i(a.x, a.y): true}
	w.inventory = ["popper"]
	var kills: Array = []
	w.events.subscribe("bomb", func(_n: String, d: Dictionary) -> void: kills.append(d["kills"]))
	assert_true(w.use_item(0))
	assert_false(w.monsters.has(a))
	assert_true(w.monsters.has(far))
	assert_eq(far.hp, far.max_hp)
	assert_eq(kills, [1])


func test_bomb_needs_a_target_and_no_safe_room() -> void:
	w.inventory = ["popper"]
	assert_false(w.use_item(0))
	assert_eq(w.inventory, ["popper"])
	_in_safe()
	assert_false(w.use_item(0))


func test_junk_is_not_usable() -> void:
	w.inventory = ["sock"]
	assert_false(w.use_item(0))
	assert_eq(w.inventory, ["sock"])


func test_monster_drops_use_loot_rng() -> void:
	TestHelpers.patch_static(GameConfig, "ITEM_DROP_CHANCE", 1.0)
	var p := w.player
	var d := _walkable_step()
	var m := Entities.spawn_monster("gnawer", p.x + d.x, p.y + d.y)
	m.hp = 1
	w.monsters.append(m)
	p.attack = 100
	w.move_player(d.x, d.y)
	assert_eq(w.floor_items.get(Vector2i(m.x, m.y), []).size(), 1)

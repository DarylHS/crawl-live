extends TestCase
## tests/test_phase3.py: the data tests (S4), the World init and floor tests (S6) and the pet, boss and
## ranged-monster tests that need attacks and Ai (S7), then skills, crafting at the bench and the pet
## command and revive (S8). Saves are listed in docs/port-plan.md B.1.


## Chebyshev distance between two entities (crawler/ai.py cheb).
func _cheb(a: Entity, b: Entity) -> int:
	return Ai.cheb(a, b)



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


# --- S7: pets and monsters in action (Ai), boss kills ---------------------------------

func _clear(w: World) -> void:
	w.monsters.clear()
	w.floor_items.clear()


## Free walkable non-safe tiles within `radius` of (x, y), in Python's order (dx outer, dy inner).
func _free_tiles_near(w: World, x: int, y: int, radius: int) -> Array:
	var taken := {}
	for m in w.monsters:
		taken[Vector2i(m.x, m.y)] = true
	taken[Vector2i(w.player.x, w.player.y)] = true
	if w.active_pet != null:
		taken[Vector2i(w.pet.x, w.pet.y)] = true
	var out: Array = []
	for dx in range(-radius, radius + 1):
		for dy in range(-radius, radius + 1):
			if w.floor.walkable(x + dx, y + dy) and not w.floor.is_safe(x + dx, y + dy) \
					and not taken.has(Vector2i(x + dx, y + dy)):
				out.append(Vector2i(x + dx, y + dy))
	return out


func _headliner(w: World) -> Monster:
	for m in w.monsters:
		if m.tier == "headliner":
			return m
	fail_test("no headliner")
	return null


## (S8 range, pulled forward with move_player.)
func test_swap_places_with_pet() -> void:
	var w := World.new(2, ["dog", "Rex"])
	_clear(w)
	var p := w.player
	var pet := w.pet
	var target := Vector2i(pet.x, pet.y)
	assert_true(w.move_player(pet.x - p.x, pet.y - p.y))
	assert_eq(Vector2i(p.x, p.y), target)


func test_pet_attacks_adjacent_monster_and_earns_xp() -> void:
	var w := World.new(3, ["dog", "Rex"])
	_clear(w)
	var pet := w.pet
	var spot: Vector2i = _free_tiles_near(w, pet.x, pet.y, 1)[0]
	var m := Entities.spawn_monster("gnawer", spot.x, spot.y)
	m.hp = 1
	w.monsters.append(m)
	pet.attack = 100
	w.wait()
	assert_false(w.monsters.has(m))
	assert_eq(pet.kills, 1)
	assert_gt(pet.xp, 0)


func test_cat_pounces_from_range() -> void:
	var w := World.new(4, ["cat", "Tom"])
	_clear(w)
	var pet := w.pet
	var spot := Vector2i(-1, -1)
	for s in _free_tiles_near(w, pet.x, pet.y, 3):
		if maxi(absi(s.x - pet.x), absi(s.y - pet.y)) == 3:
			spot = s
			break
	var m := Entities.spawn_monster("golem", spot.x, spot.y)
	w.monsters.append(m)
	w.visible = {Vector2i(m.x, m.y): true}
	Ai.take_pet_turn(w)
	assert_eq(Ai.cheb(pet, m), 1)
	assert_eq(pet.cooldown, Content.pet("cat")["cooldown"])


func test_dog_licks_wounds() -> void:
	var w := World.new(5, ["dog", "Rex"])
	_clear(w)
	w.player.hp = 5
	w.wait()
	assert_gt(w.player.hp, 6)
	assert_gt(w.pet.cooldown, 0)


func test_boss_kill_awards_box_achievement_and_viewers() -> void:
		var w := World.new(13)
	var boss := _headliner(w)
	var viewers := w.viewers
	var kills: Array = []
	w.events.subscribe("boss_kill", func(_n: String, d: Dictionary) -> void: kills.append(d))
	boss.hp = 0
	w._after_hit(boss, "melee")
	assert_false(w.monsters.has(boss))
	assert_eq(kills.size(), 1)
	assert_eq(kills[0]["boss"], boss.name)
	assert_true(w.has_key)
	assert_eq(w.player.kills, 1)
	assert_gte(w.viewers, viewers + 150)
	var box: String = Content.boss(1)["box"]
	assert_true(w.boxes.has(box))
	assert_true(w.achievements.unlocked.has("headliner_1"))
	var found := false
	for r in w.box_reasons[box]:
		found = found or Content.boss(1)["name"] in r
	assert_true(found)


func test_final_boss_phase_two_calls_for_help() -> void:
	var w := World.new(14)
	w.new_floor(GameConfig.NUM_FLOORS)
	var boss := _headliner(w)
	var count := w.monsters.size()
	var bonus := boss.dmg_bonus
	boss.hp = PyMath.floordiv(boss.max_hp, 2)
	w._after_hit(boss, "melee")
	assert_eq(boss.phase, 2)
	assert_gt(boss.dmg_bonus, bonus)
	assert_ne(boss.ranged, 0)
	assert_gt(w.monsters.size(), count)
	w._after_hit(boss, "melee")                          # no second trigger
	assert_eq(boss.phase, 2)


func test_ranged_monster_shoots_from_distance() -> void:
	var w := World.new(15)
	_clear(w)
	var p := w.player
	var spot := Vector2i(-1, -1)
	for s in _free_tiles_near(w, p.x, p.y, 4):
		if maxi(absi(s.x - p.x), absi(s.y - p.y)) >= 3:
			spot = s
			break
	var m := Entities.spawn_monster("cultist", spot.x, spot.y)
	m.attack = 100
	w.monsters.append(m)
	var hp := p.hp
	for _i in range(10):
		w.visible[Vector2i(m.x, m.y)] = true
		Ai.take_monster_turns(w)                # it notices you and joins combat...
		if w.combat != null and w.combat.has_entity(m):
			Ai.take_combat_turn(w, m)           # ...then acts on its turn in the order
	assert_lt(p.hp, hp)


func test_budgie_squawk_stuns_nearby_monsters() -> void:
	var w := World.new(20, ["budgie", "Pickles"])
	_clear(w)
	var p := w.player
	var spots := _free_tiles_near(w, p.x, p.y, 2).slice(0, 2)
	var ms: Array = []
	for s in spots:
		ms.append(Entities.spawn_monster("golem", s.x, s.y))
	w.monsters.append_array(ms)
	for m in ms:
		w.visible[Vector2i(m.x, m.y)] = true
	Ai.take_pet_turn(w)
	for m in ms:
		assert_eq(m.stunned, 2)
	assert_eq(w.pet.cooldown, Content.pet("budgie")["cooldown"])
	var where: Array = []
	for m in ms:
		where.append(Vector2i(m.x, m.y))
	Ai.take_monster_turns(w)
	var after: Array = []
	for m in ms:
		after.append(Vector2i(m.x, m.y))
		assert_eq(m.stunned, 1)
	assert_eq(after, where)


func test_mouse_dirty_trick_on_wounded_monster() -> void:
	var w := World.new(21, ["mouse", "Skritch"])
	_clear(w)
	var pet := w.pet
	var spot: Vector2i = _free_tiles_near(w, pet.x, pet.y, 1)[0]
	var m := Entities.spawn_monster("golem", spot.x, spot.y)
	m.hp = PyMath.floordiv(m.max_hp, 2)
	w.monsters.append(m)
	pet.attack = 100
	for _i in range(5):                       # 95% hit cap
		if pet.cooldown != 0:
			break
		Ai.take_pet_turn(w)
	assert_eq(pet.cooldown, Content.pet("mouse")["cooldown"])


func test_mouse_runs_away_when_hurt() -> void:
	var w := World.new(22, ["mouse", "Skritch"])
	_clear(w)
	var pet := w.pet
	var p := w.player
	var far := Vector2i(-1, -1)
	var far_d := -1
	for s in _free_tiles_near(w, p.x, p.y, 4):
		var d := maxi(absi(s.x - p.x), absi(s.y - p.y))
		if d > far_d:                         # max(): the first largest wins
			far_d = d
			far = s
	pet.x = far.x
	pet.y = far.y
	var spot: Vector2i = _free_tiles_near(w, pet.x, pet.y, 1)[0]
	var m := Entities.spawn_monster("gnawer", spot.x, spot.y)
	w.monsters.append(m)
	pet.hp = 2
	var before := Ai.cheb(pet, p)
	var flees: Array = []
	w.events.subscribe("pet_flee", func(_n: String, d: Dictionary) -> void: flees.append(d))
	Ai.take_pet_turn(w)
	assert_lt(Ai.cheb(pet, p), before)
	assert_eq(m.hp, m.max_hp)
	assert_eq(flees.size(), 1)
	var said := false
	for line in w.messages.recent(5):
		if "Skritch:" in line[0]:
			said = true
	assert_true(said)


func test_boss_names_read_naturally() -> void:
	var w := World.new(23)
	var boss := _headliner(w)
	w.player.hp = 1
	w.player.ac = -100
	for _i in range(40):
		if w.state == "dead":
			break
		w.monster_attack(boss)
	assert_eq(w.death_cause, "Killed by %s on floor 1" % boss.name)
	var parts := PackedStringArray()
	for line in w.messages.recent(50):
		parts.append(line[0])
	var text := " ".join(parts)
	assert_false(text.contains("The The"))
	assert_false(text.contains("a The"))
	var m := Entities.spawn_monster("goblin", 0, 0)
	assert_eq([m.the, m.The, m.a], ["the Knockoff Goblin", "The Knockoff Goblin", "a Knockoff Goblin"])


func test_following_pet_joins_the_players_fight() -> void:
	var w := World.new(24, ["dog", "Rex"])
	_clear(w)
	var p := w.player
	var pet := w.pet
	# A monster next to the player but not next to the pet.
	var spot := Vector2i(-1, -1)
	for s in _free_tiles_near(w, p.x, p.y, 1):
		if maxi(absi(s.x - pet.x), absi(s.y - pet.y)) >= 2:
			spot = s
			break
	var m := Entities.spawn_monster("golem", spot.x, spot.y)
	m.stunned = 99                                      # keep it still
	w.monsters.append(m)
	w.visible[spot] = true
	for _i in range(4):
		Ai.take_pet_turn(w)
	assert_eq(Ai.cheb(pet, m), 1)


# --- S8: descend, pet commands, skills, crafting ------------------------------------------------

func test_monsters_never_stand_on_the_pet() -> void:
	var w := World.new(7, ["cat", "Tom"])
	w.player.max_hp = 10000
	w.player.hp = 10000
	var rng := PyRandom.new(7)
	for _i in range(1500):
		if w.state != "playing":
			break
		if w.on_stairs and not w.exit_sealed and rng.random() < 0.5:
			w.descend()
		else:
			var d: Vector2i = rng.choice(DungeonFloor.NEIGHBOURS_8)
			w.move_player(d.x, d.y)
		var pet := w.active_pet
		if pet != null:
			for m in w.monsters:
				assert_ne(Vector2i(m.x, m.y), Vector2i(pet.x, pet.y))


func test_pet_command_cycles_modes() -> void:
	var w := World.new(3, ["cat", "Tom"])
	var modes: Array = [w.pet.mode]
	for _i in range(3):
		w.command_pet()
		modes.append(w.pet.mode)
	assert_eq(modes, ["follow", "attack", "stay", "follow"])


func test_pet_downed_then_revived_in_safe_room() -> void:
	var w := World.new(6, ["dog", "Rex"])
	_clear(w)
	var pet := w.pet
	var spot: Vector2i = _free_tiles_near(w, pet.x, pet.y, 1)[0]
	var m := Entities.spawn_monster("stalker", spot.x, spot.y)
	m.attack = 100
	m.alerted = true
	w.monsters.append(m)
	pet.hp = 1
	for _i in range(20):                             # hit chance caps at 95%
		if not pet.downed:
			w.monster_attack_pet(m)
	assert_true(pet.downed)
	assert_null(w.active_pet)
	w.monsters.clear()
	assert_false(w.revive_pet())                     # not in a safe room
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	var before := w.timer
	assert_true(w.revive_pet())
	assert_false(pet.downed)
	assert_eq(pet.hp, pet.max_hp)
	assert_eq(before - w.timer, GameConfig.PET_REVIVE_TURNS)


func test_skill_needs_a_class_and_respects_cooldown() -> void:
	var w := World.new(9)
	_clear(w)
	assert_false(w.use_skill())
	w.choose_class("human", "analyst")
	assert_true(w.use_skill())
	assert_gt(w.scout_turns, 0)
	assert_false(w.use_skill())                      # recharging
	for _i in range(30):
		w.wait()
	assert_eq(w.skill_cooldown, 0)
	assert_eq(w.scout_turns, 0)


func test_haymaker_always_hits_double() -> void:
	var w := World.new(10)
	_clear(w)
	w.choose_class("human", "brawler")
	var spot: Vector2i = _free_tiles_near(w, w.player.x, w.player.y, 1)[0]
	var m := Entities.spawn_monster("golem", spot.x, spot.y)
	m.ac = 100
	w.monsters.append(m)
	assert_true(w.use_skill())
	assert_lt(m.hp, m.max_hp)


func test_arc_bolt_hits_nearest_visible() -> void:
	var w := World.new(11)
	_clear(w)
	w.choose_class("elf", "arcanist")
	var spot: Vector2i = _free_tiles_near(w, w.player.x, w.player.y, 3)[0]
	var m := Entities.spawn_monster("golem", spot.x, spot.y)
	w.monsters.append(m)
	w.visible = {Vector2i(m.x, m.y): true}
	assert_true(w.use_skill())
	assert_eq(m.max_hp - m.hp, 6 + 2 * w.player.level + w.mod("int"))


func test_crafting_in_safe_room_only_and_costs_time() -> void:
	var w := World.new(16)
	_clear(w)
	var recipe: Dictionary = Crafting.recipes()[0]
	w.inventory = (recipe["needs"] as Array).duplicate()
	assert_false(w.craft(0))
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	var before := w.timer
	assert_true(w.craft(0))
	assert_eq(w.inventory, [recipe["makes"]])
	assert_eq(before - w.timer, Crafting.CRAFT_TURNS)
	assert_false(w.craft(0))                         # parts used up

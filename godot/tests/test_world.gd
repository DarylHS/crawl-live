extends TestCase
## World (slice S6: init, traits, refresh_stats, floors and spawns, queries, timer). Slice S7 added the
## kill and collapse tests and slice S8 the descend, rest and random-play smoke tests;
## the S6 parts of the other pytest files live in test_attributes, test_practice, test_items,
## test_phase3 and test_phase4. This file holds World-specific checks and the ownership test.


## Builds a world (optionally with a pet), keeps only weak references and returns them: World, then
## each of its four subsystems. Both strong references die when this function returns.
func _build(pet: Variant) -> Array:
	var w := World.new(5, pet)
	w.new_floor(2)
	assert_true(w.training.world == w)
	assert_true(w.achievements.world == w)
	assert_true(w.showrunner.world == w)
	assert_true(w.funfacts.world == w)
	return [weakref(w), weakref(w.training), weakref(w.achievements), weakref(w.showrunner),
			weakref(w.funfacts), weakref(w.events), weakref(w.shop)]


func test_world_and_all_subsystems_are_freed_when_dropped(pet = use_parameters([null, ["dog", "Rex"]])) -> void:
	var refs := _build(pet)
	var names := ["world", "practice", "achievements", "showrunner", "funfacts", "events", "shop"]
	for i in refs.size():
		assert_null(refs[i].get_ref(), names[i])


func test_subsystems_are_created_once_and_subscribe_in_python_order() -> void:
	var w := World.new(1)
	var training := w.training
	w.new_floor(2)
	assert_true(training == w.training)   # never reassigned
	# Practice subscribes in World.__init__ before anything else; its listeners come first.
	for ev in ["player_attack", "kill", "damage_taken", "step", "item_pickup", "shop_buy", "viewers_gained"]:
		var subs := w.events.subscribers(ev)
		assert_false(subs.is_empty(), ev)
		assert_true(subs[0].get_object() == training, ev)


func test_init_state_after_floor_one() -> void:
	var w := World.new(1)
	assert_eq([w.seed, w.depth, w.turn, w.state, w.hero_name], [1, 1, 0, "playing", "Crawler"])
	assert_eq(w.floor_stats.size(), 1)
	assert_eq(w.floor_stats[0], {"depth": 1, "damage_taken": 0, "gold": 0, "kills": 0,
		"viewers_start": 50, "viewers_end": 50, "contract": null})
	assert_eq([w.viewers, w.timer, w.timer_max], [50, GameConfig.floor_turns(1), GameConfig.floor_turns(1)])
	assert_eq(w.stairs_wait, PyMath.floordiv(GameConfig.floor_turns(1), 2))
	assert_true(w.stairs_locked)
	assert_false(w.exit_sealed)
	assert_false(w.pending_choice)
	assert_null(w.pet)
	assert_null(w.active_pet)
	assert_eq(w.address, "crawler")
	assert_eq([w.player.x, w.player.y], [112, 13])
	assert_false(w.in_safe_room)
	assert_false(w.on_stairs)
	assert_eq(w.messages.lines.size(), 2)
	assert_eq(w.messages.lines[0][0], "Floor 1. It collapses in %s. Find the stairs." % w.timer_text())
	assert_eq(w.weapon_style(), "unarmed")


func test_streams_are_seeded_in_python_order() -> void:
	var w := World.new(77)
	assert_eq(w.loot_rng.words_used, 0)
	assert_eq(w.deal_rng.words_used, 0)
	assert_eq(w.shop.rng.words_used, 0)
	assert_eq(w.showrunner.rng.words_used, 0)
	assert_gt(w.rng.words_used, 0)
	var fresh := PyRandom.new(77 ^ 0x100F)
	assert_eq(w.loot_rng.get_state(), fresh.get_state())
	assert_eq(w.deal_rng.get_state(), PyRandom.new(77 ^ 0xC0DE).get_state())
	assert_eq(w.shop.rng.get_state(), PyRandom.new(77 ^ 0x5A0F).get_state())
	assert_eq(w.showrunner.rng.get_state(), PyRandom.new(77 ^ 0x5EED).get_state())


func test_unseeded_world_draws_a_seed() -> void:
	var w := World.new()
	assert_true(w.seed >= 0 and w.seed < (1 << 30))


func test_timer_text() -> void:
	var w := World.new(1)
	assert_eq(w.timer_text(0), "0h 00m")
	assert_eq(w.timer_text(59), "0h 59m")
	assert_eq(w.timer_text(60), "1h 00m")
	assert_eq(w.timer_text(725), "12h 05m")
	w.timer = 61
	assert_eq(w.timer_text(), "1h 01m")


func test_traits_and_bonuses_come_from_backstory_race_and_class() -> void:
	var w := World.new(2, null, {"name": "T", "gender": "female", "backstory": "tradie"})
	assert_eq(w.hero_name, "T")
	assert_eq(w.address, "madam" if w.get_trait("address") == null else w.get_trait("address"))
	assert_null(w.get_trait("no_such_perk"))
	assert_eq(w.get_trait("no_such_perk", 7), 7)
	assert_eq(w.bonus("max_hp"), Content.backstory("tradie").get("max_hp", 0))
	w.choose_class("dwarf", "brawler")
	assert_eq(w.bonus("max_hp"), Content.backstory("tradie").get("max_hp", 0)
			+ Content.race("dwarf").get("max_hp", 0) + Content.klass("brawler").get("max_hp", 0))
	assert_eq(w.skill, Content.klass("brawler")["skill"])


func test_pet_head_start_trait_buffs_the_pet() -> void:
	for key in Content.table("backstories"):
		if Content.backstory(key).has("pet_head_start"):
			var plain := World.new(1, ["dog", "Rex"])
			var w := World.new(1, ["dog", "Rex"], {"name": "T", "gender": null, "backstory": key})
			assert_gt(w.pet.level, plain.pet.level)
			assert_eq(w.pet.max_hp > plain.pet.max_hp, true)
			return
	pass_test("no backstory has pet_head_start")


func test_floor_layout_invariants(depth = use_parameters(range(1, GameConfig.NUM_FLOORS + 1))) -> void:
	var w := World.new(21)
	w.new_floor(depth)
	assert_eq(w.depth, depth)
	var fl := w.floor
	var seen := {}
	for m in w.monsters:
		var p := Vector2i(m.x, m.y)
		assert_false(seen.has(p), "monsters never share a tile")
		seen[p] = true
		assert_ne(fl.tiles[m.y][m.x], DungeonFloor.STAIRS)
	assert_eq(w.exit_sealed, depth == GameConfig.NUM_FLOORS)
	assert_eq(w.pending_choice, depth >= World.CHOICE_FLOOR)
	assert_true(w.visible.has(Vector2i(w.player.x, w.player.y)))
	assert_eq(w.monster_at(w.monsters[0].x, w.monsters[0].y), w.monsters[0])
	assert_null(w.monster_at(-1, -1))


func test_pet_is_placed_beside_the_player_and_pet_at_finds_it() -> void:
	var w := World.new(3, ["cat", "Tom"])
	assert_true(w.pet_at(w.pet.x, w.pet.y) == w.pet)
	assert_null(w.pet_at(w.pet.x + 50, w.pet.y))
	w.pet.downed = true
	assert_null(w.active_pet)
	assert_null(w.pet_at(w.pet.x, w.pet.y))


func test_contract_accept_and_decline() -> void:
	var w := World.new(4)
	assert_false(w.accept_contract())
	assert_false(w.decline_contract())
	w.pending_offer = "gloop_blitz"
	assert_true(w.decline_contract())
	assert_null(w.pending_offer)
	w.pending_offer = "gloop_blitz"
	assert_true(w.accept_contract())
	assert_eq(w.floor_stats[-1]["contract"], "gloop_blitz")
	assert_eq(Contracts.effect(w, "gold_mult"), Content.table("contracts")["gloop_blitz"]["gold_mult"])


func test_earn_gold_rounds_half_to_even_and_logs_the_floor() -> void:
	var w := World.new(4)
	assert_eq(w._earn_gold(2.5, "test"), 2)
	assert_eq(w._earn_gold(3.5, "test"), 4)
	assert_eq(w._earn_gold(-4.0, "test"), 0)
	assert_eq(w.gold, 6)
	assert_eq(w.floor_stats[-1]["gold"], 6)


func test_toasts_expire() -> void:
	var w := World.new(4)
	w.add_toast("a", "gold")
	w.turn = GameConfig.TOAST_TURNS + 5
	w.add_toast("b", "silver", "sub")
	assert_eq(w.toasts, [[GameConfig.TOAST_TURNS + 5, "b", "silver", "sub"]])


func test_respawn_adds_a_monster_out_of_sight_and_reschedules() -> void:
	var w := World.new(9)
	w.new_floor(2)
	var before := w.monsters.size()
	w._spawn_cap = 1000
	var tries := 0
	while w.monsters.size() == before and tries < 50:
		w._respawn()
		tries += 1
	assert_eq(w.monsters.size(), before + 1)
	var m: Monster = w.monsters[-1]
	assert_false(w.visible.has(Vector2i(m.x, m.y)))
	assert_gt(w._next_spawn, w.turn)


func test_stairs_reachable_on_every_floor() -> void:
	var w := World.new(11)
	for depth in range(1, GameConfig.NUM_FLOORS + 1):
		w.new_floor(depth)
		var dist := w.floor.distance_map(w.player.x, w.player.y)
		for s in w.floor.stairs:
			assert_eq(w.floor.tiles[s.y][s.x], DungeonFloor.STAIRS)
			assert_gt(dist[s.y * w.floor.width + s.x], 0)


# --- S7 (attacks, kills, the clock), plus bump and safe-room tests that need only move_player ---

func _free_neighbour(w: World) -> Vector2i:
	var p := w.player
	for n in DungeonFloor.NEIGHBOURS_8:
		if w.floor.walkable(p.x + n.x, p.y + n.y) and not w.floor.is_safe(p.x + n.x, p.y + n.y):
			return n
	fail_test("player boxed in")
	return Vector2i()


## (S8 range, pulled forward with move_player.)
func test_bump_attack_damages_monster() -> void:
	var w := World.new(3)
	w.monsters.clear()
	var d := _free_neighbour(w)
	var m := Entities.spawn_monster("golem", w.player.x + d.x, w.player.y + d.y)
	w.monsters.append(m)
	w.player.attack = 100
	assert_true(w.move_player(d.x, d.y))
	assert_lt(m.hp, m.max_hp)
	assert_ne(Vector2i(w.player.x, w.player.y), Vector2i(m.x, m.y))


func test_kill_awards_xp_and_emits_event() -> void:
	var w := World.new(4)
	w.monsters.clear()
	var kills: Array = []
	w.events.subscribe("kill", func(_n: String, d: Dictionary) -> void: kills.append(d))
	var d := _free_neighbour(w)
	var m := Entities.spawn_monster("gnawer", w.player.x + d.x, w.player.y + d.y)
	m.hp = 1
	w.monsters.append(m)
	w.player.attack = 100
	w.move_player(d.x, d.y)
	assert_false(kills.is_empty())
	assert_eq(kills[0]["monster"], "gnawer")
	assert_eq(w.player.kills, 1)
	assert_eq(w.player.xp, m.xp_value)
	assert_false(w.monsters.has(m))


func test_timer_collapse_kills_player() -> void:
	var w := World.new(5)
	w.monsters.clear()
	w.timer = 2
	w.wait()
	assert_eq(w.state, "playing")
	w.wait()
	assert_eq(w.state, "dead")
	assert_true((w.death_cause as String).contains("collapsed"))


## (S8 range, pulled forward with move_player and wait.)
func test_no_fighting_in_safe_room() -> void:
	var w := World.new(10)
	w.monsters.clear()
	var sr := w.floor.safe_room
	w.player.x = sr.x
	w.player.y = sr.y                      # corner of safe room
	# Put a monster just outside the room, adjacent diagonally.
	var mx := sr.x - 1
	var my := sr.y - 1
	w.floor.tiles[my][mx] = 1
	var m := Entities.spawn_monster("goblin", mx, my)
	m.alerted = true
	w.monsters.append(m)
	var hp := w.player.hp
	assert_false(w.move_player(-1, -1))
	for _i in range(20):
		w.wait()
	assert_gte(w.player.hp, hp)
	assert_eq(m.hp, m.max_hp)


## Builds a world, starts a fight (combat, initiative, chase cache and toasts all live) and returns weak
## references to the world, its encounter and the tracer when `traced` (taps attached).
func _build_mid_combat(traced: bool) -> Array:
	var tracer := TraceRun.Tracer.new()
	var w: World
	if traced:
		w = World.new(3, ["dog", "Rex"], null, Callable(tracer, "on_event"), Callable(tracer, "on_message"), tracer)
	else:
		w = World.new(3, ["dog", "Rex"])
	var g := Entities.spawn_monster("goblin", w.player.x + 2, w.player.y)
	w.monsters.append(g)
	w.join_combat(g)
	w.wait()
	assert_not_null(w.combat)
	return [weakref(w), weakref(w.combat), weakref(tracer), weakref(w.training)]


func test_world_dropped_mid_combat_is_freed(traced = use_parameters([false, true])) -> void:
	var refs := _build_mid_combat(traced)
	for i in refs.size():
		assert_null(refs[i].get_ref(), "ref %d traced=%s" % [i, traced])


# --- S8: descend, rest, random play ---------------------------------------------------------

func test_descend_moves_to_next_floor_and_resets_timer() -> void:
	var w := World.new(6)
	var s0: Vector2i = w.floor.stairs[0]
	w.player.x = s0.x
	w.player.y = s0.y
	w.timer -= 100
	assert_true(w.stairs_locked)
	assert_false(w.descend())                        # locked until half the time passes
	w.turn = w.stairs_open_turn
	assert_true(w.descend())
	assert_eq(w.depth, 2)
	assert_eq(w.timer, GameConfig.floor_turns(2))


func test_final_floor_needs_the_boss_dead() -> void:
	var w := World.new(7)
	w.new_floor(GameConfig.NUM_FLOORS)
	var s0: Vector2i = w.floor.stairs[0]
	w.player.x = s0.x
	w.player.y = s0.y
	assert_true(w.exit_sealed)
	assert_false(w.descend())
	var boss: Monster = null
	for m in w.monsters:
		if m.tier == "headliner":
			boss = m
			break
	boss.hp = 0
	w._after_hit(boss, "melee")
	assert_false(w.exit_sealed)
	w.descend()
	assert_eq(w.state, "victory")


func test_descend_without_stairs_does_nothing() -> void:
	var w := World.new(8)
	assert_false(w.descend())
	assert_eq(w.depth, 1)


func test_rest_only_in_safe_room_and_costs_time() -> void:
	var w := World.new(9)
	w.monsters.clear()
	w.floor_items.clear()
	w.player.hp = 5
	assert_false(w.rest())
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	var before := w.timer
	assert_true(w.rest())
	assert_eq(w.player.hp, w.player.max_hp)
	assert_lt(w.timer, before)


## A random bot plays many turns: no crashes, monsters never enter safe rooms. Python's
## `random.Random(seed)` driver is a PyRandom with the same seed.
func test_random_play_smoke(seed_value = use_parameters(range(12))) -> void:
	var rng := PyRandom.new(seed_value)
	var w := World.new(seed_value)
	w.player.max_hp = 10000
	w.player.hp = 10000                              # keep it alive to cover more floors
	for _i in range(4000):
		if w.state != "playing":
			break
		if w.on_stairs and rng.random() < 0.5:
			w.descend()
		elif w.in_safe_room and rng.random() < 0.05:
			w.rest()
		else:
			var d: Vector2i = rng.choice(DungeonFloor.NEIGHBOURS_8)
			w.move_player(d.x, d.y)
		var positions := {}
		for m in w.monsters:
			assert_false(w.floor.is_safe(m.x, m.y))
			assert_true(w.floor.walkable(m.x, m.y))
			positions[Vector2i(m.x, m.y)] = true
		assert_eq(positions.size(), w.monsters.size())
		assert_false(positions.has(Vector2i(w.player.x, w.player.y)))
	assert_gt(w.turn, 0)

extends TestCase
## tests/test_encounter.py: initiative ordering with ties (S4) and the combat-mode tests on a World
## (S7: starting, initiative, the turn budget, ending, attacks of opportunity). The tests that need
## bombs, items, skills, descend, rest or saves are listed in docs/port-plan.md B.1 (slices S8, T2, T5, T6).


func after_each() -> void:
	TestHelpers.restore_patches()


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


# --- Helpers (tests/test_encounter.py) -------------------------------------------------

func _world(seed_value: int = 3, pet: Variant = null) -> World:
	var w := World.new(seed_value, pet)
	w.monsters.clear()
	w.floor_items.clear()
	w.player.max_hp = 999                  # nobody dies by accident
	w.player.hp = 999
	return w


## The payloads of every `event_name` event from now on.
func _record(w: World, event_name: String) -> Array:
	var seen: Array = []
	w.events.subscribe(event_name, func(_n: String, d: Dictionary) -> void: seen.append(d))
	return seen


func _open(w: World, x: int, y: int) -> bool:
	return w.floor.walkable(x, y) and not w.floor.is_safe(x, y) and w.floor.tiles[y][x] != DungeonFloor.STAIRS


## A non-safe tile with n open tiles to its east, so tests can line things up.
func _row(w: World, n: int = 4) -> Vector2i:
	var f := w.floor
	for y in range(f.height):
		for x in range(f.width):
			var ok := true
			for i in range(n + 1):
				if not _open(w, x + i, y):
					ok = false
					break
			if ok:
				return Vector2i(x, y)
	fail_test("no open row")
	return Vector2i()


func _goblin(w: World, x: int, y: int, kw: Dictionary = {}) -> Monster:
	var g := Entities.spawn_monster("goblin", x, y)
	var hp: int = kw.get("hp", 999)
	g.hp = hp
	g.max_hp = hp
	for k in kw:
		if k != "hp":
			g.set(k, kw[k])
	w.monsters.append(g)
	return g


## Player at the west end of an open row, a goblin `gap` tiles east, combat on with the goblin
## stunned (so it waits) unless told otherwise.
func _fight(w: World, gap: int = 2, kw: Dictionary = {}) -> Monster:
	var pos := _row(w)
	w.player.x = pos.x
	w.player.y = pos.y
	w.update_fov()
	var opts := kw.duplicate()
	var stunned: int = opts.get("stunned", 0)
	opts.erase("stunned")
	var g := _goblin(w, pos.x + gap, pos.y, opts)
	w.wait()                                    # it sees you: roll for initiative
	assert_true(w.combat != null and w.combat.has_entity(g))
	g.x = pos.x + gap                           # back in place if it already stepped closer
	g.stunned = stunned
	return g


## First open tile (row by row) out of sight and more than `far` tiles from the player; with
## `all_open` its eight neighbours must be open too. Vector2i(-1, -1) if none.
func _far_tile(w: World, far: int, all_open: bool = false) -> Vector2i:
	for y in range(w.floor.height):
		for x in range(w.floor.width):
			if not (_open(w, x, y) and not w.visible.has(Vector2i(x, y))
					and maxi(absi(x - w.player.x), absi(y - w.player.y)) > far):
				continue
			var ok := true
			if all_open:
				for n in DungeonFloor.NEIGHBOURS_8:
					if not _open(w, x + n.x, y + n.y):
						ok = false
						break
			if ok:
				return Vector2i(x, y)
	fail_test("no far tile")
	return Vector2i(-1, -1)


func _all_true(d: Dictionary) -> bool:
	for k in d:
		if not d[k]:
			return false
	return true


# --- Starting ----------------------------------------------------------------

func test_out_of_combat_nothing_changes() -> void:
	var w := _world()
	var turn := w.turn
	assert_null(w.combat)
	var pos := _row(w)
	w.player.x = pos.x
	w.player.y = pos.y
	assert_true(w.move_player(1, 0))
	assert_eq(w.turn, turn + 1)                  # every act is a whole turn
	assert_true(w.wait())
	assert_eq(w.turn, turn + 2)
	assert_null(w.combat)


func test_monster_in_view_starts_combat() -> void:
	var w := _world()
	var starts := _record(w, "combat_start")
	var rolls := _record(w, "initiative")
	var g := _fight(w, 3)
	assert_true(g.alerted)
	assert_eq(starts[0]["by"], "monster")
	var who: Array = []
	for r in rolls:
		if not who.has(r["who"]):
			who.append(r["who"])
	who.sort()
	var expected: Array = ["you", g.name]
	expected.sort()
	assert_eq(who, expected)
	var found := false
	for line in w.messages.lines:
		if (line[0] as String).begins_with("COMBAT! Initiative: "):
			found = true
	assert_true(found)


func test_no_combat_while_in_a_safe_room() -> void:
	var w := _world()
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	w.update_fov()
	var g := _goblin(w, w.player.x + 1, w.player.y)
	w.visible[Vector2i(g.x, g.y)] = true
	Ai.take_monster_turns(w)
	assert_true(g.alerted)
	assert_null(w.combat)
	assert_false(w.join_combat(g))


func test_bump_attacking_starts_combat_and_spends_the_action() -> void:
	var w := _world()
	var starts := _record(w, "combat_start")
	var pos := _row(w)
	w.player.x = pos.x
	w.player.y = pos.y
	w.update_fov()
	var g := _goblin(w, pos.x + 1, pos.y)
	g.alerted = false
	var turn := w.turn
	assert_true(w.move_player(1, 0))
	var enc := w.combat
	assert_true(enc != null and enc.has_entity(g) and g.alerted)
	assert_eq(starts[0]["by"], "player")
	assert_true(not enc.has("action") and enc.has("move") and enc.has("bonus"))
	assert_eq(w.turn, turn)
	assert_eq(enc.round, 1)                      # still your first turn
	assert_false(w.move_player(1, 0))            # second attack refused
	assert_true((w.messages.lines[-1][0] as String).contains("action"))
	assert_eq(w.turn, turn)


# --- Initiative ----------------------------------------------------------------

func test_initiative_is_seeded_and_dex_applies() -> void:
	var orders: Array = []
	for _i in range(2):
		var w := _world(11, ["dog", "Rex"])
		w.player.attrs["dex"] = 18
		var rolls := _record(w, "initiative")
		_fight(w, 3)
		var you: Dictionary = {}
		for r in rolls:
			if r["who"] == "you":
				you = r
				break
		assert_eq(you["bonus"], w.mod("dex"))
		assert_eq(you["bonus"], 4)
		assert_eq(you["total"], you["roll"] + 4)
		assert_true(w.combat.has_entity(w.pet))
		var enc := w.combat
		var totals: Array = []
		for e in enc.entities:
			totals.append(enc.total(e))
		var sorted_totals := totals.duplicate()
		sorted_totals.sort()
		sorted_totals.reverse()
		assert_eq(totals, sorted_totals)
		var order: Array = []
		for r in rolls:
			order.append([r["who"], r["total"]])
		orders.append(order)
	assert_eq(orders[0], orders[1])


func test_late_joiner_rolls_on_joining() -> void:
	var w := _world()
	_fight(w, 3, {"stunned": 9})
	var rolls := _record(w, "initiative")
	var late := _goblin(w, w.player.x, w.player.y + 1)
	w.join_combat(late)
	assert_true(w.combat.has_entity(late))
	var who: Array = []
	for r in rolls:
		who.append(r["who"])
	assert_eq(who, [late.name])


# --- The turn budget -------------------------------------------------------------

func test_wait_ends_your_turn_early() -> void:
	var w := _world()
	_fight(w, 3, {"stunned": 9})
	var turn := w.turn
	assert_true(w.move_player(1, 0))
	assert_eq(w.turn, turn)
	assert_true(w.wait())
	assert_eq(w.turn, turn + 1)
	assert_true(_all_true(w.combat.budget))


func test_monster_in_combat_steps_and_attacks_in_one_round() -> void:
	var w := _world()
	var hits := _record(w, "damage_taken")
	var misses := _record(w, "dodged")
	var g := _fight(w, 3, {"attack": 100})
	g.x = w.player.x + 2                         # two tiles off: step, then swing
	var turn := w.turn
	w.wait()
	assert_eq(Ai.cheb(w.player, g), 1)
	assert_eq(w.turn, turn + 1)
	assert_gte(hits.size() + misses.size(), 1)
	assert_false(hits.is_empty())


func test_one_round_ticks_the_clock_once() -> void:
	var w := _world()
	_fight(w, 3, {"stunned": 99})
	var turns: Array = []
	w.events.subscribe("turn", func(_n: String, d: Dictionary) -> void: turns.append(d["turn"]))
	for _i in range(3):
		w.wait()
	assert_eq(turns.size(), 3)


# --- Ending ----------------------------------------------------------------------

func test_killing_the_last_combatant_ends_combat() -> void:
	var w := _world()
	var ends := _record(w, "combat_end")
	var g := _fight(w, 1, {"stunned": 9, "hp": 1})
	w.player.attack = 100
	var turn := w.turn
	assert_true(w.move_player(1, 0))
	assert_false(w.monsters.has(g))
	assert_null(w.combat)
	assert_eq(ends[0]["cause"], "cleared")
	assert_eq(w.turn, turn + 1)                  # the rest of the round plays out


func test_losing_track_ends_combat() -> void:
	var w := _world()
	var ends := _record(w, "combat_end")
	var g := _fight(w, 3)
	var far := _far_tile(w, 30)
	g.x = far.x
	g.y = far.y
	g.unseen_turns = GameConfig.MONSTER_LOSE_TRACK
	w.wait()
	assert_null(w.combat)
	assert_false(g.alerted)
	assert_eq(ends[0]["cause"], "lost_track")


func test_entering_a_safe_room_ends_combat() -> void:
	var w := _world()
	var f := w.floor
	var door: Vector2i = f.safe_door
	var outside := Vector2i(-1, -1)
	for n in DungeonFloor.NEIGHBOURS_8:
		if _open(w, door.x + n.x, door.y + n.y):
			outside = Vector2i(door.x + n.x, door.y + n.y)
			break
	w.player.x = outside.x
	w.player.y = outside.y
	w.update_fov()
	var spot := Vector2i(-1, -1)
	for n in DungeonFloor.NEIGHBOURS_8:
		if _open(w, outside.x + n.x, outside.y + n.y):
			spot = Vector2i(outside.x + n.x, outside.y + n.y)
			break
	var g := _goblin(w, spot.x, spot.y, {"stunned": 9})
	w.join_combat(g)
	assert_not_null(w.combat)
	assert_true(w.move_player(door.x - outside.x, door.y - outside.y))
	assert_true(w.in_safe_room)
	assert_null(w.combat)


func test_dying_ends_combat() -> void:
	var w := _world()
	var ends := _record(w, "combat_end")
	var g := _fight(w, 1, {"attack": 100})
	g.dmg_bonus = 5000
	w.riposte = 0
	w.wait()
	assert_eq(w.state, "dead")
	assert_null(w.combat)
	assert_eq(ends[-1]["cause"], "death")


func test_a_monster_that_loses_track_does_not_act_again_that_round() -> void:
	TestHelpers.patch_static(GameConfig, "MONSTER_WANDER_CHANCE", 1.0)    # an outsider would always wander
	var w := _world()
	var g := _fight(w, 3)
	var far := _far_tile(w, 30, true)
	g.x = far.x
	g.y = far.y
	g.unseen_turns = GameConfig.MONSTER_LOSE_TRACK
	w.wait()
	assert_null(w.combat)
	assert_false(g.alerted)
	assert_eq(Vector2i(g.x, g.y), far)


func test_a_pet_ahead_in_initiative_acts_once_when_the_fight_ends_mid_turn() -> void:
	var w := _world(3, ["dog", "Rex"])
	var g := _fight(w, 1, {"stunned": 99})
	var enc := w.combat
	var pet := w.pet
	enc.remove(pet)
	enc.add(pet, 99, 0)                                    # the pet goes first
	pet.cooldown = 10
	w.wait()                                               # next round: the pet acts first
	assert_eq(pet.cooldown, 9)
	g.hp = 1
	w.player.attack = 100
	var turn := w.turn
	assert_true(w.move_player(g.x - w.player.x, g.y - w.player.y))
	assert_null(w.combat)
	assert_eq(w.turn, turn + 1)
	assert_eq(pet.cooldown, 9)                             # it already had its go this round


func test_monsters_ahead_in_initiative_act_before_your_first_turn() -> void:
	TestHelpers.patch_item(Content.monster("goblin"), "init", 50)     # it always goes first
	var w := _world()
	var hits := _record(w, "damage_taken")
	var pos := _row(w)
	w.player.x = pos.x
	w.player.y = pos.y
	w.update_fov()
	var g := _goblin(w, pos.x + 2, pos.y, {"attack": 100})
	w.wait()                                               # it notices you: combat starts...
	assert_not_null(w.combat)
	assert_true(is_same(w.combat.entities[0], g))
	assert_eq(Ai.cheb(w.player, g), 1)                     # ...and it closes in and hits first
	assert_false(hits.is_empty())
	assert_true(_all_true(w.combat.budget))                # then your turn, untouched


# --- Attacks of opportunity ------------------------------------------------------

## A non-safe tile with open ground two tiles west, three east and one above and below.
func _room(w: World) -> Vector2i:
	var f := w.floor
	for y in range(f.height):
		for x in range(f.width):
			var ok := true
			for dx in range(-2, 4):
				for dy in [-1, 0, 1]:
					if not _open(w, x + dx, y + dy):
						ok = false
			if ok:
				return Vector2i(x, y)
	fail_test("no open room")
	return Vector2i()


## You with a goblin right next to you (east), in combat, your turn fresh. Returns [x, y, goblin].
func _melee_fight(w: World, kw: Dictionary = {}) -> Array:
	var pos := _room(w)
	w.player.x = pos.x
	w.player.y = pos.y
	w.update_fov()
	var g := _goblin(w, pos.x + 1, pos.y, kw)
	assert_true(w.join_combat(g))
	return [pos.x, pos.y, g]


func _has_line(w: World, needle: String) -> bool:
	for line in w.messages.lines:
		if (line[0] as String).contains(needle):
			return true
	return false


func test_stepping_away_provokes_one_attack_a_round() -> void:
	var w := _world()
	var aoo := _record(w, "opportunity_attack")
	var fight := _melee_fight(w, {"attack": 100})
	var g: Monster = fight[2]
	var pv := w.provokers(-1, 0)
	assert_eq(pv.size(), 1)
	assert_true(is_same(pv[0], g))
	assert_true(w.provokers(0, 1).is_empty())
	var hp := w.player.hp
	assert_true(w.move_player(-1, 0))
	assert_eq_deep(aoo, [{"attacker": "goblin", "target": "player", "hit": true}])
	assert_lt(w.player.hp, hp)
	assert_true(_has_line(w, "Attack of opportunity"))
	assert_false(w.move_player(-1, 0))                     # move spent: no second step
	assert_eq(aoo.size(), 1)
	w.wait()                                               # its turn: it closes in again
	assert_eq(Ai.cheb(w.player, g), 1)
	var px := w.player.x
	assert_true(w.move_player(-1, 0))                      # next round it provokes again
	assert_eq(w.player.x, px - 1)
	assert_eq(aoo.size(), 2)


func test_moving_along_its_side_does_not_provoke() -> void:
	var w := _world()
	var aoo := _record(w, "opportunity_attack")
	_melee_fight(w)
	assert_true(w.move_player(0, 1))
	assert_true(aoo.is_empty())


func test_each_adjacent_monster_gets_its_own_attack() -> void:
	var w := _world()
	var aoo := _record(w, "opportunity_attack")
	var fight := _melee_fight(w)
	var g2 := _goblin(w, fight[0] + 1, fight[1] + 1)
	w.join_combat(g2)
	assert_true(w.move_player(-1, 0))
	assert_eq(aoo.size(), 2)
	for a in aoo:
		assert_eq(a["attacker"], "goblin")


func test_riposte_parries_an_attack_of_opportunity() -> void:
	var w := _world()
	var aoo := _record(w, "opportunity_attack")
	_melee_fight(w, {"attack": 100})
	w.riposte = 2
	var hp := w.player.hp
	assert_true(w.move_player(-1, 0))
	assert_eq(w.riposte, 1)
	assert_eq(aoo[0]["hit"], false)
	assert_eq(w.player.hp, hp)


func test_a_stunned_monster_cannot_react_and_a_reaction_lasts_until_its_turn() -> void:
	var w := _world()
	var aoo := _record(w, "opportunity_attack")
	_melee_fight(w, {"stunned": 1})
	assert_true(w.provokers(-1, 0).is_empty())
	assert_true(w.move_player(-1, 0))
	assert_true(aoo.is_empty())
	var w2 := _world()
	var aoo2 := _record(w2, "opportunity_attack")
	var fight2 := _melee_fight(w2)
	w2.combat.react(fight2[2])                             # already used this round
	assert_true(w2.move_player(-1, 0))
	assert_true(aoo2.is_empty())


func test_a_monster_leaving_your_reach_gives_you_and_your_pet_a_free_attack() -> void:
	var w := _world(3, ["dog", "Rex"])
	var aoo := _record(w, "opportunity_attack")
	var fight := _melee_fight(w)
	var x: int = fight[0]
	var y: int = fight[1]
	var g: Monster = fight[2]
	w.pet.x = x + 1                                        # the dog is next to it too
	w.pet.y = y + 1
	assert_true(w.combat.has_entity(w.pet))
	assert_true(w.opportunity_attacks(g, x + 3, y))
	var pairs: Array = []
	for a in aoo:
		pairs.append([a["attacker"], a["target"]])
	pairs.sort()
	assert_eq(pairs, [["pet", "goblin"], ["player", "goblin"]])
	assert_true(w.opportunity_attacks(g, x + 3, y))
	assert_eq(aoo.size(), 2)                               # reactions used up


func test_your_pet_leaving_a_monster_provokes_it() -> void:
	var w := _world(3, ["dog", "Rex"])
	var aoo := _record(w, "opportunity_attack")
	var fight := _melee_fight(w)
	var x: int = fight[0]
	var y: int = fight[1]
	w.pet.x = x + 2
	w.pet.y = y
	w.opportunity_attacks(w.pet, x + 3, y + 1)
	var pairs: Array = []
	for a in aoo:
		pairs.append([a["attacker"], a["target"]])
	assert_eq(pairs, [["goblin", "pet"]])


func test_swapping_with_your_pet_does_not_provoke() -> void:
	var w := _world(3, ["dog", "Rex"])
	var aoo := _record(w, "opportunity_attack")
	var fight := _melee_fight(w)
	var x: int = fight[0]
	var y: int = fight[1]
	w.pet.x = x - 1
	w.pet.y = y
	assert_true(w.move_player(-1, 0))
	assert_eq([w.pet.x, w.pet.y], [x, y])
	assert_true(aoo.is_empty())


func test_nothing_provokes_out_of_combat() -> void:
	var w := _world()
	var aoo := _record(w, "opportunity_attack")
	var pos := _room(w)
	w.player.x = pos.x
	w.player.y = pos.y
	_goblin(w, pos.x + 1, pos.y, {"alerted": false})
	assert_true(w.provokers(-1, 0).is_empty())
	assert_true(w.threats().is_empty())
	assert_true(w.move_player(-1, 0))
	assert_true(aoo.is_empty())


func test_a_monster_cut_down_as_it_retreats_does_not_move() -> void:
	var w := _world()
	var fight := _melee_fight(w, {"hp": 1})
	var g: Monster = fight[2]
	w.player.attack = 100
	assert_false(w.opportunity_attacks(g, fight[0] + 3, fight[1]))
	assert_false(w.monsters.has(g))


# --- Slice 5 review fixes ------------------------------------------------------------

func test_the_combat_banner_shows_for_two_of_your_rounds() -> void:
	var w := _world()
	_fight(w, 3, {"stunned": 99})
	var stamp := -1
	for t in w.toasts:
		if t[2] == "combat":
			stamp = t[0]
			break
	assert_true(w.turn - stamp < 2)
	w.wait()
	assert_true(w.turn - stamp < 2)
	w.wait()
	assert_false(w.turn - stamp < 2)


func test_expired_toasts_are_pruned() -> void:
	var w := _world()
	for i in range(50):
		w.add_toast("t%d" % i, "silver")
		w._tick_clock()
	assert_lte(w.toasts.size(), GameConfig.TOAST_TURNS + 1)


func test_a_fight_with_only_a_lost_outsider_left_ends() -> void:
	var w := _world()
	var ends := _record(w, "combat_end")
	var g := _fight(w, 1, {"stunned": 9, "hp": 1})
	var p := w.player
	var spot := Vector2i(-1, -1)
	for y in range(w.floor.height):
		for x in range(w.floor.width):
			var d := maxi(absi(x - p.x), absi(y - p.y))
			if spot.x < 0 and _open(w, x, y) and not w.visible.has(Vector2i(x, y)) and 6 < d and d <= 20:
				spot = Vector2i(x, y)
	var o := _goblin(w, spot.x, spot.y, {"alerted": true, "unseen_turns": GameConfig.MONSTER_LOSE_TRACK})
	w.player.attack = 100
	assert_true(w.move_player(1, 0))
	assert_false(w.monsters.has(g))
	assert_not_null(w.combat)                              # it's still after you...
	w.wait()
	assert_false(o.alerted)
	assert_null(w.combat)
	assert_eq(ends[-1]["cause"], "lost_track")


## A safe tile s with a non-safe walkable neighbour o (s + d) and a safe tile behind (s - d):
## [s, d], or [] if there is none.
func _safe_edge(w: World) -> Array:
	var f := w.floor
	for y in range(f.height):
		for x in range(f.width):
			if not f.is_safe(x, y) or not f.walkable(x, y):
				continue
			for n in DungeonFloor.NEIGHBOURS_8:
				if _open(w, x + n.x, y + n.y) and f.walkable(x - n.x, y - n.y) \
						and f.is_safe(x - n.x, y - n.y):
					return [Vector2i(x, y), n]
	fail_test("no safe-room edge")
	return []


func test_no_attacks_of_opportunity_into_or_out_of_a_safe_room() -> void:
	var w := _world(3, ["dog", "Rex"])
	var aoo := _record(w, "opportunity_attack")
	var fight := _melee_fight(w, {"attack": 100})
	var g: Monster = fight[2]
	var edge := _safe_edge(w)
	var s: Vector2i = edge[0]
	var d: Vector2i = edge[1]
	w.pet.x = s.x                                          # the pet on the safe side...
	w.pet.y = s.y
	g.x = s.x + d.x                                        # ...the goblin just outside
	g.y = s.y + d.y
	var hp := w.pet.hp
	assert_true(w.opportunity_attacks(w.pet, s.x - d.x, s.y - d.y))   # pet steps deeper in: no swing
	assert_true(w.opportunity_attacks(g, g.x + d.x, g.y + d.y))       # goblin backs off: the pet can't swing out
	assert_true(aoo.is_empty())
	assert_eq(w.pet.hp, hp)


func test_no_warning_once_your_move_is_spent() -> void:
	var w := _world()
	var fight := _melee_fight(w)
	var th := w.threats()
	assert_eq(th.size(), 1)
	assert_true(is_same(th[0], fight[2]))
	w.combat.spend("move")
	assert_true(w.threats().is_empty())
	assert_true(w.provokers(-1, 0).is_empty())

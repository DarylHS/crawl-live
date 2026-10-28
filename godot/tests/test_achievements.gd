extends TestCase
## Slice T1: Achievements, AchievementTracker and AchievementRules. The achievement tests of
## tests/test_showrunner.py (kept here, not in test_showrunner.gd, so slice T2 owns that file) and
## checks of the data-rule interpreter, the unlock flow (toast, message, "achievement" event payload
## order, box with reason), subscription order and ownership.


func _kill(w: World, hp: Variant = null, monster: String = "goblin", by: String = "melee") -> void:
	var p := w.player
	w.events.emit("kill", {"monster": monster, "depth": 1, "turn": w.turn, "by": by,
			"player_hp": p.hp if hp == null else hp, "player_max_hp": p.max_hp})


func after_each() -> void:
	TestHelpers.restore_patches()


func _tracker() -> AchievementTracker:
	return AchievementTracker.new()


# --- tests/test_showrunner.py ---------------------------------------------------------------------

func test_achievements_unlock_once_and_award_boxes() -> void:
	var w := World.new(3)
	var table := Achievements.table()
	assert_gte(table.size(), 30)
	for k in table:
		assert_true(String(table[k]["desc"]).ends_with("."), k)
	_kill(w)
	assert_true(w.achievements.unlocked.has("first_blood"))
	assert_gte(w.boxes.count("bronze"), 1)
	var named := 0
	for t in w.toasts:
		if "First Blood" in t[1]:
			named += 1
	assert_eq(named, 1)
	var n := w.boxes.size()
	_kill(w)
	assert_eq(w.boxes.size(), n)
	assert_eq(w.achievements.tracker.kills, 2)
	named = 0
	for t in w.toasts:
		if "First Blood" in t[1]:
			named += 1
	assert_eq(named, 1)


func test_close_call_and_cutting_it_fine() -> void:
	var w := World.new(3)
	_kill(w, 2)
	assert_true(w.achievements.unlocked.has("close_call"))
	w.events.emit("descend", {"depth": 1, "turn": 5, "timer_left": 10, "timer_max": 720})
	assert_true(w.achievements.unlocked.has("cutting_it_fine"))


func test_dressed_to_kill_and_pack_rat_and_demolition() -> void:
	var w := World.new(3)
	w.inventory = ["pan", "jersey"]
	w.equip(0)
	assert_false(w.achievements.unlocked.has("dressed_to_kill"))
	w.equip(0)
	assert_true(w.achievements.unlocked.has("dressed_to_kill"))
	for _i in range(10):
		w.events.emit("item_pickup", {"item": "sock"})
	assert_true(w.achievements.unlocked.has("pack_rat"))
	w.events.emit("bomb", {"item": "popper", "kills": 2})
	assert_true(w.achievements.unlocked.has("demolition"))


func test_deep_diver_via_descend() -> void:
	var w := World.new(3)
	w.new_floor(2)
	assert_false(w.achievements.unlocked.has("deep_diver"))
	w.new_floor(3)
	assert_true(w.achievements.unlocked.has("deep_diver"))


# --- Unlock flow -----------------------------------------------------------------------------------

func test_unlock_flow_toast_message_event_box() -> void:
	var w := World.new(7)
	var said: Array = []
	w.events.subscribe("achievement", func(_n: String, d: Dictionary) -> void: said.append(d))
	var order: Array = []
	w.events.subscribe("*", func(n: String, _d: Dictionary) -> void:
		if n == "achievement" or n == "box_gained":
			order.append(n))
	w.events.emit("nat1", {"foe": "the goblin", "Foe": "The goblin"})
	assert_eq(said.size(), 1)
	var d: Dictionary = said[0]
	assert_eq(d.keys(), ["key", "title", "tier", "turn", "why", "reward"])
	assert_eq(d["key"], "blooper_reel")
	assert_eq(d["title"], "Blooper Reel")
	assert_eq(d["tier"], "bronze")
	assert_eq(d["turn"], w.turn)
	assert_eq(d["why"], "Rolled a natural 1. The audience loved it.")
	assert_eq(d["reward"], "a Bronze box")
	assert_eq(order, ["achievement", "box_gained"])
	assert_eq(w.achievements.unlocked["blooper_reel"], w.turn)
	var toast: Array = w.toasts[-1]
	assert_eq(toast, [w.turn, "Achievement: Blooper Reel", "bronze", "Bronze box. Open it in a safe room."])
	assert_eq(w.box_reasons["bronze"][0], "Blooper Reel. Rolled a natural 1. The audience loved it.")
	var lines := w.messages.recent(5)
	assert_eq(lines[-2][0], "Achievement unlocked: Blooper Reel! Rolled a natural 1. The audience loved it.")
	assert_eq(lines[-2][1], GameConfig.ACCENT)
	assert_eq(lines[-1][0], "You receive a Bronze loot box. Open it in a safe room.")


func test_unlock_order_follows_table_order() -> void:
	# nat1 matches blooper_reel then cursed_dice (table order); the fifth nat1 awards both in turn.
	var w := World.new(8)
	var keys: Array = []
	w.events.subscribe("achievement", func(_n: String, d: Dictionary) -> void: keys.append(d["key"]))
	for _i in range(5):
		w.events.emit("nat1", {})
	assert_eq(keys, ["blooper_reel", "cursed_dice"])


func test_tracker_counters() -> void:
	var w := World.new(10)
	var t := w.achievements.tracker
	_kill(w, null, "goblin", "melee")
	w.events.emit("kill", {"monster": "x", "by": "melee", "style": "unarmed", "player_hp": 9, "player_max_hp": 9})
	assert_eq([t.kills, t.unarmed_kills], [2, 1])
	w.events.emit("shop_sell", {"item_kind": "junk"})
	w.events.emit("shop_sell", {"item_kind": "weapon"})
	w.events.emit("pet_kill", {})
	w.events.emit("map_found", {})
	w.events.emit("nat1", {})
	assert_eq([t.junk_sold, t.pet_kills, t.maps, t.nat1s], [1, 1, 1, 1])
	w.events.emit("equip", {"slot": "weapon"})
	assert_true(t.equipped.has("weapon"))
	w.events.emit("unequip", {"slot": "weapon"})
	assert_false(t.equipped.has("weapon"))
	w.events.emit("unequip", {"slot": "weapon"})      # discard of a missing slot is fine
	assert_true(t.equipped.is_empty())


func test_headliner_achievements_come_from_bosses() -> void:
	var table := Achievements.table()
	for depth in range(1, 7):
		var b := Content.boss(depth)
		var a: Dictionary = table["headliner_%d" % depth]
		assert_eq(a["name"], "Show Stopper: " + b["name"])
		assert_eq(a["desc"], "Took down floor %d's Headliner, %s." % [depth, b["name"]])
		assert_eq(a["tier"], b["box"])
		assert_eq(a["on"], "boss_kill")


# --- Subscriptions ---------------------------------------------------------------------------------

func test_one_achievements_handler_per_event_after_practice() -> void:
	var w := World.new(1)
	var ons: Dictionary = {}
	for a in Achievements.table().values():
		ons[a["on"]] = true
	for ev in ons:
		var mine := 0
		var first_mine := -1
		var subs := w.events.subscribers(ev)
		for i in subs.size():
			if subs[i].get_object() == w.achievements:
				mine += 1
				first_mine = i
		assert_eq(mine, 1, ev)
		# Practice (created before Achievements in World._init) comes earlier on shared events.
		for i in subs.size():
			if subs[i].get_object() == w.training:
				assert_lt(i, first_mine, ev)
	var un := w.events.subscribers("unequip")
	assert_eq(un.size(), 1)
	assert_true(un[0].get_object() == w.achievements)


# --- Rules interpreter -----------------------------------------------------------------------------

func test_rule_counter_and_field_kinds() -> void:
	var t := _tracker()
	t.kills = 14
	var r := {"kind": "counter_gte", "counter": "kills", "n": 15}
	assert_false(AchievementRules.test(r, t, {}))
	t.kills = 15
	assert_true(AchievementRules.test(r, t, {}))
	assert_true(AchievementRules.test({"kind": "always"}, t, {}))
	var g := {"kind": "field_gte", "field": "depth", "n": 3}
	assert_false(AchievementRules.test(g, t, {"depth": 2}))
	assert_true(AchievementRules.test(g, t, {"depth": 3}))
	var e := {"kind": "field_eq", "field": "tier", "value": "opening"}
	assert_true(AchievementRules.test(e, t, {"tier": "opening"}))
	assert_false(AchievementRules.test(e, t, {"tier": "featured"}))
	var ft := {"kind": "field_true", "field": "early"}
	assert_false(AchievementRules.test(ft, t, {}))
	assert_false(AchievementRules.test(ft, t, {"early": false}))
	assert_true(AchievementRules.test(ft, t, {"early": true}))


func test_rule_floordiv_and_frac() -> void:
	var t := _tracker()
	var r := {"kind": "field_lte_floordiv", "field": "player_hp", "of": "player_max_hp", "div": 4}
	assert_true(AchievementRules.test(r, t, {"player_hp": 2, "player_max_hp": 11}))
	assert_false(AchievementRules.test(r, t, {"player_hp": 3, "player_max_hp": 11}))
	assert_true(AchievementRules.test(r, t, {"player_hp": 0, "player_max_hp": 3}))
	var f := {"kind": "field_lt_frac", "field": "timer_left", "of": "timer_max", "frac": 0.1}
	assert_true(AchievementRules.test(f, t, {"timer_left": 71, "timer_max": 720}))
	assert_false(AchievementRules.test(f, t, {"timer_left": 72, "timer_max": 720}))
	assert_false(AchievementRules.test(f, t, {"timer_left": 0, "timer_max": 0}))


func test_rule_equipped_all_and_all() -> void:
	var t := _tracker()
	var eq := {"kind": "equipped_all", "slots": ["weapon", "armour"]}
	assert_false(AchievementRules.test(eq, t, {}))
	t.equipped["weapon"] = true
	assert_false(AchievementRules.test(eq, t, {}))
	t.equipped["armour"] = true
	t.equipped["x"] = true
	assert_true(AchievementRules.test(eq, t, {}))
	var both: Dictionary = Achievements.table()["underfoot"]["rule"]
	assert_false(AchievementRules.test(both, t, {"skill": "stomping", "level": 2}))
	assert_false(AchievementRules.test(both, t, {"skill": "blades", "level": 3}))
	assert_true(AchievementRules.test(both, t, {"skill": "stomping", "level": 3}))


class FakeWorld extends RefCounted:
	var viewers: int = 0
	var inventory: Array = []


func test_rule_world_gte_reads_config_at_test_time() -> void:
	var fw := FakeWorld.new()
	var t := AchievementTracker.new(fw)
	assert_true(t.world == fw)
	var crowd := {"kind": "world_gte", "stat": "viewers", "n": 1000}
	fw.viewers = 999
	assert_false(AchievementRules.test(crowd, t, {}))
	fw.viewers = 1000
	assert_true(AchievementRules.test(crowd, t, {}))
	var hoard := {"kind": "world_gte", "stat": "inventory_len", "n_config": "INVENTORY_SIZE"}
	fw.inventory.resize(GameConfig.INVENTORY_SIZE - 1)
	assert_false(AchievementRules.test(hoard, t, {}))
	fw.inventory.resize(GameConfig.INVENTORY_SIZE)
	assert_true(AchievementRules.test(hoard, t, {}))
	TestHelpers.patch_static(GameConfig, "INVENTORY_SIZE", 3)
	fw.inventory.resize(3)
	assert_true(AchievementRules.test(hoard, t, {}))
	fw.inventory.resize(2)
	assert_false(AchievementRules.test(hoard, t, {}))


func test_hoarder_unlocks_on_a_full_pack() -> void:
	var w := World.new(11)
	w.inventory = []
	for _i in range(GameConfig.INVENTORY_SIZE - 1):
		w.inventory.append("sock")
	w.events.emit("item_pickup", {"item": "sock"})
	assert_false(w.achievements.unlocked.has("hoarder"))
	w.inventory.append("sock")
	w.events.emit("item_pickup", {"item": "sock"})
	assert_true(w.achievements.unlocked.has("hoarder"))


func test_crowd_pleaser_reads_the_showrunners_viewers() -> void:
	var w := World.new(12)
	w.showrunner.viewers = 999
	w.events.emit("viewers_gained", {"amount": 1})
	assert_false(w.achievements.unlocked.has("crowd_pleaser"))
	w.showrunner.viewers = 1000
	w.events.emit("viewers_gained", {"amount": 1})
	assert_true(w.achievements.unlocked.has("crowd_pleaser"))


# --- Ownership -------------------------------------------------------------------------------------

func _build() -> Array:
	var w := World.new(5)
	_kill(w)
	return [weakref(w), weakref(w.achievements), weakref(w.achievements.tracker)]


func test_achievements_and_tracker_are_freed_with_their_world() -> void:
	var refs := _build()
	for r in refs:
		assert_null(r.get_ref())


func test_tracker_without_world_has_null_world() -> void:
	var t := AchievementTracker.new()
	assert_null(t.world)

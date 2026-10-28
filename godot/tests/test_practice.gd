extends TestCase
## Practice (crawler/practice.py) and the World-free parts of tests/test_practice.py, plus replay of
## scripts/practice_reference.py output (real Python Practice driven by a recording stand-in
## world; env PRACTICE_REF, set by scripts/gd_test.sh).
##
## Deferred tests from tests/test_practice.py are listed in docs/port-plan.md Appendix B.1. Tests
## that need a real World (S6) run on World.new; the stand-in FakeWorld below only drives the
## replay of scripts/practice_reference.py output and the Practice unit checks.


## Recording stand-in for the World seam of Practice (events, messages, refresh_stats, add_toast,
## weapon_style); the log has the same shape as scripts/practice_reference.py's.
class FakeWorld:
	extends RefCounted
	var log: Array = []
	var style := "unarmed"
	var events := EventBus.new()
	var messages := MessageLog.new()
	var toasts: Array = []
	var training: Practice   # the world owns its Practice, as World.training will

	func _init() -> void:
		# The lambdas capture the log Array, not self: capturing self would be a reference cycle.
		var lg := log
		events.subscribe("practice_level", func(_n: String, d: Dictionary) -> void:
			lg.append(["event", d["skill"], d["level"], d["title"], d["many_at_3"]]))
		messages.tap = func(text: String, colour: Array) -> void: lg.append(["msg", text, colour])

	func refresh_stats() -> void:
		log.append(["refresh"])

	func add_toast(text: String, tier: String) -> void:
		toasts.append([0, text, tier])
		log.append(["toast", text, tier])

	func weapon_style() -> String:
		return style


var _worlds: Array = []   # Practice holds its world weakly: tests keep the worlds alive here
var _ref: Dictionary = {}
var _ref_error := ""


func after_each() -> void:
	_worlds = []


## A Practice on a fresh stand-in world that stays alive until the test ends.
func _fresh() -> Practice:
	var w := FakeWorld.new()
	_worlds.append(w)
	return Practice.new(w)


func before_all() -> void:
	var path := OS.get_environment("PRACTICE_REF")
	if path == "" or not FileAccess.file_exists(path):
		_ref_error = "PRACTICE_REF missing (run through scripts/gd_test.sh): " + path
		return
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		_ref = parsed
	else:
		_ref_error = "PRACTICE_REF does not parse: " + path


func _need_ref() -> bool:
	if _ref_error != "":
		fail_test(_ref_error)
		return false
	return true


func _rows(section: String) -> Array:
	var out: Array = []
	for row in _ref[section]:
		var r: Array = []
		for cell in row:
			r.append(PyFixtures.decode(cell))
		out.append(r)
	return out


func _snapshot(p: Practice) -> Dictionary:
	return {"levels": p.levels.duplicate(), "xp": p.xp.duplicate(), "used": p.to_dict()["used"], "steps": p.steps}


# --- Ported from tests/test_practice.py (World-free parts) ------------------------------------

func test_xp_curve_is_increasing_and_capped() -> void:
	var costs: Array = []
	for n in Practice.MAX_LEVEL:
		costs.append(Practice.xp_to_next(n))
	var sorted_costs := costs.duplicate()
	sorted_costs.sort()
	assert_eq(costs, sorted_costs)
	assert_true(costs[0] >= 1)
	var w := World.new(1)
	w.training.gain("stomping", 10_000)
	assert_eq(w.practice("stomping"), Practice.MAX_LEVEL)
	w.training.gain("stomping", 50)   # no XP past the cap
	assert_eq(w.practice("stomping"), Practice.MAX_LEVEL)


func test_skills_are_hidden_until_used_and_level_up_announces() -> void:
	var w := World.new(2)
	var t := w.training
	assert_true(Practice.skills().size() >= 20 and t.used.is_empty())
	var levels: Array = []
	w.events.subscribe("practice_level", func(_n: String, d: Dictionary) -> void: levels.append(d["level"]))
	t.gain("haggling", Practice.xp_to_next(0))
	assert_true(t.used.has("haggling"))
	assert_eq(w.practice("haggling"), 1)
	assert_eq(levels, [1])
	var found := false
	for toast in w.toasts:
		if "Skill up: Haggling 1" in toast[1]:
			found = true
	assert_true(found)


func test_stat_gains_apply_once_per_level() -> void:
	var w := World.new(3)
	var p := w.player
	var hp := p.max_hp
	var ac := p.ac
	var t := w.training
	while w.practice("pain_tolerance") < 3:
		t.gain("pain_tolerance")
	while w.practice("dodging") < 4:
		t.gain("dodging")
	assert_eq(p.max_hp, hp + 3)
	assert_eq(p.ac, ac + 1)


func test_sneaking_shortens_notice_range() -> void:
	var w := World.new(6)
	assert_eq(w.notice_range(), GameConfig.FOV_RADIUS)
	w.training.levels["sneaking"] = 8
	assert_eq(w.notice_range(), GameConfig.FOV_RADIUS - 2)


func test_haggling_and_gambling_change_prices() -> void:
	var w := World.new(7)
	var key: String = w.shop.stock.keys()[0]
	var buy := w.buy_price(key)
	var sell := w.sell_price(key)
	var fee := w.reroll_fee("gold")
	w.training.levels["haggling"] = 10
	w.training.levels["gambling"] = 10
	assert_lt(w.buy_price(key), buy)
	assert_gte(w.sell_price(key), sell)
	assert_lt(w.reroll_fee("gold"), fee)


func test_cardio_trains_by_walking_and_extends_the_next_timer() -> void:
	var w := World.new(8)
	w.player.max_hp = 1000
	w.player.hp = 1000
	TestHelpers.play(w, PyRandom.new(1), Practice.CARDIO_STEPS * 3)
	assert_true(w.training.used.has("cardio"))
	w.training.levels["cardio"] = 4
	var base: int = GameConfig.floor_turns(2) + int(w.get_trait("timer_bonus", 0))
	w.new_floor(2)
	assert_eq(w.timer_max, base + 8)


## A gnawer next to the player with 999 HP (survives every hit; max_hp still "small").
func _adjacent_gnawer(w: World) -> Monster:
	TestHelpers.clear_world(w)
	var spot: Vector2i = TestHelpers.free_tiles_near(w, w.player.x, w.player.y, 1)[0]
	var m := Entities.spawn_monster("gnawer", spot.x, spot.y)
	m.hp = 999
	w.monsters.append(m)
	return m


## Python wraps world.attack to read `bonus`; there is no seam in World, so the same roll is replayed
## on a copy of the main stream: the damage dealt must be that of an attack with bonus 2 (stomping 5
## // 2), not bonus 0.
func test_stomping_adds_damage_against_small_monsters() -> void:
	var w := World.new(4)
	var m := _adjacent_gnawer(w)
	w.training.levels["stomping"] = 5
	var checked := false
	for _i in range(30):                    # swing until the replayed roll hits, so the bonus shows
		var with_bonus := PyRandom.new(0)
		with_bonus.set_state(w.rng.get_state())
		var without := PyRandom.new(0)
		without.set_state(w.rng.get_state())
		var twin_a := Entities.spawn_monster("gnawer", m.x, m.y)
		twin_a.hp = 999
		var twin_b := Entities.spawn_monster("gnawer", m.x, m.y)
		twin_b.hp = 999
		var want := Combat.attack(w.player, twin_a, with_bonus, 1, false, 2)
		var bare := Combat.attack(w.player, twin_b, without, 1, false, 0)
		var before := m.hp
		w._player_attack(m)
		assert_eq(before - m.hp, want.damage)    # unarmed, no fisticuffs yet: all from stomping
		if want.hit:
			assert_ne(want.damage, bare.damage)
			checked = true
			break
	assert_true(checked)


func test_hitting_trains_the_matching_weapon_skill() -> void:
	var w := World.new(5)
	var m := _adjacent_gnawer(w)
	for _i in range(10):                    # a few swings, so at least one lands
		w._player_attack(m)
	assert_true(w.training.used.has("fisticuffs") and w.training.used.has("stomping"))
	w.equipment["weapon"] = "cleaver"
	for _i in range(10):
		w._player_attack(m)
	assert_true(w.training.used.has("blades"))


func test_telemetry_has_one_practice_row_per_skill() -> void:
	var w := World.new(10)
	var t := Telemetry.new(w, "bot", 1)
	w.training.gain("lobbing", 10)
	var tables := t.tables()
	assert_eq(tables["practice"].size(), Practice.skills().size())
	var row: Dictionary = {}
	for r in tables["practice"]:
		if r["skill"] == "lobbing":
			row = r
			break
	assert_eq(row["level"], w.practice("lobbing"))
	assert_eq(row["used"], 1)
	var total := 0
	for k in w.training.levels:
		total += w.training.levels[k]
	assert_eq(tables["runs"][0]["practice_levels"], total)


# --- Direct checks ------------------------------------------------------------------------------

func test_constants_match_python() -> void:
	assert_eq(Practice.MAX_LEVEL, 15)
	assert_eq(Practice.SMALL_MONSTER_HP, 12)
	assert_eq(Practice.CARDIO_STEPS, 40)
	assert_eq(Practice.skills().size(), 20)


func test_xp_to_next_known_values() -> void:
	assert_eq(Practice.xp_to_next(0), 8)
	assert_eq(Practice.xp_to_next(1), 12)
	assert_eq(Practice.xp_to_next(2), 17)


func test_new_practice_is_all_zero_in_skill_order() -> void:
	var p := _fresh()
	assert_eq(p.levels.keys(), Practice.skills().keys())
	assert_eq(p.xp.keys(), Practice.skills().keys())
	for v in p.levels.values():
		assert_eq(v, 0)
	assert_eq(p.steps, 0)


func test_non_positive_gain_does_not_mark_used() -> void:
	var p := _fresh()
	p.gain("cardio", 0)
	p.gain("cardio", -4)
	assert_true(p.used.is_empty())


func test_gain_at_cap_marks_used_but_adds_no_xp() -> void:
	var p := _fresh()
	p.gain("lobbing", 100_000)
	var before: int = p.xp["lobbing"]
	p.gain("lobbing", 7)
	assert_eq(p.xp["lobbing"], before)
	assert_true(p.used.has("lobbing"))


func _build_owned() -> Array:
	var w := FakeWorld.new()
	w.training = Practice.new(w)
	w.training.gain("cardio", 100)
	return [weakref(w), weakref(w.training)]


func test_world_and_practice_are_freed_together() -> void:
	var refs := _build_owned()   # both dropped when the inner function returns
	assert_null(refs[0].get_ref())
	assert_null(refs[1].get_ref())


func test_practice_without_its_world_gets_null() -> void:
	var p: Practice
	var w := FakeWorld.new()
	p = Practice.new(w)
	assert_true(p.world == w)
	w = null
	assert_null(p.world)


func test_listener_subscription_order() -> void:
	# Python subscribes in this order; same-named subscribers must keep it (shop_buy and shop_sell share _shop).
	var w := FakeWorld.new()
	var p := Practice.new(w)
	var expected := {
		"player_attack": "_attack", "kill": "_kill", "damage_taken": "_hurt", "dodged": "_dodged",
		"bomb": "_bomb", "item_use": "_item_use", "rest": "_rest", "step": "_step",
		"item_pickup": "_pickup", "shop_buy": "_shop", "shop_sell": "_shop", "box_opened": "_box",
		"craft": "_craft", "viewers_gained": "_viewers", "pet_hit": "_pet"}
	for ev in expected:
		var subs: Array = w.events.subscribers(ev)
		assert_eq(subs.size(), 1, ev)
		assert_eq(String(subs[0].get_method()), expected[ev], ev)
		assert_true(subs[0].get_object() == p, ev)
	# Subscription order across events: the key order of this dictionary is Python's tuple order.
	assert_eq(expected.keys(), ["player_attack", "kill", "damage_taken", "dodged", "bomb", "item_use", "rest", "step",
		"item_pickup", "shop_buy", "shop_sell", "box_opened", "craft", "viewers_gained", "pet_hit"])
	w.events.emit("shop_sell", {})
	assert_eq(p.xp["haggling"], 1)


# --- Replay of Python output --------------------------------------------------------------------

func test_ref_constants() -> void:
	if not _need_ref():
		return
	var c: Array = []
	for cell in _ref["constants"]:
		c.append(PyFixtures.decode(cell))
	assert_eq(c[0], Practice.MAX_LEVEL)
	assert_eq(c[1], Practice.CARDIO_STEPS)
	assert_eq(c[2], Practice.skills().keys())
	assert_eq(PyFixtures.decode(_ref["accent"]), GameConfig.ACCENT)


func test_ref_xp_curve_levels_0_to_40() -> void:
	if not _need_ref():
		return
	var rows := _rows("curve")
	assert_eq(rows.size(), 41)
	var bad := 0
	for r in rows:
		if Practice.xp_to_next(r[0]) != r[1]:
			bad += 1
			push_warning("curve mismatch at %d" % r[0])
	assert_eq(bad, 0)


func test_ref_every_level_up_of_every_skill() -> void:
	if not _need_ref():
		return
	var rows := _rows("level_ups")
	assert_eq(rows.size(), Practice.skills().size())
	var bad := 0
	for r in rows:
		var w := FakeWorld.new()
		var p := Practice.new(w)
		var key: String = r[0]
		var steps: Array = []
		for a in r[1]:
			p.gain(key, a)
			steps.append([p.level(key), p.xp[key], w.log.size()])
		var d1 := strict_diff(steps, r[2], key + " steps")
		var d2 := strict_diff(w.log, r[3], key + " log")
		var d3 := strict_diff(_snapshot(p), r[4], key + " state")
		for d in [d1, d2, d3]:
			if d != "":
				bad += 1
				gut.p(d)
	assert_eq(bad, 0)


func test_ref_random_gain_sequences() -> void:
	if not _need_ref():
		return
	var rows := _rows("gains")
	assert_eq(rows.size(), 30)
	var bad := 0
	for r in rows:
		var w := FakeWorld.new()
		var p := Practice.new(w)
		var ends: Array = []
		for s in r[0]:
			p.gain(s[0], s[1])
			ends.append(w.log.size())
		for d in [strict_diff(ends, r[1], "ends"), strict_diff(w.log, r[2], "log"), strict_diff(_snapshot(p), r[3], "state")]:
			if d != "":
				bad += 1
				gut.p(d)
	assert_eq(bad, 0)


func test_ref_event_scenarios() -> void:
	if not _need_ref():
		return
	var rows := _rows("events")
	assert_eq(rows.size(), 9)
	var bad := 0
	var total := 0
	for r in rows:
		var w := FakeWorld.new()
		var p := Practice.new(w)
		var snaps: Array = []
		var evs: Array = r[0]
		for j in evs.size():
			var e: Array = evs[j]
			w.style = e[2]
			w.events.emit(e[0], e[1])
			total += 1
			if j % 25 == 24 or j == evs.size() - 1:
				var lv := 0
				for v in p.levels.values():
					lv += v
				var xs := 0
				for v in p.xp.values():
					xs += v
				snaps.append([j, w.log.size(), p.steps, lv, xs])
		var expected_snaps: Array = r[1]
		if not expected_snaps.is_empty():
			var d := strict_diff(snaps, expected_snaps, "snaps")
			if d != "":
				bad += 1
				gut.p(d)
		for d in [strict_diff(w.log, r[2], "log"), strict_diff(_snapshot(p), r[3], "state")]:
			if d != "":
				bad += 1
				gut.p(d)
	assert_eq(bad, 0)
	assert_true(total > 20000)


func test_ref_load_and_to_dict() -> void:
	if not _need_ref():
		return
	var rows := _rows("load")
	assert_eq(rows.size(), 5)
	var bad := 0
	for i in rows.size():
		var r: Array = rows[i]
		var p := _fresh()
		if i < 4:
			p.load(r[0])
		else:
			var w := FakeWorld.new()
			var src := Practice.new(w)
			src.gain("scavenging", 30)
			src.gain("first_aid", 3)
			assert_eq_deep(src.to_dict(), r[0], "source")
			p.load(src.to_dict())
		for d in [strict_diff(p.to_dict(), r[1], "to_dict"), strict_diff(p.levels.keys(), r[2], "level keys"),
				strict_diff(p.xp.keys(), r[3], "xp keys")]:
			if d != "":
				bad += 1
				gut.p(d)
	assert_eq(bad, 0)

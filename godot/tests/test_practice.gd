extends TestCase
## Practice (crawler/practice.py) and the World-free parts of tests/test_practice.py, plus replay of
## scripts/practice_reference.py output (real Python Practice driven by a recording stand-in
## world; env PRACTICE_REF, set by scripts/gd_test.sh).
##
## Deferred to later slices (they need World): stat_gains_apply_once_per_level (S6),
## stomping_adds_damage_against_small_monsters, hitting_trains_the_matching_weapon_skill (S8),
## sneaking_shortens_notice_range, haggling_and_gambling_change_prices,
## cardio_trains_by_walking_and_extends_the_next_timer (S6/S8), save_round_trip_keeps_practice (T5),
## telemetry_has_one_practice_row_per_skill (T4). The World parts of test_xp_curve and
## test_skills_are_hidden_until_used are ported here against the stand-in world.


## Recording stand-in for the World seam of Practice (events, messages, refresh_stats, add_toast,
## weapon_style); the log has the same shape as scripts/practice_reference.py's.
class FakeWorld:
	extends RefCounted
	var log: Array = []
	var style := "unarmed"
	var events := EventBus.new()
	var messages := MessageLog.new()
	var toasts: Array = []

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
	var w := FakeWorld.new()
	var t := Practice.new(w)
	t.gain("stomping", 10_000)
	assert_eq(t.level("stomping"), Practice.MAX_LEVEL)
	t.gain("stomping", 50)   # no XP past the cap
	assert_eq(t.level("stomping"), Practice.MAX_LEVEL)


func test_skills_are_hidden_until_used_and_level_up_announces() -> void:
	var w := FakeWorld.new()
	var t := Practice.new(w)
	assert_true(Practice.skills().size() >= 20 and t.used.is_empty())
	var levels: Array = []
	w.events.subscribe("practice_level", func(_n: String, d: Dictionary) -> void: levels.append(d["level"]))
	t.gain("haggling", Practice.xp_to_next(0))
	assert_true(t.used.has("haggling"))
	assert_eq(t.level("haggling"), 1)
	assert_eq(levels, [1])
	var found := false
	for toast in w.toasts:
		if "Skill up: Haggling 1" in toast[1]:
			found = true
	assert_true(found)


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


func test_world_is_held_weakly() -> void:
	var p: Practice
	var w := FakeWorld.new()
	p = Practice.new(w)
	assert_true(p.world == w)


func test_listener_subscription_order() -> void:
	# Python order: attack, kill, damage_taken, dodged, bomb, item_use, rest, step, pickup, shop buy and sell, box, craft, viewers, pet.
	var w := FakeWorld.new()
	var seen: Array = []
	var p := Practice.new(w)
	w.events.subscribe("*", func(n: String, _d: Dictionary) -> void: seen.append(n))
	w.events.emit("shop_sell", {})
	assert_eq(p.level("haggling"), 0)
	assert_eq(p.xp["haggling"], 1)
	assert_eq(seen, ["shop_sell"])


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

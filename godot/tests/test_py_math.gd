extends TestCase
## PyMath against Python 3.12+ (fixtures from scripts/make_fixtures.py, path in FIXTURES) plus
## hand-written cases from the port plan (3.1, 3.3, Appendix A).


## Negative zero (the GDScript literal -0.0 is parsed as +0.0).
var NEG_ZERO: float = PyFixtures.float_from_hex("8000000000000000")


func _need_fixtures() -> bool:
	if not PyFixtures.available():
		pending("FIXTURES not set (run through scripts/gd_test.sh)")
		return false
	return true


# --- Hand-written cases ---------------------------------------------------------------------

func test_floordiv_and_mod_on_negatives() -> void:
	assert_eq(PyMath.floordiv(-1, 2), -1)
	assert_eq(PyMath.floordiv(7, -2), -4)
	assert_eq(PyMath.floordiv(-7, -2), 3)
	assert_eq(PyMath.floordiv(8, 2), 4)
	assert_eq(PyMath.floordiv(-8, 2), -4)
	assert_eq(PyMath.mod(-1, 5), 4)
	assert_eq(PyMath.mod(5, -3), -1)
	assert_eq(PyMath.mod(-6, 3), 0)
	assert_eq(PyMath.mod(-60, 60), 0)
	# The attribute modifier: (score - 10) // 2 for a score of 9 is -1, GDScript's / would give 0.
	assert_eq(PyMath.floordiv(9 - 10, 2), -1)
	assert_eq((9 - 10) / 2, 0)


func test_division_by_zero_is_an_error() -> void:
	assert_eq(PyMath.floordiv(5, 0), 0)
	assert_push_error("PyMath.floordiv")
	assert_eq(PyMath.mod(5, 0), 0)
	assert_push_error("PyMath.mod")


func test_fmod_py_signs() -> void:
	assert_eq(PyFixtures.float_bits(PyMath.fmod_py(-5.0, 3.0)), PyFixtures.float_bits(1.0))
	assert_eq(PyFixtures.float_bits(PyMath.fmod_py(5.0, -3.0)), PyFixtures.float_bits(-1.0))
	assert_eq(PyFixtures.float_bits(PyMath.fmod_py(-360.0, 360.0)), PyFixtures.float_bits(0.0))
	assert_eq(PyFixtures.float_bits(PyMath.fmod_py(0.0, -5.0)), PyFixtures.float_bits(NEG_ZERO))
	assert_eq(PyFixtures.float_bits(PyMath.fmod_py(-0.0, 5.0)), PyFixtures.float_bits(0.0))


func test_round_half_even() -> void:
	assert_eq(PyMath.round_half_even(0.5), 0)
	assert_eq(PyMath.round_half_even(1.5), 2)
	assert_eq(PyMath.round_half_even(2.5), 2)
	assert_eq(PyMath.round_half_even(-0.5), 0)
	assert_eq(PyMath.round_half_even(-1.5), -2)
	assert_eq(PyMath.round_half_even(-2.5), -2)
	assert_eq(PyMath.round_half_even(10 * 1.25), 12)   # round(sum * RESPAWN_CAP) with 10 monsters
	assert_eq(PyMath.round_half_even(2.4999), 2)
	assert_eq(PyMath.round_half_even(2.5001), 3)
	assert_eq(PyMath.round_half_even(7.0), 7)
	assert_eq(round(2.5), 3.0, "Godot's own round() is half away from zero, which is why PyMath exists")


func test_round_n() -> void:
	assert_eq(PyFixtures.float_bits(PyMath.round_n(2.675, 2)), PyFixtures.float_bits(2.67))
	assert_eq(PyFixtures.float_bits(PyMath.round_n(0.1 + 0.2, 3)), PyFixtures.float_bits(0.3))
	assert_eq(PyFixtures.float_bits(PyMath.round_n(1.0 / 3.0, 3)), PyFixtures.float_bits(0.333))
	assert_eq(PyFixtures.float_bits(PyMath.round_n(0.5, 0)), PyFixtures.float_bits(0.0))
	assert_eq(PyFixtures.float_bits(PyMath.round_n(1.5, 0)), PyFixtures.float_bits(2.0))


func test_fsum_is_compensated() -> void:
	assert_eq(PyMath.fsum_py([0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1, 0.1]), 1.0)
	var naive := 0.0
	for i in 10:
		naive += 0.1
	assert_ne(naive, 1.0, "a naive loop gives 0.9999999999999999")
	assert_eq(PyMath.fsum_py([]), 0.0)
	assert_eq(PyMath.fsum_py([2, 3]), 5.0)


func test_truthy() -> void:
	for v in [0, 0.0, "", [], {}, null, false, PackedStringArray()]:
		assert_false(PyMath.truthy(v), "falsy %s" % var_to_str(v))
	for v in [1, -1, 0.5, "a", " ", [0], {"a": 1}, true, Vector2i.ZERO]:
		assert_true(PyMath.truthy(v), "truthy %s" % var_to_str(v))


func test_compare_tuples() -> void:
	assert_eq(PyMath.compare_tuples([1, 2], [1, 3]), -1)
	assert_eq(PyMath.compare_tuples([2], [1, 9]), 1)
	assert_eq(PyMath.compare_tuples([1, 2], [1, 2]), 0)
	assert_eq(PyMath.compare_tuples([1], [1, 0]), -1)
	assert_eq(PyMath.compare_tuples([], []), 0)
	assert_eq(PyMath.compare_tuples([1, "b"], [1, "a"]), 1)
	assert_eq(PyMath.compare_tuples([1, 2.5], [1, 2]), 1)


func test_stable_sort_keeps_ties_in_order() -> void:
	var items := [["a", 2], ["b", 1], ["c", 2], ["d", 1], ["e", 2]]
	var got := PyMath.stable_sort_by(items, func(x: Array) -> int: return x[1])
	assert_eq(got.map(func(x: Array) -> String: return x[0]), ["b", "d", "a", "c", "e"])
	# reverse=True keeps equal elements in their original order too (Python semantics).
	var rev := PyMath.stable_sort_by(items, func(x: Array) -> int: return x[1], true)
	assert_eq(rev.map(func(x: Array) -> String: return x[0]), ["a", "c", "e", "b", "d"])
	assert_eq(items[0][0], "a", "input untouched")


func test_stable_sort_in_place_typed_array() -> void:
	var xs: Array[int] = [5, 3, 9, 1]
	PyMath.stable_sort_in_place(xs, func(x: int) -> int: return -x)
	assert_eq(xs, [9, 5, 3, 1] as Array[int])


func test_sort_key_called_once_per_element_in_order() -> void:
	var seen: Array = []
	var items := [3, 1, 2]
	PyMath.stable_sort_by(items, func(x: int) -> int:
		seen.append(x)
		return x)
	assert_eq(seen, [3, 1, 2])


func test_min_max_by_first_extreme_wins() -> void:
	var items := [["a", 1], ["b", 0], ["c", 0], ["d", 2], ["e", 2]]
	var key := func(x: Array) -> int: return x[1]
	assert_eq(PyMath.min_by(items, key)[0], "b")
	assert_eq(PyMath.max_by(items, key)[0], "d")
	assert_eq(PyMath.min_by([], key), null)
	assert_eq(PyMath.max_by([], key, -1), -1)
	# Tuple keys, e.g. (cheb, s).
	var pts := [[3, 1], [2, 5], [2, 4]]
	assert_eq(PyMath.min_by(pts, func(p: Array) -> Array: return [p[0], p[1]]), [2, 4])


# --- Against Python ---------------------------------------------------------------------------

func test_intdiv_matches_python() -> void:
	if not _need_fixtures():
		return
	var bad: Array = []
	var rows := PyFixtures.rows("math", "intdiv")
	for r in rows:
		if PyMath.floordiv(r[0], r[1]) != r[2] or PyMath.mod(r[0], r[1]) != r[3]:
			bad.append(r)
	assert_gt(rows.size(), 400)
	assert_eq(bad.slice(0, 5), [], "%d of %d differ" % [bad.size(), rows.size()])


func test_float_mod_matches_python() -> void:
	if not _need_fixtures():
		return
	var bad: Array = []
	var rows := PyFixtures.rows("math", "floatmod")
	for r in rows:
		if PyFixtures.float_bits(PyMath.fmod_py(r[0], r[1])) != PyFixtures.float_bits(r[2]):
			bad.append([r[0], r[1], r[2], PyMath.fmod_py(r[0], r[1])])
	assert_eq(bad.slice(0, 5), [], "%d of %d differ" % [bad.size(), rows.size()])


func test_round_matches_python() -> void:
	if not _need_fixtures():
		return
	var bad: Array = []
	var rows := PyFixtures.rows("math", "round")
	for r in rows:
		if PyMath.round_half_even(r[0]) != r[1]:
			bad.append([r[0], r[1], PyMath.round_half_even(r[0])])
	assert_gt(rows.size(), 1000)
	assert_eq(bad.slice(0, 5), [], "%d of %d differ" % [bad.size(), rows.size()])


func test_round_n_matches_python() -> void:
	if not _need_fixtures():
		return
	var bad: Array = []
	var rows := PyFixtures.rows("math", "round_n")
	for r in rows:
		var got := PyMath.round_n(r[0], r[1])
		if PyFixtures.float_bits(got) != PyFixtures.float_bits(r[2]):
			bad.append([r[0], r[1], r[2], got])
	assert_gt(rows.size(), 2000)
	assert_eq(bad.slice(0, 5), [], "%d of %d differ" % [bad.size(), rows.size()])


func test_fsum_matches_python_sum() -> void:
	if not _need_fixtures():
		return
	var bad: Array = []
	var naive_differs := 0
	var rows := PyFixtures.rows("math", "fsum")
	for r in rows:
		var got := PyMath.fsum_py(r[0])
		if PyFixtures.float_bits(got) != PyFixtures.float_bits(r[1]):
			bad.append([r[0], r[1], got])
		var naive := 0.0
		for x in r[0]:
			naive += x
		if PyFixtures.float_bits(naive) != PyFixtures.float_bits(r[1]):
			naive_differs += 1
	assert_eq(bad.slice(0, 3), [], "%d of %d differ" % [bad.size(), rows.size()])
	assert_gt(naive_differs, 0, "the fixtures include lists where a naive sum is wrong")


func test_sorted_matches_python() -> void:
	if not _need_fixtures():
		return
	var bad := 0
	var rows := PyFixtures.rows("math", "sort")
	for r in rows:
		var items: Array = r[1]
		var got := PyMath.stable_sort_by(items, func(x: Array) -> Variant: return x[0], r[2])
		var order: Array = got.map(func(x: Array) -> int: return x[1])
		if order != r[3]:
			bad += 1
		var copy := items.duplicate()
		PyMath.stable_sort_in_place(copy, func(x: Array) -> Variant: return x[0], r[2])
		if copy.map(func(x: Array) -> int: return x[1]) != r[3]:
			bad += 1
	assert_gt(rows.size(), 500)
	assert_eq(bad, 0)


func test_min_max_match_python() -> void:
	if not _need_fixtures():
		return
	var bad := 0
	for r in PyFixtures.rows("math", "extreme"):
		var key := func(x: Array) -> int: return x[0]
		if PyMath.min_by(r[0], key)[1] != r[1] or PyMath.max_by(r[0], key)[1] != r[2]:
			bad += 1
	assert_eq(bad, 0)


func test_compare_tuples_matches_python() -> void:
	if not _need_fixtures():
		return
	var bad := 0
	for r in PyFixtures.rows("math", "tuple_cmp"):
		if PyMath.compare_tuples(r[0], r[1]) != r[2]:
			bad += 1
	assert_eq(bad, 0)

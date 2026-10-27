extends TestCase
## Runner self-checks (use --file=test_smoke).

func test_assert_helpers_pass() -> void:
	assert_eq(1, 1)
	assert_ne(1, 2)
	assert_true(true)
	assert_false(false)
	assert_null(null)
	assert_not_null(0)
	assert_almost_eq(0.1 + 0.2, 0.3, 1e-9)
	assert_gt(2, 1)
	assert_lt(1, 2)
	assert_between(5, 1, 9)
	assert_has([1, 2], 2)
	assert_has({"a": 1}, "a")
	assert_does_not_have([1, 2], 3)
	assert_eq_deep({"a": [1, {"b": 2.5}]}, {"a": [1, {"b": 2.5}]})
	assert_eq([1, 2], [1, 2])


func test_eq_is_type_strict() -> void:
	# Meta check: the failure path records an entry; we then clear it so the file passes.
	assert_eq(1, 1)
	var before := _failures.size()
	assert_eq(1, 1.0)
	assert_eq_deep([1], [1.0])
	assert_eq_deep({"a": 1, "b": 2}, {"b": 2, "a": 1})
	assert_eq(_failures.size() - before, 3, "int vs float and key order must fail")
	_failures = PackedStringArray()


func test_param(p = use_parameters([[1, 2], [3, 4]])) -> void:
	assert_eq(p[1], p[0] + 1)

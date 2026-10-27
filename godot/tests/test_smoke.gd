extends TestCase
## Test-base self-checks.

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
	# Int vs float and dictionary key order must count as different (GUT alone would pass them).
	assert_ne(strict_diff(1, 1.0), "")
	assert_ne(strict_diff([1], [1.0]), "")
	assert_ne(strict_diff({"a": 1, "b": 2}, {"b": 2, "a": 1}), "")
	assert_eq(strict_diff({"a": [1, {"b": 2.5}]}, {"a": [1, {"b": 2.5}]}), "")


func test_param(p = use_parameters([[1, 2], [3, 4]])) -> void:
	assert_eq(p[1], p[0] + 1)

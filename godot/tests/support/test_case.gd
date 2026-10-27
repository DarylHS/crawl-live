class_name TestCase
extends RefCounted
## GUT-compatible subset for the stopgap runner (tests/run_tests.gd, port plan 7.2).
## Migrating a test file to GUT is one line: `extends TestCase` -> `extends GutTest`.
##
## Assertions follow GUT's names and argument order and, like GUT, never abort the test.
## assert_eq / assert_ne refuse to compare different types (1 vs 1.0 fails, as in GUT), so
## int-vs-float coercion bugs in content or rules cannot hide.

var _failures: PackedStringArray = PackedStringArray()   # "file:line: message", read by the runner
var _asserts: int = 0
var _pending: PackedStringArray = PackedStringArray()
var _param_index: int = 0
var _param_count: int = 0


# --- Parametrised tests (GUT semantics) -------------------------------------------------
# func test_x(p = use_parameters([[1, 2], [3, 4]])): ...   runs once per entry, reported test_x[i].

func use_parameters(params: Array) -> Variant:
	_param_count = params.size()
	return params[_param_index] if _param_index < params.size() else null


# --- Assertions ---------------------------------------------------------------------------

func assert_eq(got: Variant, expected: Variant, msg: String = "") -> void:
	_asserts += 1
	if typeof(got) != typeof(expected):
		_fail("expected %s (%s) but got %s (%s)%s" % [_s(expected), type_string(typeof(expected)),
			_s(got), type_string(typeof(got)), _m(msg)])
	elif got != expected:
		_fail("expected %s but got %s%s" % [_s(expected), _s(got), _m(msg)])


func assert_ne(got: Variant, not_expected: Variant, msg: String = "") -> void:
	_asserts += 1
	if typeof(got) == typeof(not_expected) and got == not_expected:
		_fail("did not expect %s%s" % [_s(got), _m(msg)])


func assert_true(value: Variant, msg: String = "") -> void:
	_asserts += 1
	if value != true:
		_fail("expected true but got %s%s" % [_s(value), _m(msg)])


func assert_false(value: Variant, msg: String = "") -> void:
	_asserts += 1
	if value != false:
		_fail("expected false but got %s%s" % [_s(value), _m(msg)])


func assert_null(value: Variant, msg: String = "") -> void:
	_asserts += 1
	if value != null:
		_fail("expected null but got %s%s" % [_s(value), _m(msg)])


func assert_not_null(value: Variant, msg: String = "") -> void:
	_asserts += 1
	if value == null:
		_fail("expected a value but got null%s" % _m(msg))


func assert_almost_eq(got: Variant, expected: Variant, tolerance: Variant, msg: String = "") -> void:
	_asserts += 1
	if absf(float(got) - float(expected)) > float(tolerance):
		_fail("expected %s +/- %s but got %s%s" % [_s(expected), _s(tolerance), _s(got), _m(msg)])


func assert_gt(got: Variant, expected: Variant, msg: String = "") -> void:
	_asserts += 1
	if not got > expected:
		_fail("expected %s > %s%s" % [_s(got), _s(expected), _m(msg)])


func assert_lt(got: Variant, expected: Variant, msg: String = "") -> void:
	_asserts += 1
	if not got < expected:
		_fail("expected %s < %s%s" % [_s(got), _s(expected), _m(msg)])


func assert_between(got: Variant, low: Variant, high: Variant, msg: String = "") -> void:
	_asserts += 1
	if got < low or got > high:
		_fail("expected %s between %s and %s%s" % [_s(got), _s(low), _s(high), _m(msg)])


## Array: item in array; Dictionary: key in dictionary; String: substring.
func assert_has(container: Variant, item: Variant, msg: String = "") -> void:
	_asserts += 1
	if not _contains(container, item):
		_fail("expected %s to have %s%s" % [_s(container), _s(item), _m(msg)])


func assert_does_not_have(container: Variant, item: Variant, msg: String = "") -> void:
	_asserts += 1
	if _contains(container, item):
		_fail("expected %s not to have %s%s" % [_s(container), _s(item), _m(msg)])


## Recursive equality that also requires equal types at every leaf and equal dictionary key order.
func assert_eq_deep(got: Variant, expected: Variant, msg: String = "") -> void:
	_asserts += 1
	var diff := _deep_diff(got, expected, "")
	if diff != "":
		_fail("deep difference at %s%s" % [diff, _m(msg)])


func assert_file_exists(path: String, msg: String = "") -> void:
	_asserts += 1
	if not FileAccess.file_exists(path):
		_fail("expected file %s to exist%s" % [path, _m(msg)])


func assert_file_does_not_exist(path: String, msg: String = "") -> void:
	_asserts += 1
	if FileAccess.file_exists(path):
		_fail("expected file %s not to exist%s" % [path, _m(msg)])


func fail_test(msg: String = "") -> void:
	_asserts += 1
	_fail("failed: %s" % msg)


func pass_test(_msg: String = "") -> void:
	_asserts += 1


func pending(msg: String = "") -> void:
	_pending.append(msg)


# --- Internals -----------------------------------------------------------------------------

func _fail(text: String) -> void:
	var where := ""
	for frame in get_stack():
		if not String(frame["source"]).ends_with("test_case.gd"):
			where = "%s:%d" % [String(frame["source"]).get_file(), frame["line"]]
			break
	_failures.append("%s: %s" % [where, text])


static func _m(msg: String) -> String:
	return "" if msg == "" else " (" + msg + ")"


static func _s(v: Variant) -> String:
	var t := var_to_str(v)
	return t if t.length() <= 160 else t.left(157) + "..."


static func _contains(container: Variant, item: Variant) -> bool:
	match typeof(container):
		TYPE_DICTIONARY:
			return container.has(item)
		TYPE_STRING:
			return String(container).contains(String(item))
		_:
			return container.has(item)


static func _deep_diff(a: Variant, b: Variant, path: String) -> String:
	if typeof(a) != typeof(b):
		return "%s: %s (%s) vs %s (%s)" % [path, _s(a), type_string(typeof(a)), _s(b), type_string(typeof(b))]
	if a is Dictionary:
		var ka: Array = a.keys()
		var kb: Array = b.keys()
		if ka != kb:
			return "%s: keys %s vs %s" % [path, _s(ka), _s(kb)]
		for k in ka:
			var d := _deep_diff(a[k], b[k], path + "/" + str(k))
			if d != "":
				return d
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s: size %d vs %d" % [path, a.size(), b.size()]
		for i in a.size():
			var d := _deep_diff(a[i], b[i], path + "/" + str(i))
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s vs %s" % [path, _s(a), _s(b)]

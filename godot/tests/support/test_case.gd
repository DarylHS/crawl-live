class_name TestCase
extends GutTest
## Base class for every Crawl Live! test: GUT 9 (addons/gut) plus stricter equality.
##
## GUT's assert_eq treats 1 and 1.0 as equal and its deep compare ignores dictionary key order.
## The port needs both to fail (content and rules must keep Python's int/float types and insertion
## order), so assert_eq, assert_ne and assert_eq_deep are tightened here. Every other assert,
## use_parameters, before_all/after_each and pending come straight from GutTest.


func assert_eq(got, expected, text := "") -> void:
	var diff := strict_diff(got, expected)
	if diff == "":
		_pass("%s == %s %s" % [_s(got), _s(expected), text])
	else:
		_fail("expected %s but got %s (%s) %s" % [_s(expected), _s(got), diff, text])


func assert_ne(got, not_expected, text := "") -> void:
	if strict_diff(got, not_expected) == "":
		_fail("did not expect %s %s" % [_s(got), text])
	else:
		_pass("%s != %s %s" % [_s(got), _s(not_expected), text])


## Recursive equality: equal types at every leaf and equal dictionary key order.
func assert_eq_deep(got, expected, text := "") -> void:
	var diff := strict_diff(got, expected)
	if diff == "":
		_pass("deep equal %s" % text)
	else:
		_fail("deep difference at %s %s" % [diff, text])


## "" when a and b are strictly equal, else the path and values of the first difference.
static func strict_diff(a: Variant, b: Variant, path := "") -> String:
	if typeof(a) != typeof(b):
		return "%s: %s (%s) vs %s (%s)" % [path, _s(a), type_string(typeof(a)), _s(b), type_string(typeof(b))]
	if a is Dictionary:
		var ka: Array = a.keys()
		var kb: Array = b.keys()
		if ka != kb:
			return "%s: keys %s vs %s" % [path, _s(ka), _s(kb)]
		for k in ka:
			var d := strict_diff(a[k], b[k], path + "/" + str(k))
			if d != "":
				return d
		return ""
	if a is Array:
		if a.size() != b.size():
			return "%s: size %d vs %d" % [path, a.size(), b.size()]
		for i in a.size():
			var d := strict_diff(a[i], b[i], path + "/" + str(i))
			if d != "":
				return d
		return ""
	return "" if a == b else "%s: %s vs %s" % [path, _s(a), _s(b)]


static func _s(v: Variant) -> String:
	var t := var_to_str(v)
	return t if t.length() <= 160 else t.left(157) + "..."

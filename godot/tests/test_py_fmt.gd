extends TestCase
## PyFmt against Python (fixtures from scripts/make_fixtures.py, path in FIXTURES) plus hand cases.


func _need_fixtures() -> bool:
	return PyFixtures.require(self)


# --- Hand-written cases ---------------------------------------------------------------------

func test_repr_float_basics() -> void:
	assert_eq(PyFmt.repr_float(0.1 + 0.2), "0.30000000000000004")
	assert_eq(PyFmt.repr_float(0.3), "0.3")
	assert_eq(PyFmt.repr_float(1.0), "1.0")
	assert_eq(PyFmt.repr_float(100.0), "100.0")
	assert_eq(PyFmt.repr_float(-1.5), "-1.5")
	assert_eq(PyFmt.repr_float(0.0), "0.0")
	assert_eq(PyFmt.repr_float(1e16), "1e+16")
	assert_eq(PyFmt.repr_float(1.5e16), "1.5e+16")
	assert_eq(PyFmt.repr_float(123456789012345.0), "123456789012345.0")
	assert_eq(PyFmt.repr_float(1e-4), "0.0001")
	assert_eq(PyFmt.repr_float(1e-5), "1e-05")
	assert_eq(PyFmt.repr_float(2.5e-5), "2.5e-05")
	assert_eq(PyFmt.repr_float(1.0 / 3.0), "0.3333333333333333")
	assert_eq(PyFmt.repr_float(INF), "inf")
	assert_eq(PyFmt.repr_float(-INF), "-inf")
	assert_eq(PyFmt.repr_float(NAN), "nan")
	assert_eq(PyFmt.repr_float(PyFixtures.float_from_hex("8000000000000000")), "-0.0")
	assert_ne(str(0.1 + 0.2), "0.30000000000000004", "Godot's own str() loses digits, which is why PyFmt exists")


func test_str_and_repr() -> void:
	assert_eq(PyFmt.str(true), "True")
	assert_eq(PyFmt.str(false), "False")
	assert_eq(PyFmt.str(null), "None")
	assert_eq(PyFmt.str(5), "5")
	assert_eq(PyFmt.str(-5), "-5")
	assert_eq(PyFmt.str(2.0), "2.0")
	assert_eq(PyFmt.str("x"), "x")
	assert_eq(PyFmt.str(Vector2i(3, -4)), "(3, -4)")
	assert_eq(PyFmt.str([1, "a", null, true]), "[1, 'a', None, True]")
	assert_eq(PyFmt.repr("it's"), "\"it's\"")
	assert_eq(PyFmt.repr("a\nb"), "'a\\nb'")


func test_integer_specs() -> void:
	assert_eq(PyFmt.signed_int(3), "+3")
	assert_eq(PyFmt.signed_int(0), "+0")
	assert_eq(PyFmt.signed_int(-3), "-3")
	assert_eq(PyFmt.thousands(1234567), "1,234,567")
	assert_eq(PyFmt.thousands(-1000), "-1,000")
	assert_eq(PyFmt.thousands(999), "999")
	assert_eq(PyFmt.zero_pad(5, 2), "05")
	assert_eq(PyFmt.zero_pad(0, 2), "00")
	assert_eq(PyFmt.zero_pad(-5, 3), "-05")
	assert_eq(PyFmt.zero_pad(123, 2), "123")
	assert_eq(PyFmt.rjust("7", 3), "  7")
	assert_eq(PyFmt.rjust("1234", 3), "1234")
	assert_eq(PyFmt.ljust("7", 3), "7  ")


func test_float_specs() -> void:
	assert_eq(PyFmt.fixed(2.5, 0), "2")
	assert_eq(PyFmt.fixed(3.5, 0), "4")
	assert_eq(PyFmt.fixed(0.125, 2), "0.12")
	assert_eq(PyFmt.fixed(-0.4, 0), "-0")
	assert_eq(PyFmt.signed_fixed(-0.4, 0), "-0")
	assert_eq(PyFmt.signed_fixed(5.25, 1), "+5.2")
	assert_eq(PyFmt.percent(0.25, 0), "25%")
	assert_eq(PyFmt.percent(0.12345, 2), "12.35%")
	assert_eq(PyFmt.signed_percent(0.1, 0), "+10%")
	assert_eq(PyFmt.signed_percent(-0.1, 0), "-10%")
	assert_eq(PyFmt.thousands_fixed(1234567.891, 0), "1,234,568")
	assert_eq(PyFmt.thousands_fixed(-1234.5, 2), "-1,234.50")
	assert_eq(PyFmt.fixed(NAN, 1), "nan")
	assert_eq(PyFmt.fixed(INF, 1), "inf")


func test_capitalize_is_python_not_godot() -> void:
	assert_eq(PyFmt.capitalize("opening_act"), "Opening_act")
	assert_eq(PyFmt.capitalize("SILVER"), "Silver")
	assert_eq(PyFmt.capitalize(""), "")
	assert_eq("opening_act".capitalize(), "Opening Act", "Godot's capitalize() is a different operation")


func test_format_map() -> void:
	assert_eq(PyFmt.format_map("Floor {depth} is live, {hero}.", {"depth": 3, "hero": "Zed"}), "Floor 3 is live, Zed.")
	assert_eq(PyFmt.format_map("{a} {nope}", {"a": 1.5}), "1.5 ?")
	assert_eq(PyFmt.format_map("{{literal}} {a}", {"a": true}), "{literal} True")
	assert_eq(PyFmt.format_map("plain", {}), "plain")
	assert_eq(PyFmt.format_map("bad {", {}), "bad {")
	assert_push_error("single '{'")


# --- Against Python ---------------------------------------------------------------------------

func _check_repr(group: String, name: String) -> void:
	var bad: Array = []
	var rows := PyFixtures.rows(group, name)
	for r in rows:
		var got := PyFmt.repr_float(r[0])
		if got == r[1]:
			continue
		bad.append([r[1], got])
	assert_gt(rows.size(), 100)
	assert_eq(bad.slice(0, 8), [], "%d of %d differ" % [bad.size(), rows.size()])


func test_repr_float_game_values_match_python() -> void:
	if _need_fixtures():
		_check_repr("fmt", "repr_game")


func test_repr_float_edges_match_python() -> void:
	if _need_fixtures():
		_check_repr("fmt", "repr_edge")


func test_repr_float_random_values_match_python() -> void:
	if _need_fixtures():
		_check_repr("fmt", "repr_random")


func test_fixed_specs_match_python() -> void:
	if not _need_fixtures():
		return
	var bad: Array = []
	var rows := PyFixtures.rows("fmt", "fixed")
	for r in rows:
		if PyFmt.fixed(r[0], r[1]) != r[2] or PyFmt.signed_fixed(r[0], r[1]) != r[3]:
			bad.append([r[0], r[1], r[2], PyFmt.fixed(r[0], r[1]), r[3], PyFmt.signed_fixed(r[0], r[1])])
	assert_gt(rows.size(), 4000)
	assert_eq(bad.slice(0, 5), [], "%d of %d differ" % [bad.size(), rows.size()])


func test_percent_specs_match_python() -> void:
	if not _need_fixtures():
		return
	var bad: Array = []
	var rows := PyFixtures.rows("fmt", "percent")
	for r in rows:
		if PyFmt.percent(r[0], r[1]) != r[2] or PyFmt.signed_percent(r[0], r[1]) != r[3]:
			bad.append([r[0], r[1], r[2], PyFmt.percent(r[0], r[1]), r[3], PyFmt.signed_percent(r[0], r[1])])
	assert_gt(rows.size(), 3000)
	assert_eq(bad.slice(0, 5), [], "%d of %d differ" % [bad.size(), rows.size()])


func test_thousands_fixed_matches_python() -> void:
	if not _need_fixtures():
		return
	var bad: Array = []
	for r in PyFixtures.rows("fmt", "thousands_fixed"):
		if PyFmt.thousands_fixed(r[0], 0) != r[1] or PyFmt.thousands_fixed(r[0], 2) != r[2]:
			bad.append([r[0], r[1], PyFmt.thousands_fixed(r[0], 0), r[2], PyFmt.thousands_fixed(r[0], 2)])
	assert_eq(bad.slice(0, 5), [])


func test_integer_specs_match_python() -> void:
	if not _need_fixtures():
		return
	var bad: Array = []
	for r in PyFixtures.rows("fmt", "ints"):
		var n: int = r[0]
		var got := [PyFmt.signed_int(n), PyFmt.thousands(n), PyFmt.zero_pad(n, 2), PyFmt.zero_pad(n, 5),
				PyFmt.rjust(PyFmt.str(n), 3), PyFmt.ljust(PyFmt.str(n), 4)]
		if got != r.slice(1):
			bad.append([n, r.slice(1), got])
	assert_eq(bad.slice(0, 5), [])


func test_rjust_and_padded_percent_match_python() -> void:
	if not _need_fixtures():
		return
	for r in PyFixtures.rows("fmt", "rjust"):
		assert_eq(PyFmt.rjust(r[0], r[1]), r[2])
		assert_eq(PyFmt.ljust(r[0], r[1]), r[3])
	var rows := PyFixtures.rows("fmt", "pct_rjust")
	for r in rows:
		assert_eq(PyFmt.rjust(PyFmt.percent(r[0], 0), 4), r[1])
	assert_gt(rows.size(), 50)


func test_capitalize_matches_python() -> void:
	if not _need_fixtures():
		return
	for r in PyFixtures.rows("fmt", "capitalize"):
		assert_eq(PyFmt.capitalize(r[0]), r[1])


func test_str_and_repr_match_python() -> void:
	if not _need_fixtures():
		return
	for r in PyFixtures.rows("fmt", "str"):
		# Tuples have no GDScript twin here: the (1, 2) case arrives as a list and is skipped.
		if r[2] == "(1, 2)":
			continue
		assert_eq(PyFmt.str(r[0]), r[1])
		assert_eq(PyFmt.repr(r[0]), r[2])


func test_format_map_matches_python_on_every_system_line() -> void:
	if not _need_fixtures():
		return
	var bad: Array = []
	var rows := PyFixtures.rows("fmt", "format_map")
	for r in rows:
		var got := PyFmt.format_map(r[0], r[1])
		if got != r[2]:
			bad.append([r[0], got, r[2]])
	assert_gt(rows.size(), 300)
	assert_eq(bad.slice(0, 3), [], "%d of %d differ" % [bad.size(), rows.size()])

extends TestCase
## PyJson.dumps against json.dumps (fixtures from scripts/make_fixtures.py) plus loads checks.


func test_dumps_defaults() -> void:
	assert_eq(PyJson.dumps({"b": 1, "a": [1, 2.5, "x", null, true, false]}), '{"b": 1, "a": [1, 2.5, "x", null, true, false]}')
	assert_eq(PyJson.dumps([]), "[]")
	assert_eq(PyJson.dumps({}), "{}")
	assert_eq(PyJson.dumps(1.0), "1.0")
	assert_eq(PyJson.dumps(0.1 + 0.2), "0.30000000000000004")
	assert_eq(PyJson.dumps(NAN), "NaN")
	assert_eq(PyJson.dumps(INF), "Infinity")
	assert_eq(PyJson.dumps(-INF), "-Infinity")


func test_dumps_keeps_insertion_order_unlike_json_stringify() -> void:
	var d := {"zeta": 1, "alpha": 2}
	assert_eq(PyJson.dumps(d), '{"zeta": 1, "alpha": 2}')
	assert_ne(JSON.stringify(d), PyJson.dumps(d), "JSON.stringify sorts keys by default")


func test_dumps_int_vs_float() -> void:
	assert_eq(PyJson.dumps([3, 3.0]), "[3, 3.0]")
	assert_eq(PyJson.dumps(10 ** 12), "1000000000000")


func test_dumps_vector2i_as_list() -> void:
	assert_eq(PyJson.dumps(Vector2i(3, 4)), "[3, 4]")


func test_dumps_unsupported_type_is_an_error() -> void:
	assert_eq(PyJson.dumps(Color.RED), "null")
	assert_push_error("cannot serialise")


func test_ensure_ascii() -> void:
	assert_eq(PyJson.dumps("café"), '"caf\\u00e9"')
	assert_eq(PyJson.dumps("café", false), '"café"')
	assert_eq(PyJson.dumps("\U01f600"), '"\\ud83d\\ude00"')


func test_loads_round_trip() -> void:
	var text := PyJson.dumps({"a": [1, 2.5], "b": null, "c": "x\ny"})
	var back = PyJson.loads(text)
	assert_eq(back.keys(), ["a", "b", "c"], "document order kept")
	assert_eq(back["a"][1], 2.5)
	assert_eq(back["c"], "x\ny")
	assert_eq(typeof(back["a"][0]), TYPE_FLOAT, "ints come back as float; callers coerce by schema")


func test_loads_error() -> void:
	assert_eq(PyJson.loads("{oops"), null)
	assert_push_error("PyJson.loads")
	assert_false(PyJson.parse_ok("{oops"))
	assert_true(PyJson.parse_ok("null"))


func test_dumps_matches_python() -> void:
	if not PyFixtures.require(self):
		return
	var bad: Array = []
	var rows := PyFixtures.rows("json")
	for r in rows:
		var got := [PyJson.dumps(r[0]), PyJson.dumps(r[0], false), PyJson.dumps(r[0], false, 1), PyJson.dumps(r[0], true, 2)]
		if got != r.slice(1):
			bad.append([r.slice(1), got])
	assert_gt(rows.size(), 30)
	assert_eq(bad.slice(0, 3), [], "%d of %d differ" % [bad.size(), rows.size()])

extends TestCase
## Content loads from res://data/*.json with Python's types and order. The leaf-by-leaf comparison
## uses scripts/content_reference.py output (a typed dump of the Python objects, made by
## scripts/gd_test.sh into CONTENT_REF on every run).

var _ref: Dictionary = {}


func before_all() -> void:
	var path := TestHelpers.env("CONTENT_REF")
	if path != "" and FileAccess.file_exists(path):
		var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			_ref = parsed


func after_each() -> void:
	TestHelpers.restore_patches()


# --- Encoding helpers (same scheme as scripts/content_reference.py) ----------------------------

static func _enc(v: Variant) -> String:
	match typeof(v):
		TYPE_NIL:
			return "n:"
		TYPE_BOOL:
			return "b:1" if v else "b:0"
		TYPE_INT:
			return "i:%d" % v
		TYPE_FLOAT:
			var bytes := PackedByteArray()
			bytes.resize(8)
			bytes.encode_double(0, v)
			var hex := ""
			for i in range(7, -1, -1):
				hex += "%02x" % bytes[i]
			return "f:" + hex
		TYPE_STRING:
			return "s:" + v
	return "?:" + type_string(typeof(v))


static func _flat(node: Variant, path: String, out: Array) -> void:
	if node is Dictionary:
		if node.is_empty():
			out.append([path, "e:{}"])
		for k in node:
			_flat(node[k], path + "/" + String(k).replace("~", "~0").replace("/", "~1"), out)
	elif node is Array:
		if node.is_empty():
			out.append([path, "e:[]"])
		for i in node.size():
			_flat(node[i], path + "/" + str(i), out)
	else:
		out.append([path, _enc(node)])


# --- Every table loads ----------------------------------------------------------------------

func test_manifest_lists_every_data_file() -> void:
	var m := Content.manifest()
	assert_eq(m["generator"], 1)
	assert_eq(m["files"].size(), 23)
	assert_eq(Content.names().size(), 23)
	var on_disk := PackedStringArray()
	for f in DirAccess.get_files_at("res://data"):
		if f.ends_with(".json") and f != "manifest.json":
			on_disk.append(f.trim_suffix(".json"))
	on_disk.sort()
	var listed := Array(Content.names())
	listed.sort()
	assert_eq(Array(on_disk), listed)


func test_every_table_loads(name = use_parameters(Array(Content.names()))) -> void:
	var t = Content.table(name)
	assert_not_null(t, name)
	assert_true(t is Dictionary or t is Array, name)
	assert_false(t.is_empty(), name)


func test_files_match_manifest_hashes() -> void:
	assert_true(Content.verify())


func test_table_is_cached() -> void:
	assert_true(is_same(Content.table("monsters"), Content.table("monsters")))
	var first = Content.table("pets")
	Content.reload()
	var second = Content.table("pets")
	assert_false(is_same(first, second), "reload() drops the cache")
	assert_eq_deep(first, second)


func test_unknown_table_is_null() -> void:
	assert_null(Content.table("no_such_table"))


# --- Types ------------------------------------------------------------------------------------

func _walk(node: Variant, path: String, floats: Dictionary, bad: Array) -> void:
	match typeof(node):
		TYPE_INT:
			if floats.has(path):
				bad.append("%s should be float" % path)
		TYPE_FLOAT:
			if not floats.has(path):
				bad.append("%s should be int" % path)
		TYPE_DICTIONARY:
			for k in node:
				_walk(node[k], path + "/" + String(k).replace("~", "~0").replace("/", "~1"), floats, bad)
		TYPE_ARRAY:
			for i in node.size():
				_walk(node[i], path + "/" + str(i), floats, bad)


func test_numbers_are_int_unless_float_path(file = use_parameters(Array(Content.names()))) -> void:
	var floats := {}
	for p in Content.manifest()["files"][file + ".json"]["float_paths"]:
		floats[p] = true
	var bad: Array = []
	_walk(Content.table(file), "", floats, bad)
	assert_eq(bad.slice(0, 5), [], file)
	# and every float path really exists with float type
	var seen := {}
	_collect_floats(Content.table(file), "", seen)
	assert_eq(seen.size(), floats.size(), file + ": float_paths count")


func _collect_floats(node: Variant, path: String, seen: Dictionary) -> void:
	match typeof(node):
		TYPE_FLOAT:
			seen[path] = true
		TYPE_DICTIONARY:
			for k in node:
				_collect_floats(node[k], path + "/" + String(k).replace("~", "~0").replace("/", "~1"), seen)
		TYPE_ARRAY:
			for i in node.size():
				_collect_floats(node[i], path + "/" + str(i), seen)


func test_spot_types() -> void:
	assert_eq(typeof(Content.monster("gnawer")["hp"]), TYPE_INT)
	assert_eq(typeof(Content.monster("gnawer")["dmg"][0]), TYPE_INT)
	assert_eq(typeof(Content.table("acts")["acts"]["opening"]["hp"]), TYPE_FLOAT, "ACTS hp is 2.0")
	assert_eq(typeof(Content.table("acts")["acts"]["opening"]["attack"]), TYPE_INT)
	assert_eq(Content.table("acts")["acts"]["featured"]["hp"], 3.0)
	assert_eq(typeof(Content.backstory("mixologist")["potion_mult"]), TYPE_FLOAT)
	assert_eq(typeof(Content.backstory("tradie")["craft_mult"]), TYPE_FLOAT, "0.5")
	assert_eq(typeof(Content.backstory("rideshare")["timer_bonus"]), TYPE_INT)
	assert_eq(typeof(Content.table("contracts")["power_naps"]["rest_mult"]), TYPE_INT, "rest_mult=2 is an int in Python")
	assert_eq(typeof(Content.table("contracts")["hazard_pay"]["gold_mult"]), TYPE_FLOAT, "2.0")
	assert_eq(typeof(Content.table("shop")["base_demand"]["tonic"]), TYPE_FLOAT, "3.0")
	assert_eq(Content.config("config")["RESPAWN_CAP"], 1.25)
	assert_eq(typeof(Content.config("config")["MAP_W"]), TYPE_INT)
	assert_eq(typeof(Content.config("showrunner")["DECAY"]), TYPE_FLOAT)
	assert_eq(typeof(Content.config("config")["SASS_LEVEL"]), TYPE_INT)


# --- Counts (Python: len of each table) ------------------------------------------------------

func test_counts_match_python() -> void:
	assert_eq(Content.table("achievements").size(), 33)
	var headliners := 0
	for k in Content.table("achievements"):
		if String(k).begins_with("headliner_"):
			headliners += 1
	assert_eq(headliners, 6)
	assert_eq(Content.table("practice_skills").size(), 20)
	assert_eq(Content.table("lines").size(), 41)
	assert_eq(Content.table("classes").size(), 9)
	assert_eq(Content.table("races").size(), 6)
	assert_eq(Content.table("pets").size(), 4)
	assert_eq(Content.table("monsters").size(), 8)
	assert_eq(Content.table("bosses").size(), 6)
	assert_eq(Content.table("backstories").size(), 8)
	assert_eq(Content.table("genders").size(), 3)
	assert_eq(Content.table("items")["items"].size(), 17)
	assert_eq(Content.table("floor_loot").size(), 15)
	assert_eq(Content.table("recipes").size(), 4)
	assert_eq(Content.table("contracts").size(), 4)
	assert_eq(Content.table("sponsor_gifts").size(), 5)
	assert_eq(Content.table("skills").size(), 9)
	assert_eq(Content.table("loot_boxes").size(), 5)
	assert_eq(Content.table("attributes").size(), 5)


func test_counts_agree_with_python_dump() -> void:
	assert_true(_ref.has("counts"), "set CONTENT_REF (scripts/gd_test.sh does this)")
	var c: Dictionary = _ref.get("counts", {})
	assert_eq(Content.table("monsters").size(), int(c.get("monsters", -1)))
	assert_eq(Content.table("pets").size(), int(c.get("pets", -1)))
	assert_eq(Content.table("races").size(), int(c.get("races", -1)))
	assert_eq(Content.table("classes").size(), int(c.get("classes", -1)))
	assert_eq(Content.table("achievements").size(), int(c.get("achievements", -1)))
	assert_eq(Content.table("bosses").size(), int(c.get("headliners", -1)))
	assert_eq(Content.table("practice_skills").size(), int(c.get("practice_skills", -1)))
	assert_eq(Content.table("lines").size(), int(c.get("lines", -1)))
	assert_eq(Content.table("items")["items"].size(), int(c.get("items", -1)))
	assert_eq(Content.table("floor_loot").size(), int(c.get("floor_loot", -1)))


# --- Python order and structure ---------------------------------------------------------------

func test_key_order_is_python_insertion_order() -> void:
	assert_eq(Array(Content.table("monsters").keys()),
		["gnawer", "goblin", "vacbot", "skeleton", "brute", "cultist", "golem", "stalker"])
	assert_eq(Array(Content.table("pets").keys()), ["cat", "dog", "budgie", "mouse"])
	assert_eq(Array(Content.table("races").keys()), ["human", "elf", "dwarf", "hobgoblin", "bog_troll", "houseplant"])
	assert_eq(Array(Content.table("genders").keys()), ["female", "male", "nonbinary"])
	assert_eq(Array(Content.table("shop")["base_demand"].keys()),
		["tonic", "brew", "elixir", "popper", "fireworks", "jersey", "vest", "pan", "cleaver"])
	assert_eq(Array(Content.table("loot_boxes").keys()), ["bronze", "silver", "gold", "platinum", "legendary"])
	var ach: Array = Content.table("achievements").keys()
	assert_eq(ach[0], "first_blood")
	assert_eq(ach[26], "nap_champion")
	assert_eq(ach[27], "headliner_1")
	assert_eq(ach[32], "headliner_6")


func test_helpers() -> void:
	assert_eq(Content.monster("goblin")["name"], "Knockoff Goblin")
	assert_eq(Content.item("pan")["dice"], [1, 6])
	assert_eq(Content.fists()["style"], "unarmed")
	assert_eq(Content.boss(3)["name"], "Foreman Gristle")
	assert_true(Content.boss(6)["final"])
	assert_eq(Content.box("gold")["table"][0], {"item": "cleaver", "weight": 3})
	assert_eq(Content.klass("alchemist")["pairs"], ["mixologist", "parent"])
	assert_eq(Content.skill("arc_bolt")["range"], 6)
	assert_eq(Content.pet("cat")["default_name"], "Mittens")
	assert_eq(Content.config("encounter")["PARTS"], ["move", "action", "bonus"])
	assert_eq(Content.race("hobgoblin")["crit_range"], 3)
	assert_eq(Content.gender("male")["address"], "sir")


func test_optional_keys_only_where_python_has_them() -> void:
	assert_false(Content.monster("gnawer").has("ranged"))
	assert_eq(Content.monster("cultist")["ranged"], 5)
	assert_false(Content.boss(1).has("final"))
	assert_eq(Content.boss(4)["ranged"], 5)


func test_achievement_rules_are_data() -> void:
	var a: Dictionary = Content.table("achievements")
	assert_eq(a["close_call"]["rule"], {"kind": "field_lte_floordiv", "field": "player_hp", "of": "player_max_hp", "div": 4})
	assert_eq(a["cutting_it_fine"]["rule"]["frac"], 0.1)
	assert_eq(a["hoarder"]["rule"], {"kind": "world_gte", "stat": "inventory_len", "n_config": "INVENTORY_SIZE"})
	assert_eq(a["underfoot"]["rule"]["rules"].size(), 2)
	assert_eq(a["headliner_3"]["name"], "Show Stopper: Foreman Gristle")
	assert_eq(a["headliner_3"]["tier"], "gold")
	assert_eq(a["headliner_3"]["rule"], {"kind": "field_eq", "field": "depth", "value": 3})
	for k in a:
		assert_true(a[k].has("rule"), k)


func test_lines_placeholders_are_plain() -> void:
	var rx := RegEx.new()
	rx.compile("\\{[^{}]*\\}")
	var plain := RegEx.new()
	plain.compile("^\\{[A-Za-z_][A-Za-z_0-9]*\\}$")
	var n := 0
	for ev in Content.table("lines"):
		for pool in Content.table("lines")[ev]:
			for text in Content.table("lines")[ev][pool]:
				assert_false(String(text).contains("{{"), ev)
				for m in rx.search_all(text):
					n += 1
					assert_not_null(plain.search(m.get_string()), "%s: %s" % [ev, m.get_string()])
	assert_gt(n, 100)


# --- Every leaf of every table against the Python dump -----------------------------------------

func test_every_leaf_matches_python(name = use_parameters(Array(Content.names()))) -> void:
	if not _ref.has("tables"):
		fail_test("CONTENT_REF not loaded (scripts/gd_test.sh sets it)")
		return
	var want: Array = _ref["tables"].get(name, [])
	var got: Array = []
	_flat(Content.table(name), "", got)
	assert_gt(want.size(), 0, name)
	assert_eq(got.size(), want.size(), name + ": leaf count")
	var shown := 0
	for i in mini(got.size(), want.size()):
		if got[i] != want[i]:
			assert_eq(got[i], want[i], "%s leaf %d" % [name, i])
			shown += 1
			if shown >= 3:
				break
	if shown == 0 and got.size() == want.size():
		pass_test()

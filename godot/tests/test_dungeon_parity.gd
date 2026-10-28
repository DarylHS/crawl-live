extends TestCase
## Parity of the dungeon with Python (port plan 6.4, slice S3). scripts/gd_test.sh produces
##  - FLOOR_TRACES: a directory with floors_<seed>.jsonl from `py_trace.py --floor-only` (seeds 0-19 in the suite), and
##  - DUNGEON_FIXTURES: FOV and distance-map digests from scripts/make_dungeon_fixtures.py.
## The full acceptance run (seeds 0-199) is done with tools/trace.gd and scripts/parity_diff.py.


func _need(var_name: String) -> String:
	var v := OS.get_environment(var_name)
	if v == "":
		fail_test("%s is not set (run through scripts/gd_test.sh)" % var_name)
	return v


func test_floor_traces_match_python(seed_value = use_parameters(range(20))) -> void:
	var dir := _need("FLOOR_TRACES")
	if dir == "":
		return
	var path := "%s/floors_%d.jsonl" % [dir, seed_value]
	if not FileAccess.file_exists(path):
		fail_test("missing " + path)
		return
	var py: Array = []
	for line in FileAccess.get_file_as_string(path).split("\n", false):
		py.append(JSON.parse_string(line))
	var mine := TraceFloors.run_floors(seed_value, 6)
	assert_eq(mine.size(), py.size())
	for i in mini(mine.size(), py.size()):
		# through JSON text so both sides carry the same number types as the Python file
		var got: Dictionary = JSON.parse_string(PyJson.dumps(mine[i], false))
		var want: Dictionary = py[i]
		if want["k"] == "header":
			want["impl"] = got["impl"]
		var diff := TestCase.strict_diff(got, want)
		if diff != "":
			var which: String = "header" if want["k"] == "header" else str(int(want["depth"]))
			fail_test("seed %d record %s differs: %s" % [seed_value, which, diff.left(200)])
			return
	assert_true(true)


## Debug dump: the visible set as rows of '#' (seen) and '.', only the rows that contain something.
static func _fov_rows(fl: DungeonFloor, vis: Dictionary) -> String:
	var lines := PackedStringArray()
	for y in fl.height:
		var row := ""
		for x in fl.width:
			row += "#" if vis.has(Vector2i(x, y)) else "."
		if "#" in row:
			lines.append("%2d %s" % [y, row])
	return "\n".join(lines)


## Debug dump: a distance map as rows (distance mod 10, '.' unreachable), only rows with something reachable.
static func _dist_rows(fl: DungeonFloor, d: PackedInt32Array) -> String:
	var lines := PackedStringArray()
	for y in fl.height:
		var row := ""
		for x in fl.width:
			var v := d[y * fl.width + x]
			row += "." if v < 0 else str(v % 10)
		if row.replace(".", "") != "":
			lines.append("%2d %s" % [y, row])
	return "\n".join(lines)


static func _bitmap_digest(fl: DungeonFloor, vis: Dictionary) -> String:
	var b := PackedByteArray()
	b.resize(fl.width * fl.height)
	for p in vis:
		b[p.y * fl.width + p.x] = 1
	for i in b.size():
		b[i] += 48
	return TraceFloors.h16(b.get_string_from_ascii())


func test_fov_and_distance_maps_match_python() -> void:
	var path := _need("DUNGEON_FIXTURES")
	if path == "":
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(path))
	var rngs := {}
	var fov_checked := 0
	var dist_checked := 0
	for entry in data["floors"]:
		var seed_value := int(entry["seed"])
		var depth := int(entry["depth"])
		if not rngs.has(seed_value):
			rngs[seed_value] = PyRandom.new(seed_value)
		var fl := Dungeon.generate_floor(rngs[seed_value], depth)
		for row in entry["fov"]:
			var vis := Dungeon.compute_fov(fl, int(row[0]), int(row[1]), int(row[2]))
			if vis.size() != int(row[3]) or _bitmap_digest(fl, vis) != row[4]:
				fail_test("FOV differs: seed %d depth %d origin %d,%d radius %d" % [
						seed_value, depth, int(row[0]), int(row[1]), int(row[2])])
				gut.p("Godot visible set (%d tiles, Python %d):\n%s" % [vis.size(), int(row[3]), _fov_rows(fl, vis)])
				return
			fov_checked += 1
		for row in entry["dist"]:
			var d := fl.distance_map(int(row[0]), int(row[1]), int(row[2]), int(row[3]) != 0)
			var reach := 0
			var mx := -1
			for v in d:
				if v >= 0:
					reach += 1
				mx = maxi(mx, v)
			var digest := TraceFloors.h16(",".join(Array(d).map(func(v: int) -> String: return str(v))))
			if reach != int(row[4]) or mx != int(row[5]) or digest != row[6]:
				fail_test("distance map differs: seed %d depth %d start %d,%d max_dist %d avoid_safe %d" % [
						seed_value, depth, int(row[0]), int(row[1]), int(row[2]), int(row[3])])
				gut.p("Godot map (reach %d max %d, Python reach %d max %d):\n%s" % [
						reach, mx, int(row[4]), int(row[5]), _dist_rows(fl, d)])
				return
			dist_checked += 1
	assert_gt(fov_checked, 1000)
	assert_gt(dist_checked, 1000)

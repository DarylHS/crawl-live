extends TestCase
## Port of tests/test_dungeon.py: reachability, stairs and safe room placement, the enclosed safe room,
## the wall border, and FOV on a hand-built floor. Seeds are parametrised like pytest's SEEDS.

const WALL := DungeonFloor.WALL
const FLOOR := DungeonFloor.FLOOR
const STAIRS := DungeonFloor.STAIRS
const FURNITURE := DungeonFloor.FURNITURE


func test_every_open_tile_reachable_from_start(seed_value = use_parameters(range(25))) -> void:
	var rng := PyRandom.new(seed_value)
	for depth in range(1, GameConfig.NUM_FLOORS + 1):
		var fl := Dungeon.generate_floor(rng, depth)
		var sc := fl.start_room.centre()
		var dist := fl.distance_map(sc.x, sc.y)
		for y in fl.height:
			for x in fl.width:
				if fl.walkable(x, y):
					if dist[y * fl.width + x] < 0:
						fail_test("unreachable tile seed %d depth %d at %d,%d" % [seed_value, depth, x, y])
						return
	assert_true(true)


func test_stairs_and_safe_room_placement(seed_value = use_parameters(range(25))) -> void:
	var fl := Dungeon.generate_floor(PyRandom.new(seed_value), 1)
	assert_eq(fl.stairs.size(), GameConfig.STAIRS_PER_FLOOR)
	for s in fl.stairs:
		assert_eq(int(fl.tiles[s.y][s.x]), STAIRS)
		assert_false(fl.safe[s.y][s.x] != 0)
		assert_false(fl.start_room.contains(s.x, s.y))
	assert_true(fl.safe_room != fl.start_room)   # identity, as `is not`
	var sc := fl.start_room.centre()
	assert_false(fl.is_safe(sc.x, sc.y))
	var total := 0
	for row in fl.safe:
		for v in (row as PackedByteArray):
			total += v
	assert_eq(total, fl.safe_room.w * fl.safe_room.h + 1)   # + doorway


func test_safe_room_is_enclosed_with_one_doorway_and_furniture(seed_value = use_parameters(range(10))) -> void:
	var fl := Dungeon.generate_floor(PyRandom.new(seed_value), 2)
	var r := fl.safe_room
	var openings: Array = []
	for x in range(r.x - 1, r.x + r.w + 1):
		for y in range(r.y - 1, r.y + r.h + 1):
			if not r.contains(x, y) and fl.tiles[y][x] != WALL:
				openings.append(Vector2i(x, y))
	assert_eq(openings, [fl.safe_door])
	var kinds: Array = fl.furniture.values()
	kinds.sort()
	assert_eq(kinds, ["bed", "bench", "counter"])
	for p in fl.furniture:
		assert_true(r.contains(p.x, p.y) and fl.tiles[p.y][p.x] == FURNITURE)


func test_border_is_always_wall() -> void:
	var fl := Dungeon.generate_floor(PyRandom.new(1), 3)
	for x in fl.width:
		assert_true(fl.tiles[0][x] == WALL and fl.tiles[fl.height - 1][x] == WALL)
	for y in fl.height:
		assert_true(fl.tiles[y][0] == WALL and fl.tiles[y][fl.width - 1] == WALL)


func _open_box(w: int = 21, h: int = 21) -> DungeonFloor:
	var fl := DungeonFloor.new(w, h, 1)
	for y in range(1, h - 1):
		for x in range(1, w - 1):
			fl.tiles[y][x] = FLOOR
	return fl


func test_fov_open_room_respects_radius() -> void:
	var fl := _open_box()
	var vis := Dungeon.compute_fov(fl, 10, 10, 5)
	assert_true(vis.has(Vector2i(10, 10)) and vis.has(Vector2i(14, 10)) and vis.has(Vector2i(10, 6)))
	assert_false(vis.has(Vector2i(16, 10)))
	for p in vis:
		assert_true(fl.in_bounds(p.x, p.y))


func test_fov_blocked_by_wall() -> void:
	var fl := _open_box()
	for y in range(1, 20):
		fl.tiles[y][12] = WALL   # a full-height wall
	var vis := Dungeon.compute_fov(fl, 10, 10, 8)
	assert_true(vis.has(Vector2i(12, 10)))    # the wall itself is seen
	assert_false(vis.has(Vector2i(14, 10)))   # but not what's behind it


# --- extras beyond the pytest file: the small helpers the rest of the port leans on ---

func test_room_helpers() -> void:
	var a := DungeonRoom.new(2, 3, 5, 4)
	assert_eq(a.centre(), Vector2i(4, 5))
	assert_true(a.contains(2, 3) and a.contains(6, 6))
	assert_false(a.contains(7, 3) or a.contains(2, 7))
	assert_true(a.intersects(DungeonRoom.new(7, 3, 3, 3)))        # one tile gap needed: pad 1
	assert_false(a.intersects(DungeonRoom.new(8, 3, 3, 3)))
	assert_true(a.intersects(DungeonRoom.new(7, 3, 3, 3), 0) == false)
	var t := DungeonRoom.new(1, 1, 2, 2).tiles()
	assert_eq(t, [Vector2i(1, 1), Vector2i(2, 1), Vector2i(1, 2), Vector2i(2, 2)] as Array[Vector2i])


func test_distance_map_limits_and_safe_avoidance() -> void:
	var fl := _open_box(9, 5)
	var d := fl.distance_map(1, 1)
	assert_eq(d[1 * 9 + 1], 0)
	assert_eq(d[3 * 9 + 7], 6)
	assert_eq(d[0], -1)   # wall corner
	var near := fl.distance_map(1, 1, 2)
	assert_eq(near[1 * 9 + 3], 2)
	assert_eq(near[1 * 9 + 4], -1)
	assert_eq(fl.distance_map(1, 1, 0)[1 * 9 + 2], -1)
	fl.safe[2][4] = 1
	fl.forget_paths()
	assert_eq(fl.distance_map(1, 1)[2 * 9 + 4], 3)
	assert_eq(fl.distance_map(1, 1, -1, true)[2 * 9 + 4], -1)
	assert_eq(fl.distance_map(4, 2, -1, true)[2 * 9 + 5], 1)   # a safe start is still expanded


func test_generated_floor_is_deterministic_per_rng_state() -> void:
	var a := Dungeon.generate_floor(PyRandom.new(3), 1)
	var b := Dungeon.generate_floor(PyRandom.new(3), 1)
	assert_eq(TraceFloors.floor_fp(a), TraceFloors.floor_fp(b))

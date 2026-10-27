class_name Dungeon
extends RefCounted
## Floor generation and field of view (crawler/dungeon.py, functions part).
##
## A floor is a grid of tiles carved into rooms joined by L-shaped corridors. Rooms are connected in
## creation order, which guarantees every room is reachable; a few extra corridors add loops. One room
## is the safe room and the rooms furthest from the start hold the stairwells.
## All randomness goes through the PyRandom passed in, in Python's exact draw order.

const WALL := DungeonFloor.WALL
const FLOOR := DungeonFloor.FLOOR
const STAIRS := DungeonFloor.STAIRS
const FURNITURE := DungeonFloor.FURNITURE
const NEIGHBOURS_8 := DungeonFloor.NEIGHBOURS_8

## Recursive shadowcasting octants (xx, xy, yx, yy).
const _OCTANTS: Array = [[1, 0, 0, 1], [0, 1, 1, 0], [0, -1, 1, 0], [-1, 0, 0, 1],
		[-1, 0, 0, -1], [0, -1, -1, 0], [0, 1, -1, 0], [1, 0, 0, -1]]


# --- Generation -----------------------------------------------------------

static func _carve_room(fl: DungeonFloor, room: DungeonRoom) -> void:
	for t in room.tiles():
		fl.tiles[t.y][t.x] = DungeonFloor.FLOOR


static func _carve_corridor(fl: DungeonFloor, rng: PyRandom, a: Vector2i, b: Vector2i) -> void:
	var x1 := a.x
	var y1 := a.y
	var x2 := b.x
	var y2 := b.y
	var corner: Vector2i
	if rng.random() < 0.5:
		corner = Vector2i(x2, y1)
	else:
		corner = Vector2i(x1, y2)
	var legs: Array = [[Vector2i(x1, y1), corner], [corner, Vector2i(x2, y2)]]
	for leg in legs:
		var s: Vector2i = leg[0]
		var e: Vector2i = leg[1]
		for x in range(mini(s.x, e.x), maxi(s.x, e.x) + 1):
			for y in range(mini(s.y, e.y), maxi(s.y, e.y) + 1):
				fl.tiles[y][x] = DungeonFloor.FLOOR


static func _random_room(rng: PyRandom, width: int, height: int) -> DungeonRoom:
	var w := rng.randint(GameConfig.ROOM_MIN_W, GameConfig.ROOM_MAX_W)
	var h := rng.randint(GameConfig.ROOM_MIN_H, GameConfig.ROOM_MAX_H)
	var rx := rng.randint(1, width - w - 1)
	var ry := rng.randint(1, height - h - 1)
	return DungeonRoom.new(rx, ry, w, h)


## Keeps trying until a floor passes every check (Python `while True`).
static func generate_floor(rng: PyRandom, depth: int, width: int = -1, height: int = -1) -> DungeonFloor:
	if width < 0:
		width = GameConfig.MAP_W
	if height < 0:
		height = GameConfig.MAP_H
	while true:
		var fl := _try_generate(rng, depth, width, height)
		if fl != null:
			return fl
	return null


static func _try_generate(rng: PyRandom, depth: int, width: int, height: int) -> DungeonFloor:
	var fl := DungeonFloor.new(width, height, depth)
	for _i in GameConfig.MAX_ROOMS * 15:
		if fl.rooms.size() >= GameConfig.MAX_ROOMS:
			break
		var room := _random_room(rng, width, height)
		var hit := false
		for r in fl.rooms:
			if room.intersects(r):
				hit = true
				break
		if hit:
			continue
		_carve_room(fl, room)
		if not fl.rooms.is_empty():
			_carve_corridor(fl, rng, fl.rooms[-1].centre(), room.centre())
		fl.rooms.append(room)

	# Need start + safe room + a room per stairwell, plus one for monsters.
	if fl.rooms.size() < GameConfig.STAIRS_PER_FLOOR + 3:
		return null

	for _i in GameConfig.EXTRA_CORRIDORS:
		var pair := rng.sample(fl.rooms, 2)
		_carve_corridor(fl, rng, (pair[0] as DungeonRoom).centre(), (pair[1] as DungeonRoom).centre())

	fl.start_room = fl.rooms[0]
	var sc := fl.start_room.centre()
	var dist := fl.distance_map(sc.x, sc.y)
	var others: Array = PyMath.stable_sort_by(fl.rooms.slice(1), func(r: DungeonRoom) -> int:
		var c := r.centre()
		return dist[c.y * width + c.x])
	if not _add_safe_room(fl, rng, dist):
		return null

	# Stairwells in the furthest rooms, on an interior tile away from walls.
	for room in others.slice(maxi(0, others.size() - GameConfig.STAIRS_PER_FLOOR) if GameConfig.STAIRS_PER_FLOOR > 0 else 0):
		var r: DungeonRoom = room
		var x := rng.randint(r.x + 1, r.x + r.w - 2)
		var y := rng.randint(r.y + 1, r.y + r.h - 2)
		fl.tiles[y][x] = DungeonFloor.STAIRS
		fl.stairs.append(Vector2i(x, y))
	return fl


## Build the safe room in solid rock: a small room with one doorway and a short corridor to the
## nearest open tile. Several candidate spots are found and the one about mid-way from the start wins.
static func _add_safe_room(fl: DungeonFloor, rng: PyRandom, dist: PackedInt32Array) -> bool:
	var w := GameConfig.SAFE_W
	var h := GameConfig.SAFE_H
	var candidates: Array = []   # [d, room, door, path, inward]
	for _i in 600:
		var rx := rng.randint(2, fl.width - w - 3)
		var ry := rng.randint(2, fl.height - h - 3)
		var room := DungeonRoom.new(rx, ry, w, h)
		var all_wall := true
		for y in range(room.y - 2, room.y + h + 2):
			for x in range(room.x - 2, room.x + w + 2):
				if fl.tiles[y][x] != DungeonFloor.WALL:
					all_wall = false
					break
			if not all_wall:
				break
		if not all_wall:
			continue
		var c := room.centre()
		var sides: Array = [[Vector2i(c.x, room.y - 1), Vector2i(0, -1)],
				[Vector2i(c.x, room.y + h), Vector2i(0, 1)],
				[Vector2i(room.x - 1, c.y), Vector2i(-1, 0)],
				[Vector2i(room.x + w, c.y), Vector2i(1, 0)]]
		rng.shuffle(sides)
		for side in sides:
			var door: Vector2i = side[0]
			var step: Vector2i = side[1]
			var path: Array[Vector2i] = [door]
			var x := door.x
			var y := door.y
			var broke := false
			for _j in 14:
				x += step.x
				y += step.y
				if not fl.in_bounds(x, y):
					broke = true
					break
				if fl.tiles[y][x] != DungeonFloor.WALL:
					var d: int = dist[y * fl.width + x]
					if d >= 0:
						candidates.append([d, room, door, path, Vector2i(-step.x, -step.y)])
					broke = true
					break
				path.append(Vector2i(x, y))
			if not broke:
				continue
			break
		if candidates.size() >= 24:
			break
	if candidates.is_empty():
		return false
	PyMath.stable_sort_in_place(candidates, func(cd: Array) -> int: return cd[0])
	var chosen: Array = candidates[PyMath.floordiv(candidates.size(), 2)]
	var sroom: DungeonRoom = chosen[1]
	var sdoor: Vector2i = chosen[2]
	var spath: Array = chosen[3]
	var inward: Vector2i = chosen[4]
	_carve_room(fl, sroom)
	for p in spath:
		fl.tiles[p.y][p.x] = DungeonFloor.FLOOR
	var marks: Array = sroom.tiles()
	marks.append(sdoor)
	for p in marks:
		fl.safe[p.y][p.x] = 1
	fl.safe_room = sroom
	fl.safe_door = sdoor
	fl.rooms.append(sroom)
	# Furniture along the wall opposite the door: bed, crafting bench, shop counter.
	var spots: Array[Vector2i] = []
	if inward.y != 0:
		var fy := sroom.y + (sroom.h - 1 if inward.y > 0 else 0)
		spots = [Vector2i(sroom.x, fy), Vector2i(sroom.x + PyMath.floordiv(sroom.w, 2), fy),
				Vector2i(sroom.x + sroom.w - 1, fy)]
	else:
		var fx := sroom.x + (sroom.w - 1 if inward.x > 0 else 0)
		spots = [Vector2i(fx, sroom.y), Vector2i(fx, sroom.y + PyMath.floordiv(sroom.h, 2)),
				Vector2i(fx, sroom.y + sroom.h - 1)]
	var kinds := ["bed", "bench", "counter"]
	for i in 3:
		var sp := spots[i]
		fl.tiles[sp.y][sp.x] = DungeonFloor.FURNITURE
		fl.furniture[sp] = kinds[i]
	fl.forget_paths()
	return true


# --- Field of view (recursive shadowcasting) -----------------------------

## Set of visible tiles as a Dictionary Vector2i -> true (membership only).
static func compute_fov(fl: DungeonFloor, ox: int, oy: int, radius: int = -1) -> Dictionary:
	if radius < 0:
		radius = GameConfig.FOV_RADIUS
	var visible := {Vector2i(ox, oy): true}
	for o in _OCTANTS:
		_cast(fl, ox, oy, 1, 1.0, 0.0, radius, o[0], o[1], o[2], o[3], visible)
	return visible


static func _cast(fl: DungeonFloor, cx: int, cy: int, row: int, start: float, end: float, radius: int,
		xx: int, xy: int, yx: int, yy: int, visible: Dictionary) -> void:
	if start < end:
		return
	var r2 := radius * radius
	var new_start := start
	for j in range(row, radius + 1):
		var dx := -j - 1
		var dy := -j
		var blocked := false
		while dx <= 0:
			dx += 1
			var x := cx + dx * xx + dy * xy
			var y := cy + dx * yx + dy * yy
			var l_slope := (dx - 0.5) / (dy + 0.5)
			var r_slope := (dx + 0.5) / (dy - 0.5)
			if start < r_slope:
				continue
			if end > l_slope:
				break
			var inside := fl.in_bounds(x, y)
			if inside and dx * dx + dy * dy < r2:
				visible[Vector2i(x, y)] = true
			var opaque: bool = (not inside) or fl.tiles[y][x] == DungeonFloor.WALL
			if blocked:
				if opaque:
					new_start = r_slope
					continue
				blocked = false
				start = new_start
			elif opaque and j < radius:
				blocked = true
				_cast(fl, cx, cy, j + 1, start, l_slope, radius, xx, xy, yx, yy, visible)
				new_start = r_slope
		if blocked:
			break

class_name DungeonFloor
extends RefCounted
## One generated floor (crawler/dungeon.py `Floor`): the tile grid, safe-room mask, explored mask,
## rooms, stairs, furniture and cached BFS neighbour lists.
##
## `tiles`, `safe` and `explored` are Arrays of PackedByteArray rows indexed [y][x]; safe and explored
## hold 0/1 (Python bools). `furniture` maps Vector2i to "bed" | "bench" | "counter" in insertion order.
## `safe_door` is null or a Vector2i. `distance_map` returns a flat PackedInt32Array (y * width + x),
## -1 for unreachable; `max_dist = -1` stands for Python's None.

const WALL := 0
const FLOOR := 1
const STAIRS := 2
const FURNITURE := 3   ## furniture blocks movement, not sight

const NEIGHBOURS_8: Array[Vector2i] = [
	Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1), Vector2i(-1, 0),
	Vector2i(1, 0), Vector2i(-1, 1), Vector2i(0, 1), Vector2i(1, 1)]

var width: int
var height: int
var depth: int
var tiles: Array = []      ## Array of PackedByteArray, tiles[y][x]
var safe: Array = []
var explored: Array = []
var rooms: Array[DungeonRoom] = []
var start_room: DungeonRoom = null
var safe_room: DungeonRoom = null
var stairs: Array[Vector2i] = []
var furniture: Dictionary = {}
var safe_door: Variant = null

var _adj_all: Array = []        ## empty until first use (Python: attribute absent)
var _adj_no_safe: Array = []


func _init(w: int, h: int, d: int) -> void:
	width = w
	height = h
	depth = d
	for _y in h:
		var trow := PackedByteArray()
		trow.resize(w)   # zero filled: WALL
		tiles.append(trow)
		var srow := PackedByteArray()
		srow.resize(w)
		safe.append(srow)
		var erow := PackedByteArray()
		erow.resize(w)
		explored.append(erow)


## True when (x, y) lies inside the grid.
func in_bounds(x: int, y: int) -> bool:
	return 0 <= x and x < width and 0 <= y and y < height


## True for FLOOR or STAIRS tiles inside the grid (furniture and walls block movement).
func walkable(x: int, y: int) -> bool:
	return in_bounds(x, y) and (tiles[y][x] == FLOOR or tiles[y][x] == STAIRS)


## True when (x, y) is in the safe room or its doorway (the caller keeps x, y in bounds).
func is_safe(x: int, y: int) -> bool:
	return safe[y][x] != 0


## Walkable 8-way neighbours of every open tile, as flat indices (see Python `_adjacency`).
func _adjacency(avoid_safe: bool) -> Array:
	var adj: Array = _adj_no_safe if avoid_safe else _adj_all
	if adj.is_empty():
		var w := width
		var h := height
		var ok: Array = []
		for y in h:
			var row := PackedByteArray()
			row.resize(w)
			for x in w:
				var t: int = tiles[y][x]
				row[x] = 1 if ((t == FLOOR or t == STAIRS) and not (avoid_safe and safe[y][x] != 0)) else 0
			ok.append(row)
		var none := PackedInt32Array()
		adj.resize(w * h)
		for i in w * h:
			adj[i] = none
		for y in h:
			for x in w:
				var t2: int = tiles[y][x]
				if t2 != FLOOR and t2 != STAIRS:
					continue
				var lst := PackedInt32Array()
				for n in NEIGHBOURS_8:
					var nx := x + n.x
					var ny := y + n.y
					if 0 <= nx and nx < w and 0 <= ny and ny < h and ok[ny][nx] != 0:
						lst.append(ny * w + nx)
				adj[y * w + x] = lst
		if avoid_safe:
			_adj_no_safe = adj
		else:
			_adj_all = adj
	return adj


## Drop the cached neighbour lists after the layout changes (generation only).
func forget_paths() -> void:
	_adj_all = []
	_adj_no_safe = []


## BFS step counts (8-way) from (sx, sy) as a flat array; -1 = unreachable. The start tile is always
## expanded, even if it is itself a safe tile. max_dist < 0 means no limit (Python None).
func distance_map(sx: int, sy: int, max_dist: int = -1, avoid_safe: bool = false) -> PackedInt32Array:
	var adj := _adjacency(avoid_safe)
	var dist := PackedInt32Array()
	dist.resize(width * height)
	dist.fill(-1)
	var start := sy * width + sx
	dist[start] = 0
	var frontier := PackedInt32Array([start])
	var d := 0
	while not frontier.is_empty() and (max_dist < 0 or d < max_dist):
		d += 1
		var nxt := PackedInt32Array()
		for i in frontier:
			for j in (adj[i] as PackedInt32Array):
				if dist[j] == -1:
					dist[j] = d
					nxt.append(j)
		frontier = nxt
	return dist

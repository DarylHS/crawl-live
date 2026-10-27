class_name DungeonRoom
extends RefCounted
## A rectangular room (crawler/dungeon.py `Room`). Plain data plus a few queries.

var x: int
var y: int
var w: int
var h: int


func _init(rx: int = 0, ry: int = 0, rw: int = 0, rh: int = 0) -> void:
	x = rx
	y = ry
	w = rw
	h = rh


## Python `centre` property: (x + w // 2, y + h // 2).
func centre() -> Vector2i:
	return Vector2i(x + PyMath.floordiv(w, 2), y + PyMath.floordiv(h, 2))


func contains(px: int, py: int) -> bool:
	return x <= px and px < x + w and y <= py and py < y + h


func intersects(other: DungeonRoom, pad: int = 1) -> bool:
	return (x - pad < other.x + other.w and other.x - pad < x + w
			and y - pad < other.y + other.h and other.y - pad < y + h)


## Every tile of the room, row-major (y outer, x inner), as Python's generator yields them.
func tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for ty in range(y, y + h):
		for tx in range(x, x + w):
			out.append(Vector2i(tx, ty))
	return out

class_name FxTargets
extends RefCounted
## Finding which creature an event is about. World events carry the monster's key ("goblin") but not
## where it stands, and the rules are not to change for the effects, so FxDirector looks the creature up
## in the World's own monster list at the moment of the event: the nearest one with that key (ties go to
## the first in the list, as the rules' own `min_by` does). Headless and pure: actors are plain
## dictionaries {"id": int, "key": String, "tile": Vector2i}.

## A snapshot of the monsters on this floor (instance id, key, tile).
static func snapshot(world: World) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in world.monsters:
		out.append({"id": m.get_instance_id(), "key": m.key, "tile": Vector2i(m.x, m.y)})
	return out


## Chebyshev distance, the rules' own measure of reach.
static func cheb(a: Vector2i, b: Vector2i) -> int:
	return maxi(absi(a.x - b.x), absi(a.y - b.y))


## The actor nearest `from`, only those with `key` when it is not "". Null when there is none.
static func nearest(actors: Array, from: Vector2i, key: String = "") -> Variant:
	var best: Variant = null
	var best_d := 1 << 30
	for a: Dictionary in actors:
		if key != "" and a["key"] != key:
			continue
		var d := cheb(a["tile"], from)
		if d < best_d:
			best_d = d
			best = a
	return best

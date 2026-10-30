class_name FxTargets
extends RefCounted
## Finding which creature an event is about. World events carry the monster's key ("goblin") but not
## where it stands, and the rules are not to change for the effects, so FxDirector looks the creature up
## in the World's own monster list at the moment of the event: the nearest one with that key (ties go to
## the first in the list, as the rules' own `min_by` does). Headless and pure: actors are plain
## dictionaries {"id": int, "key": String, "tile": Vector2i, "hp": int, "ref": Monster}; `ref` lets a
## dead monster's last tile be read (the object outlives its removal from the list).

## A snapshot of the monsters on this floor (instance id, key, tile).
static func snapshot(world: World) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for m in world.monsters:
		out.append({"id": m.get_instance_id(), "key": m.key, "tile": Vector2i(m.x, m.y), "hp": m.hp, "ref": m})
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


## The actor of an earlier snapshot that is no longer in `live_ids` (a set of instance ids) and not in `consumed`
## (ids already matched to an earlier death), of `key` when it is not "", nearest `from`: the monster that just
## died. Identity, not position, says who died, so riposte, skill, bomb and pet kills all find the right one
## even with several of a kind about. Null when none.
static func gone(before: Array, live_ids: Dictionary, from: Vector2i, key: String, consumed: Dictionary) -> Variant:
	var candidates: Array = []
	for a: Dictionary in before:
		if live_ids.has(a["id"]) or consumed.has(a["id"]):
			continue
		candidates.append(a)
	return nearest(candidates, from, key)


## The monster of `now` (a snapshot) whose HP is lower than in `before`, nearest `from`: who a pet bite just
## hurt. Null when none dropped.
static func hurt(before: Array, now: Array, from: Vector2i) -> Variant:
	var old := {}
	for a: Dictionary in before:
		old[a["id"]] = a["hp"]
	var dropped: Array = []
	for a: Dictionary in now:
		if old.has(a["id"]) and int(a["hp"]) < int(old[a["id"]]):
			dropped.append(a)
	return nearest(dropped, from)


## An actor entry with its tile read from the monster now (a monster that died keeps its last tile).
static func at_now(a: Dictionary) -> Dictionary:
	var out := a.duplicate()
	var m: Monster = a["ref"]
	out["tile"] = Vector2i(m.x, m.y)
	return out

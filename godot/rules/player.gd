class_name Player
extends Entity
## The player's combat numbers are derived from attributes, level and gear by
## World.refresh_stats; attrs holds the base scores the player has bought (Player in
## crawler/entities.py).

var level: int = 1
var xp: int = 0
var kills: int = 0
var attrs: Dictionary = _base_attrs()
var stat_points: int = Attributes.START_POINTS


## {k: BASE_SCORE for k in ATTRS}
static func _base_attrs() -> Dictionary:
	var d := {}
	for k in Attributes.keys():
		d[k] = Attributes.BASE_SCORE
	return d


func xp_to_next() -> int:
	return 30 + 40 * (level - 1)


## Add XP and apply any level-ups; returns the list of new levels.
func gain_xp(amount: int) -> Array[int]:
	xp += amount
	var gained: Array[int] = []
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		stat_points += Attributes.POINTS_PER_LEVEL
		gained.append(level)
	return gained


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["level"] = level
	d["xp"] = xp
	d["kills"] = kills
	d["attrs"] = attrs.duplicate()
	d["stat_points"] = stat_points
	return d


static func from_dict(d: Dictionary) -> Player:
	var p := Player.new()
	p._load(d)
	return p

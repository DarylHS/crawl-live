class_name Entity
extends RefCounted
## Anything that fights (Entity dataclass in crawler/entities.py). Combat reads: attack (to-hit
## bonus), ac (Armour Class), dmg_n / dmg_die / dmg_bonus (damage dice, e.g. 1d8+2), dr (damage
## reduction) and crit_range (how many top d20 faces crit; 1 means only a natural 20).
## Identity equality, as `@dataclass(eq=False)`. `colour` is an [r, g, b] int Array.

var x: int
var y: int
var name: String
var glyph: String
var colour: Array
var max_hp: int
var hp: int
var attack: int = 0
var ac: int = 10
var dmg_n: int = 1
var dmg_die: int = 4
var dmg_bonus: int = 0
var dr: int = 0
var crit_range: int = 1

var alive: bool:
	get:
		return hp > 0


func _init(p_x: int = 0, p_y: int = 0, p_name: String = "", p_glyph: String = "",
		p_colour: Array = [0, 0, 0], p_max_hp: int = 0, p_hp: int = 0) -> void:
	x = p_x
	y = p_y
	name = p_name
	glyph = p_glyph
	colour = p_colour
	max_hp = p_max_hp
	hp = p_hp


func take_damage(amount: int) -> int:
	var dealt := mini(hp, amount)
	hp -= dealt
	return dealt


func heal(amount: int) -> int:
	var healed := mini(max_hp - hp, amount)
	hp += healed
	return healed


func damage_text() -> String:
	return Dice.fmt(dmg_n, dmg_die, dmg_bonus)


## dataclasses.asdict in field order (the save layout). Subclasses append their own fields.
func to_dict() -> Dictionary:
	return {
		"x": x, "y": y, "name": name, "glyph": glyph, "colour": colour.duplicate(),
		"max_hp": max_hp, "hp": hp, "attack": attack, "ac": ac, "dmg_n": dmg_n,
		"dmg_die": dmg_die, "dmg_bonus": dmg_bonus, "dr": dr, "crit_range": crit_range,
	}


## Set every field present in `d` (the `cls(**d)` of save.py `_entity`, colour copied). Fields
## missing from `d` keep their defaults; an unknown key is a push_error and is skipped. Called by the subclasses' from_dict.
func _load(d: Dictionary) -> void:
	var known := {}
	for prop in get_property_list():
		if prop["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE:
			known[prop["name"]] = true
	for k in d:
		if not known.has(k):
			push_error("Entity._load: unexpected field '%s' (Python's cls(**d) would raise)" % str(k))
			continue
		if k == "colour":
			colour = (d[k] as Array).duplicate()
		elif k == "attrs":
			set(k, (d[k] as Dictionary).duplicate())
		else:
			set(k, d[k])

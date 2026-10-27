class_name Monster
extends Entity
## A monster, boss or Act (Monster in crawler/entities.py). Monsters are plain data in
## monsters.json so new ones can be added without code.

var key: String = ""
var xp_value: int = 0
var alerted: bool = false
var unseen_turns: int = 0
var ranged: int = 0           ## attack range in tiles; 0 = melee only
var boss: bool = false
var phase: int = 1            ## bosses change behaviour as they lose HP
var stunned: int = 0          ## turns left unable to act
var save: int = 0             ## bonus on saving throws (e.g. against bombs)
var tier: String = ""         ## "" | "opening" | "featured" | "headliner" (boss tiers)
var base: String = ""         ## for Acts: the monster they're an elite version of

# Bosses have proper names ("Foreman Gristle"), so they never take an article.
var the: String:
	get:
		return name if boss else "the " + name

var The: String:
	get:
		return name if boss else "The " + name

var a: String:
	get:
		if boss:
			return name
		return ("an " if "AEIOU".contains(name.substr(0, 1)) else "a ") + name


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["key"] = key
	d["xp_value"] = xp_value
	d["alerted"] = alerted
	d["unseen_turns"] = unseen_turns
	d["ranged"] = ranged
	d["boss"] = boss
	d["phase"] = phase
	d["stunned"] = stunned
	d["save"] = save
	d["tier"] = tier
	d["base"] = base
	return d


static func from_dict(d: Dictionary) -> Monster:
	var m := Monster.new()
	m._load(d)
	return m

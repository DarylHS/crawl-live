class_name Pet
extends Entity
## A companion (Pet in crawler/entities.py). Pet AI lives in ai.gd (a later slice).

var species: String = ""
var level: int = 1
var xp: int = 0
var kills: int = 0
var mode: String = "follow"   ## "follow" | "stay" | "attack"
var cooldown: int = 0         ## turns until the ability is ready
var downed: bool = false
var enraged: int = 0          ## turns of double damage left (Beastmaster's Rile Up)


func xp_to_next() -> int:
	return 30 + 35 * (level - 1)


## Add XP and apply level-ups; returns the list of new levels.
func gain_xp(amount: int) -> Array[int]:
	xp += amount
	var gained: Array[int] = []
	while xp >= xp_to_next():
		xp -= xp_to_next()
		level += 1
		max_hp += 4
		hp = mini(max_hp, hp + 4)
		dmg_bonus += 1
		if PyMath.mod(level, 2) == 0:
			attack += 1
		if PyMath.mod(level, 3) == 0:
			ac += 1
		gained.append(level)
	return gained


func to_dict() -> Dictionary:
	var d := super.to_dict()
	d["species"] = species
	d["level"] = level
	d["xp"] = xp
	d["kills"] = kills
	d["mode"] = mode
	d["cooldown"] = cooldown
	d["downed"] = downed
	d["enraged"] = enraged
	return d


static func from_dict(d: Dictionary) -> Pet:
	var p := Pet.new()
	p._load(d)
	return p

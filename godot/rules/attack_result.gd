class_name AttackResult
extends RefCounted
## The outcome of one swing (AttackResult dataclass in crawler/combat.py).

var hit: bool
var crit: bool
var damage: int
var killed: bool
var roll: int = 0     ## the d20 face kept
var total: int = 0    ## roll + attack bonus
var target: int = 0   ## the AC it was rolled against


func _init(p_hit: bool = false, p_crit: bool = false, p_damage: int = 0, p_killed: bool = false,
		p_roll: int = 0, p_total: int = 0, p_target: int = 0) -> void:
	hit = p_hit
	crit = p_crit
	damage = p_damage
	killed = p_killed
	roll = p_roll
	total = p_total
	target = p_target


## "20", "1" or "" (Python returns None for anything else; test truthiness the same way).
func natural() -> String:
	if roll == 20:
		return "20"
	if roll == 1:
		return "1"
	return ""


## 'd20 14+3=17 vs AC 12' for the message log.
func dice_text() -> String:
	var bonus := total - roll
	return "d20 %d%s=%d vs AC %d" % [roll, PyFmt.signed_int(bonus), total, target]

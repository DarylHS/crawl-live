class_name Combat
extends RefCounted
## Attack resolution with visible dice (crawler/combat.py).
##
## An attack is d20 + attack bonus against the target's Armour Class (AC). A natural 1 always
## misses; a natural 20 always hits and is a critical (the crit range can widen, e.g. the
## Hobgoblin crits on 17-20). A hit rolls the attacker's damage dice (twice as many dice on a
## crit), adds their damage bonus, then subtracts the target's damage reduction (DR), minimum 1.
##
## hit_chance and expected_damage are exact, so the Analyst's Scout Report and the sponsor deal
## previews show true odds.

static func hit_chance(attacker: Entity, defender: Entity, advantage: int = 0) -> float:
	return Dice.chance_to_hit(attacker.attack, defender.ac, attacker.crit_range, advantage)[0]


static func crit_chance(attacker: Entity, advantage: int = 0) -> float:
	return Dice.chance_to_hit(0, 99, attacker.crit_range, advantage)[1]


static func _damage(base: int, defender: Entity) -> int:
	return maxi(1, base - defender.dr)


## Mean damage of `dice_n` dice per swing: Python's sum() (Neumaier, PyMath.fsum_py) over the
## distribution in its insertion order.
static func _mean(attacker: Entity, defender: Entity, dice_n: int, mult: float, bonus: int) -> float:
	var terms: Array = []
	var dist := Dice.dice_distribution(dice_n, attacker.dmg_die)
	for t in dist:
		var p: float = dist[t]
		terms.append(p * _damage(PyMath.round_half_even((t + attacker.dmg_bonus) * mult) + bonus, defender))
	return PyMath.fsum_py(terms)


## Expected damage per swing, including misses and crits.
static func expected_damage(attacker: Entity, defender: Entity, mult: float = 1, bonus: int = 0) -> float:
	var chances := Dice.chance_to_hit(attacker.attack, defender.ac, attacker.crit_range)
	var p_hit: float = chances[0]
	var p_crit: float = chances[1]
	var n := attacker.dmg_n
	return (p_hit - p_crit) * _mean(attacker, defender, n, mult, bonus) \
		+ p_crit * _mean(attacker, defender, 2 * n, mult, bonus)


## Resolve one swing. mult scales the dice and damage bonus, bonus adds flat damage afterwards,
## crit_bonus widens the crit range, sure means it can't miss. Draws: the d20 (two with
## advantage), then the damage dice on a hit.
static func attack(attacker: Entity, defender: Entity, rng: PyRandom, mult: float = 1,
		sure: bool = false, bonus: int = 0, crit_bonus: int = 0, advantage: int = 0) -> AttackResult:
	var face: int = Dice.d20(rng, advantage)[0]
	var total := face + attacker.attack
	var crit := face > 20 - (attacker.crit_range + crit_bonus)
	var hit := sure or crit or (face != 1 and total >= defender.ac)
	if not hit:
		return AttackResult.new(false, false, 0, false, face, total, defender.ac)
	var dice_n := attacker.dmg_n * (2 if crit else 1)
	var base := PyMath.round_half_even((Dice.roll(rng, dice_n, attacker.dmg_die) + attacker.dmg_bonus) * mult) + bonus
	var dmg := defender.take_damage(_damage(base, defender))
	return AttackResult.new(true, crit, dmg, not defender.alive, face, total, defender.ac)


## d20 + bonus against a DC. Returns [saved, face].
static func saving_throw(rng: PyRandom, bonus: int, dc: int) -> Array:
	var face: int = Dice.d20(rng)[0]
	return [face != 1 and (face == 20 or face + bonus >= dc), face]

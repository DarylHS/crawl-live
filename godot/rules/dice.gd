class_name Dice
extends RefCounted
## Dice: d20 rolls, damage dice and their exact odds (crawler/dice.py).
##
## Rolls use the World's seeded PyRandom so a run replays exactly. The exact helpers
## (chance_to_hit, dice_distribution) let the Analyst, the fun facts and the tests show true
## probabilities rather than simulated ones. Pure static functions.

## lru_cache analogue for dice_distribution, keyed Vector2i(n, sides). The cached Dictionary is
## shared, as in Python; callers never mutate it.
static var _dist_cache: Dictionary = {}


## Roll a d20. advantage > 0 keeps the higher of two, < 0 the lower. Returns [kept, all_rolls]
## (Python's tuple (kept, rolls)). With advantage the two draws are made first then second.
static func d20(rng: PyRandom, advantage: int = 0) -> Array:
	if advantage == 0:
		var r := rng.randint(1, 20)
		return [r, [r]]
	var first := rng.randint(1, 20)
	var second := rng.randint(1, 20)
	var kept := maxi(first, second) if advantage > 0 else mini(first, second)
	return [kept, [first, second]]


## Sum of n dice with the given number of sides, one randint(1, sides) draw per die.
static func roll(rng: PyRandom, n: int, sides: int) -> int:
	var total := 0
	for _i in range(n):
		total += rng.randint(1, sides)
	return total


## '2d6+3' style text.
static func fmt(n: int, sides: int, bonus: int = 0) -> String:
	if bonus != 0:
		return "%dd%d%s" % [n, sides, PyFmt.signed_int(bonus)]
	return "%dd%d" % [n, sides]


static func average(n: int, sides: int, bonus: int = 0) -> float:
	return float(n * (sides + 1)) / 2.0 + bonus


## Exact distribution of the sum of n dice: {total: probability}. Insertion order matters (float
## sums iterate it), so the loops are identical to Python's.
static func dice_distribution(n: int, sides: int) -> Dictionary:
	var key := Vector2i(n, sides)
	if _dist_cache.has(key):
		return _dist_cache[key]
	var dist := {0: 1.0}
	for _i in range(n):
		var nxt := {}
		for total in dist:
			var p: float = dist[total]
			for face in range(1, sides + 1):
				nxt[total + face] = nxt.get(total + face, 0.0) + p / sides
		dist = nxt
	_dist_cache[key] = dist
	return dist


## Exact chance that d20 + attack_bonus meets target (natural 1 misses, crits always hit).
## Returns [p_hit, p_crit], where p_crit is included in p_hit.
static func chance_to_hit(attack_bonus: int, target: int, crit_range: int = 1, advantage: int = 0) -> Array:
	var hits: Array[bool] = []
	var crits: Array[bool] = []
	var hit_count := 0
	var crit_count := 0
	for r in range(1, 21):
		var h: bool = r == 20 or r > 20 - crit_range or (r != 1 and r + attack_bonus >= target)
		var c: bool = r > 20 - crit_range
		hits.append(h)
		crits.append(c)
		hit_count += int(h)
		crit_count += int(c)
	var p_hit_1 := float(hit_count) / 20.0
	var p_crit_1 := float(crit_count) / 20.0
	if advantage == 0:
		return [p_hit_1, p_crit_1]
	# Two dice: a face is kept with probability that depends on the other die.
	var p_hit := 0.0
	var p_crit := 0.0
	for a in range(1, 21):
		for b in range(1, 21):
			var kept := maxi(a, b) if advantage > 0 else mini(a, b)
			p_hit += float(int(hits[kept - 1])) / 400.0
			p_crit += float(int(crits[kept - 1])) / 400.0
	return [p_hit, p_crit]


## The lowest d20 face that hits (between 2 and 20).
static func needed_roll(attack_bonus: int, target: int) -> int:
	return mini(20, maxi(2, target - attack_bonus))

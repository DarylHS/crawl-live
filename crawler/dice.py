"""Dice: d20 rolls, damage dice and their exact odds.

Rolls use the World's seeded RNG so a run replays exactly. The exact helpers
(chance_to_hit, dice_distribution) let the Analyst, the fun facts and
the tests show true probabilities rather than simulated ones.
"""
from functools import lru_cache


def d20(rng, advantage=0):
    """Roll a d20. advantage > 0 keeps the higher of two, < 0 the lower.
    Returns (kept, all_rolls)."""
    if advantage == 0:
        r = rng.randint(1, 20)
        return r, (r,)
    rolls = (rng.randint(1, 20), rng.randint(1, 20))
    return (max(rolls) if advantage > 0 else min(rolls)), rolls


def roll(rng, n, sides):
    return sum(rng.randint(1, sides) for _ in range(n))


def fmt(n, sides, bonus=0):
    """'2d6+3' style text."""
    if bonus:
        return f"{n}d{sides}{bonus:+d}"
    return f"{n}d{sides}"


def average(n, sides, bonus=0):
    return n * (sides + 1) / 2 + bonus


@lru_cache(maxsize=None)
def dice_distribution(n, sides):
    """Exact distribution of the sum of n dice: {total: probability}."""
    dist = {0: 1.0}
    for _ in range(n):
        nxt = {}
        for total, p in dist.items():
            for face in range(1, sides + 1):
                nxt[total + face] = nxt.get(total + face, 0.0) + p / sides
        dist = nxt
    return dist


def chance_to_hit(attack_bonus, target, crit_range=1, advantage=0):
    """Exact chance that d20 + attack_bonus meets target (natural 1 misses, crits always hit).
    Returns (p_hit, p_crit), where p_crit is included in p_hit."""
    faces = range(1, 21)
    hits = [r == 20 or r > 20 - crit_range or (r != 1 and r + attack_bonus >= target) for r in faces]
    crits = [r > 20 - crit_range for r in faces]
    p_hit_1 = sum(hits) / 20
    p_crit_1 = sum(crits) / 20
    if advantage == 0:
        return p_hit_1, p_crit_1
    # Two dice: a face is kept with probability that depends on the other die.
    p_hit = p_crit = 0.0
    for a in faces:
        for b in faces:
            kept = max(a, b) if advantage > 0 else min(a, b)
            p_hit += hits[kept - 1] / 400
            p_crit += crits[kept - 1] / 400
    return p_hit, p_crit


def needed_roll(attack_bonus, target):
    """The lowest d20 face that hits (between 2 and 20)."""
    return min(20, max(2, target - attack_bonus))

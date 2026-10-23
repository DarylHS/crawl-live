"""Attack resolution.

hit_chance and expected_damage are exact (not simulated) so the Analyst class
can show true odds later, and tests can check the dice against them.
"""
from dataclasses import dataclass

from . import config as C


@dataclass
class AttackResult:
    hit: bool
    crit: bool
    damage: int
    killed: bool


def hit_chance(attacker, defender):
    p = C.BASE_HIT + C.HIT_PER_POINT * (attacker.accuracy - defender.evasion)
    return min(C.HIT_MAX, max(C.HIT_MIN, p))


def base_roll_range(attacker):
    return max(1, attacker.power - C.DAMAGE_SPREAD), attacker.power + C.DAMAGE_SPREAD


def _damage(base, crit, defender):
    return max(1, base * (2 if crit else 1) - defender.defence)


def expected_damage(attacker, defender):
    """Expected damage per swing, including misses and crits."""
    lo, hi = base_roll_range(attacker)
    n = hi - lo + 1
    normal = sum(_damage(b, False, defender) for b in range(lo, hi + 1)) / n
    crit = sum(_damage(b, True, defender) for b in range(lo, hi + 1)) / n
    return hit_chance(attacker, defender) * ((1 - C.CRIT_CHANCE) * normal + C.CRIT_CHANCE * crit)


def attack(attacker, defender, rng, mult=1, sure=False):
    """Resolve one swing. mult scales the base roll; sure skips the hit roll."""
    if not sure and rng.random() >= hit_chance(attacker, defender):
        return AttackResult(False, False, 0, False)
    crit = rng.random() < C.CRIT_CHANCE
    base = rng.randint(*base_roll_range(attacker)) * mult
    dmg = defender.take_damage(_damage(base, crit, defender))
    return AttackResult(True, crit, dmg, not defender.alive)

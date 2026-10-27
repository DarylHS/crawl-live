"""Attack resolution with visible dice.

An attack is d20 + attack bonus against the target's Armour Class (AC). A natural 1
always misses; a natural 20 always hits and is a critical (the crit range can widen,
e.g. the Hobgoblin crits on 17-20). A hit rolls the attacker's damage dice (twice as
many dice on a crit), adds their damage bonus, then subtracts the target's damage
reduction (DR), minimum 1.

hit_chance and expected_damage are exact, so the Analyst's Scout Report and the
sponsor deal previews show true odds.
"""
from dataclasses import dataclass

from .dice import chance_to_hit, d20, dice_distribution, roll


@dataclass
class AttackResult:
    hit: bool
    crit: bool
    damage: int
    killed: bool
    roll: int = 0               # the d20 face kept
    total: int = 0              # roll + attack bonus
    target: int = 0             # the AC it was rolled against

    @property
    def natural(self):
        return "20" if self.roll == 20 else "1" if self.roll == 1 else None

    def dice_text(self):
        """'d20 14+3=17 vs AC 12' for the message log."""
        bonus = self.total - self.roll
        return f"d20 {self.roll}{bonus:+d}={self.total} vs AC {self.target}"


def hit_chance(attacker, defender, advantage=0):
    return chance_to_hit(attacker.attack, defender.ac, attacker.crit_range, advantage)[0]


def crit_chance(attacker, advantage=0):
    return chance_to_hit(0, 99, attacker.crit_range, advantage)[1]


def _damage(base, defender):
    return max(1, base - defender.dr)


def expected_damage(attacker, defender, mult=1, bonus=0):
    """Expected damage per swing, including misses and crits."""
    p_hit, p_crit = chance_to_hit(attacker.attack, defender.ac, attacker.crit_range)
    n, die = attacker.dmg_n, attacker.dmg_die

    def mean(dice_n):
        return sum(p * _damage(round((t + attacker.dmg_bonus) * mult) + bonus, defender)
                   for t, p in dice_distribution(dice_n, die).items())

    return (p_hit - p_crit) * mean(n) + p_crit * mean(2 * n)


def attack(attacker, defender, rng, mult=1, sure=False, bonus=0, crit_bonus=0, advantage=0):
    """Resolve one swing. mult scales the dice and damage bonus, bonus adds flat damage
    afterwards, crit_bonus widens the crit range, sure means it can't miss."""
    face, _ = d20(rng, advantage)
    total = face + attacker.attack
    crit = face > 20 - (attacker.crit_range + crit_bonus)
    hit = sure or crit or (face != 1 and total >= defender.ac)
    if not hit:
        return AttackResult(False, False, 0, False, face, total, defender.ac)
    dice_n = attacker.dmg_n * (2 if crit else 1)
    base = round((roll(rng, dice_n, attacker.dmg_die) + attacker.dmg_bonus) * mult) + bonus
    dmg = defender.take_damage(_damage(base, defender))
    return AttackResult(True, crit, dmg, not defender.alive, face, total, defender.ac)


def saving_throw(rng, bonus, dc):
    """d20 + bonus against a DC. Returns (saved, face)."""
    face, _ = d20(rng)
    return face != 1 and (face == 20 or face + bonus >= dc), face

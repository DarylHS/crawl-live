"""The five crawler attributes and the numbers derived from them.

Scores sit around 10; the modifier is (score - 10) // 2, as in tabletop RPGs, so a
14 gives +2 and an 8 gives -1. Crawlers get POINTS_PER_LEVEL points to spend at
each level-up (and START_POINTS at the start). Race, class and backstory nudge
scores through an `attrs` dict in their data.
"""
ATTRS = {
    "str": dict(name="Strength", short="STR",
                does="Melee hits and damage with fists and blunt weapons"),
    "dex": dict(name="Dexterity", short="DEX",
                does="Armour Class, blades (finesse), bomb save DC"),
    "con": dict(name="Constitution", short="CON",
                does="Max HP each level, faster natural healing"),
    "int": dict(name="Intelligence", short="INT",
                does="Class skill power and recharge; perception, insight, first aid"),
    "cha": dict(name="Charisma", short="CHA",
                does="Viewers gained, shop prices; willpower against fear and charm"),
}

BASE_SCORE = 10
START_POINTS = 6
POINTS_PER_LEVEL = 2
MAX_SCORE = 30


def mod(score):
    return (score - 10) // 2


def proficiency(level):
    """Training bonus to hit, to weapon damage and to save DCs: +2 at level 1, +1 every 4 levels."""
    return 2 + (level - 1) // 4


def fmt_mod(m):
    return f"{m:+d}"

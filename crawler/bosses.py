"""Floor bosses.

Each floor has a boss waiting in the furthest stairwell room. On floors 1-5
it's optional: a big fight for XP, viewers and a loot box. On the final floor
the exit stays sealed until the boss dies, and it has a second phase at half HP.
"""
from .entities import Monster, stat_block

BOSSES = {
    1: dict(name="The Grease Trap King", glyph="K", colour=(230, 200, 90), hp=24, ac=11, attack=4,
            dmg=(1, 6, 0), save=2, xp=25, box="silver"),
    2: dict(name="The Overdue Librarian", glyph="L", colour=(220, 170, 120), hp=42, ac=12, attack=5,
            dmg=(1, 6, 2), save=3, xp=40, box="silver"),
    3: dict(name="Foreman Gristle", glyph="F", colour=(235, 140, 70), hp=84, ac=13, attack=6,
            dmg=(2, 6, 0), save=3, xp=60, box="gold"),
    4: dict(name="High Hexer Volka", glyph="H", colour=(225, 110, 235), hp=77, ac=14, attack=7,
            dmg=(2, 4, 2), save=5, xp=75, box="gold", ranged=5),
    5: dict(name="The Shrink-Wrapped Colossus", glyph="W", colour=(180, 210, 240), hp=126, ac=15,
            attack=7, dmg=(2, 6, 1), save=4, xp=100, box="platinum"),
    6: dict(name="Executive Producer Glorm", glyph="P", colour=(255, 90, 90), hp=196, ac=15,
            attack=9, dmg=(2, 6, 1), save=6, xp=200, box="legendary", final=True),
}

# Final boss phase 2 (at half HP): hits harder, starts throwing things, calls in help.
PHASE_TWO = dict(damage_bonus=3, ranged=5, adds=("cultist", "cultist"))


def spawn_boss(depth, x, y):
    b = BOSSES[depth]
    return Monster(x, y, b["name"], b["glyph"], b["colour"], b["hp"], b["hp"], **stat_block(b),
                   key=f"boss_{depth}", xp_value=b["xp"], ranged=b.get("ranged", 0), boss=True,
                   save=b["save"])


def boss_depth(monster):
    return int(monster.key.split("_")[1])

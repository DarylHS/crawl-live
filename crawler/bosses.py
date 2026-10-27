"""Bosses in three tiers, named like a show's running order.

- Opening Acts: several per floor, elite versions of the floor's monsters. Each drops
  a map of the surrounding area.
- Featured Acts: one or two per floor, tougher elites that drop a better haul.
- Headliner: one per floor, the named boss beside the furthest stairwell. It drops a
  stairwell key (the stairs open early) and a top-shelf item. On the final floor the
  exit stays sealed until the Headliner falls, and it has a second phase at half HP.
"""
from .entities import MONSTERS, Monster, stat_block

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
    """The floor's Headliner."""
    b = BOSSES[depth]
    return Monster(x, y, b["name"], b["glyph"], b["colour"], b["hp"], b["hp"], **stat_block(b),
                   key=f"boss_{depth}", xp_value=b["xp"], ranged=b.get("ranged", 0), boss=True,
                   save=b["save"], tier="headliner", base=f"boss_{depth}")


# How an Act improves on its base monster.
ACTS = {
    "opening":  dict(title="Opening Act", hp=2.0, attack=1, ac=1, dmg=1, save=2, xp=3, gold=2),
    "featured": dict(title="Featured Act", hp=3.0, attack=2, ac=1, dmg=2, save=3, xp=5, gold=3),
}
ACT_NAMES = {   # (Opening Act, Featured Act)
    "gnawer":   ("Gnawer Matriarch", "The Rat Queen of Aisle Nine"),
    "goblin":   ("Goblin Shift Supervisor", "The Goblin Regional Manager"),
    "vacbot":   ("Vacuum Bot Prime", "The Self-Emptying Overlord"),
    "skeleton": ("Skeleton Middle Manager", "The Bone Auditor"),
    "brute":    ("Brute Bouncer", "The Tunnel Brute Champion"),
    "cultist":  ("Cultist Influencer", "The Hex Cult Spokesperson"),
    "golem":    ("Golem Understudy", "The Stitched Superstar"),
    "stalker":  ("Stalker Stand-in", "The Shadow Producer"),
}
MAP_RADIUS = 22                 # an Opening Act's map reveals this far around where it fell


def acts_per_floor(depth):
    """(Opening Acts, Featured Acts) on a floor."""
    return 2 + depth // 2, depth // 2


def spawn_act(tier, base, x, y):
    m, a = MONSTERS[base], ACTS[tier]
    name = ACT_NAMES[base][0 if tier == "opening" else 1]
    n, die, bonus = m["dmg"]
    hp = round(m["hp"] * a["hp"])
    return Monster(x, y, name, m["glyph"].upper(), m["colour"], hp, hp,
                   attack=m["attack"] + a["attack"], ac=m["ac"] + a["ac"], dmg_n=n, dmg_die=die, dmg_bonus=bonus + a["dmg"],
                   key=f"{tier}_{base}", xp_value=m["xp"] * a["xp"], ranged=m.get("ranged", 0),
                   boss=True, save=m["save"] + a["save"], tier=tier, base=base)


def boss_depth(monster):
    """Floor number of a Headliner (its key is boss_<depth>)."""
    return int(monster.key.split("_")[1])

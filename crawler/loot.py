"""Loot boxes: five tiers, each a weighted roll table of four items.

Tables are data. Odds are exact (weight / total), which Phase 4 shows to the player.
"""
from . import config as C

TIERS = ["bronze", "silver", "gold", "platinum", "legendary"]

BOX_TIERS = {
    "bronze":    dict(name="Bronze", colour=(205, 140, 80),
                      table=[("sock", 4), ("tonic", 4), ("popper", 3), ("jersey", 3)]),
    "silver":    dict(name="Silver", colour=(200, 205, 215),
                      table=[("trophy", 2), ("pan", 3), ("brew", 4), ("vest", 3)]),
    "gold":      dict(name="Gold", colour=C.ACCENT,
                      table=[("cleaver", 3), ("vest", 3), ("brew", 3), ("fireworks", 2)]),
    "platinum":  dict(name="Platinum", colour=(150, 225, 235),
                      table=[("cleaver", 2), ("plate", 3), ("elixir", 3), ("fireworks", 2)]),
    "legendary": dict(name="Legendary", colour=(235, 110, 255),
                      table=[("katana", 3), ("plate", 3), ("elixir", 3), ("fireworks", 1)]),
}


def odds(tier):
    """[(item_key, probability)] for a tier."""
    table = BOX_TIERS[tier]["table"]
    total = sum(w for _, w in table)
    return [(k, w / total) for k, w in table]


def roll_box(tier, rng):
    keys, weights = zip(*BOX_TIERS[tier]["table"])
    return rng.choices(keys, weights)[0]

"""Item data. Everything the player can carry is a dict in ITEMS.

kind: weapon | armour | potion | bomb | junk. value is the item's base price in gold:
the shop charges it (more when stock is scarce) and loot box EV is measured in it. Equipment gives flat stat bonuses
(power, accuracy, defence, evasion); potions heal; bombs hit every monster within
`radius` of the target for `damage`, ignoring defence. Junk does nothing yet.
"""
from . import config as C

ITEMS = {
    # weapons
    "pan":       dict(name="Dented Frying Pan", kind="weapon", value=10, power=2, colour=(190, 190, 200),
                      desc="Seen better breakfasts."),
    "cleaver":   dict(name="Pocket Cleaver", kind="weapon", value=22, power=3, accuracy=1,
                      colour=(200, 200, 215), desc="Small, rude and well balanced."),
    "katana":    dict(name="Overpriced Katana", kind="weapon", value=60, power=5, accuracy=2,
                      colour=(150, 220, 255), desc="Comes with a certificate of questionable origin."),
    # armour
    "jersey":    dict(name="Padded Gym Jersey", kind="armour", value=10, defence=1, colour=(140, 170, 220),
                      desc="Smells faintly of ambition."),
    "vest":      dict(name="Riot Vest", kind="armour", value=22, defence=2, colour=(120, 150, 200),
                      desc="Rated for crowds. Mostly."),
    "plate":     dict(name="Stagehand Plate", kind="armour", value=45, defence=4, evasion=-1,
                      colour=(170, 190, 230), desc="Heavy, shiny and very on-brand."),
    # potions
    "tonic":     dict(name="Fizzy Tonic", kind="potion", value=8, heal=10, colour=(240, 120, 150),
                      desc="Restores 10 HP. Tastes like pennies."),
    "brew":      dict(name="Sponsor Brew", kind="potion", value=15, heal=18, colour=(240, 90, 130),
                      desc="Restores 18 HP. Contains real fruit, allegedly."),
    "elixir":    dict(name="Producer's Elixir", kind="potion", value=30, heal=32, colour=(255, 70, 120),
                      desc="Restores 32 HP. Strictly off the record."),
    # bombs
    "popper":    dict(name="Party Popper Bomb", kind="bomb", value=10, damage=10, radius=1,
                      colour=(255, 170, 60), desc="10 damage to the target and its neighbours."),
    "fireworks": dict(name="Crate of Fireworks", kind="bomb", value=20, damage=18, radius=2,
                      colour=(255, 120, 40), desc="18 damage in a wide, loud burst."),
    # junk
    "sock":      dict(name="Soggy Sock", kind="junk", value=2, colour=(150, 140, 120), desc="Why is it warm?"),
    "trophy":    dict(name="Half a Trophy", kind="junk", value=4, colour=(210, 180, 80),
                      desc="Participation was close enough."),
    "remote":    dict(name="Mystery Remote", kind="junk", value=3, colour=(130, 130, 140),
                      desc="Controls nothing you own."),
    "mug":       dict(name="Sponsor Mug", kind="junk", value=2, colour=(200, 200, 160),
                      desc="'Drink responsibly. Or don't. Ratings.'"),
}

GLYPHS = {"weapon": ")", "armour": "[", "potion": "!", "bomb": "*", "junk": "~"}
EQUIP_SLOTS = {"weapon": "weapon", "armour": "armour"}
STAT_BONUSES = ("power", "accuracy", "defence", "evasion")

# Floor loot and monster drops: (key, weight, min floor).
FLOOR_LOOT = [
    ("sock", 4, 1), ("remote", 3, 1), ("mug", 3, 1), ("trophy", 2, 1),
    ("tonic", 6, 1), ("brew", 3, 2), ("elixir", 1, 4),
    ("popper", 3, 1), ("fireworks", 1, 3),
    ("pan", 2, 1), ("jersey", 2, 1), ("cleaver", 1, 2), ("vest", 1, 2),
]


def floor_loot_table(depth):
    rows = [(k, w) for k, w, lo in FLOOR_LOOT if lo <= depth]
    return [k for k, _ in rows], [w for _, w in rows]


def glyph(key):
    return GLYPHS[ITEMS[key]["kind"]]


def describe(key):
    """One-line stat summary for menus."""
    it = ITEMS[key]
    bits = [f"+{it[s]} {s}" if it[s] > 0 else f"{it[s]} {s}" for s in STAT_BONUSES if it.get(s)]
    if "heal" in it:
        bits.append(f"heals {it['heal']}")
    if "damage" in it:
        bits.append(f"{it['damage']} dmg r{it['radius']}")
    return ", ".join(bits) or it["desc"]


def value(key):
    return ITEMS[key]["value"]

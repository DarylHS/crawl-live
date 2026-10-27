"""Item data. Everything the player can carry is a dict in ITEMS.

kind: weapon | armour | potion | bomb | junk. value is the item's base price in gold:
the shop charges it (more when stock is scarce) and loot box EV is measured in it.
Weapons have damage dice (dice=(n, sides)), a style (blunt uses Strength; blade is
finesse, so it uses the better of Strength and Dexterity) and optional hit / dmg
bonuses. Armour adds to Armour Class (ac); heavy armour caps the Dexterity bonus
(max_dex). Potions heal; bombs roll their dice against every monster within
`radius` of the target, and each makes a Dexterity save for half. Junk does nothing yet.
"""
from .dice import average, fmt

FISTS = dict(name="Fists", style="unarmed", dice=(1, 4))

ITEMS = {
    # weapons
    "pan":       dict(name="Dented Frying Pan", kind="weapon", style="blunt", value=10, dice=(1, 6),
                      colour=(190, 190, 200), desc="Seen better breakfasts."),
    "cleaver":   dict(name="Pocket Cleaver", kind="weapon", style="blade", value=22, dice=(1, 8),
                      hit=1, colour=(200, 200, 215), desc="Small, rude and well balanced."),
    "katana":    dict(name="Overpriced Katana", kind="weapon", style="blade", value=60, dice=(1, 10),
                      hit=2, dmg=1, colour=(150, 220, 255),
                      desc="Comes with a certificate of questionable origin."),
    "extinguisher": dict(name="Fire Extinguisher", kind="weapon", style="blunt", value=26,
                         dice=(2, 6), colour=(220, 60, 50),
                         desc="Heavy, red and surprisingly well balanced. Puts out fires and faces."),
    "sledge":    dict(name="Demolition Sledge", kind="weapon", style="blunt", value=55, dice=(1, 12),
                      dmg=1, colour=(170, 150, 120), desc="For load-bearing walls and load-bearing "
                                                           "monsters."),
    # armour
    "jersey":    dict(name="Padded Gym Jersey", kind="armour", value=10, ac=1, colour=(140, 170, 220),
                      desc="Smells faintly of ambition."),
    "vest":      dict(name="Riot Vest", kind="armour", value=22, ac=2, max_dex=2, colour=(120, 150, 200),
                      desc="Rated for crowds. Mostly."),
    "plate":     dict(name="Stagehand Plate", kind="armour", value=45, ac=4, max_dex=0,
                      colour=(170, 190, 230), desc="Heavy, shiny and very on-brand. No room to dodge."),
    # potions
    "tonic":     dict(name="Fizzy Tonic", kind="potion", value=8, heal=10, colour=(240, 120, 150),
                      desc="Restores 10 HP. Tastes like pennies."),
    "brew":      dict(name="Sponsor Brew", kind="potion", value=15, heal=18, colour=(240, 90, 130),
                      desc="Restores 18 HP. Contains real fruit, allegedly."),
    "elixir":    dict(name="Producer's Elixir", kind="potion", value=30, heal=32, colour=(255, 70, 120),
                      desc="Restores 32 HP. Strictly off the record."),
    # bombs
    "popper":    dict(name="Party Popper Bomb", kind="bomb", value=10, dice=(3, 6), radius=1,
                      colour=(255, 170, 60), desc="3d6 to the target and its neighbours."),
    "fireworks": dict(name="Crate of Fireworks", kind="bomb", value=20, dice=(5, 6), radius=2,
                      colour=(255, 120, 40), desc="5d6 in a wide, loud burst."),
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

# Floor loot and monster drops: (key, weight, min floor).
FLOOR_LOOT = [
    ("sock", 4, 1), ("remote", 3, 1), ("mug", 3, 1), ("trophy", 2, 1),
    ("tonic", 6, 1), ("brew", 3, 2), ("elixir", 1, 4),
    ("popper", 3, 1), ("fireworks", 1, 3),
    ("pan", 2, 1), ("jersey", 2, 1), ("cleaver", 1, 2), ("vest", 1, 2),
    ("extinguisher", 1, 2), ("sledge", 1, 4),
]


def floor_loot_table(depth):
    rows = [(k, w) for k, w, lo in FLOOR_LOOT if lo <= depth]
    return [k for k, _ in rows], [w for _, w in rows]


def glyph(key):
    return GLYPHS[ITEMS[key]["kind"]]


def describe(key):
    """One-line stat summary for menus."""
    it = ITEMS[key]
    bits = []
    if it["kind"] == "weapon":
        bits.append(fmt(*it["dice"], it.get("dmg", 0)) + (" finesse" if it["style"] == "blade" else ""))
        if it.get("hit"):
            bits.append(f"{it['hit']:+d} to hit")
    if it.get("ac"):
        cap = it.get("max_dex")
        bits.append(f"+{it['ac']} AC" + ("" if cap is None else ", no DEX bonus" if cap == 0
                                          else f", DEX bonus max +{cap}"))
    if "heal" in it:
        bits.append(f"heals {it['heal']}")
    if it["kind"] == "bomb":
        bits.append(f"{fmt(*it['dice'])} (avg {average(*it['dice']):.0f}) r{it['radius']}")
    return ", ".join(bits) or it["desc"]


def value(key):
    return ITEMS[key]["value"]

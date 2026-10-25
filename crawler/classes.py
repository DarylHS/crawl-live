"""Races and classes, chosen on reaching floor 3.

Race gives a flat stat bonus; class gives a bonus plus one active skill on key 1.
"""
CHOICE_FLOOR = 3

RACES = {
    "human": dict(name="Human", desc="+8 max HP. Stubborn, adaptable, mostly harmless.",
                  max_hp=8),
    "elf":   dict(name="Elf", desc="+2 evasion, +1 accuracy. Graceful and insufferable about it.",
                  evasion=2, accuracy=1),
}

CLASSES = {
    "brawler":  dict(name="Brawler", desc="+2 attack, +1 defence. Solves problems with fists.",
                     power=2, defence=1, skill="haymaker"),
    "arcanist": dict(name="Arcanist", desc="+1 accuracy. Throws lightning at problems.",
                     accuracy=1, skill="arc_bolt"),
    "analyst":  dict(name="Analyst", desc="+1 attack, accuracy and evasion. Knows the odds and "
                                          "uses them.",
                     power=1, accuracy=1, evasion=1, skill="scout_report"),
}

SKILLS = {
    "haymaker":     dict(name="Haymaker", cooldown=10,
                         desc="A guaranteed hit on an adjacent monster for double damage."),
    "arc_bolt":     dict(name="Arc Bolt", cooldown=8, range=6,
                         desc="Zap the nearest visible monster within 6 tiles for 8 + 2 x level, "
                              "ignoring defence."),
    "scout_report": dict(name="Scout Report", cooldown=25, duration=20,
                         desc="For 20 turns, see exact hit chances and expected damage for "
                              "every visible monster, both ways."),
}

BONUS_STATS = ("max_hp", "power", "defence", "accuracy", "evasion")


def apply_choice(player, race, cls):
    for source in (RACES[race], CLASSES[cls]):
        for stat in BONUS_STATS:
            setattr(player, stat, getattr(player, stat) + source.get(stat, 0))
    player.hp += RACES[race].get("max_hp", 0)

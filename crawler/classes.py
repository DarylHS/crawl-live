"""Races and classes, chosen on reaching floor 3.

Race gives stat changes and sometimes a perk; class gives a small bonus plus one
active skill on key 1. Perks are flags the rules check with World.trait().
"""
CHOICE_FLOOR = 3

RACES = {
    "human":      dict(name="Human", desc="+10 max HP. The safe pick.", max_hp=10),
    "elf":        dict(name="Elf", desc="+2 evasion, +1 accuracy, -4 max HP. Graceful, fragile, "
                                        "insufferable about it.",
                       evasion=2, accuracy=1, max_hp=-4),
    "dwarf":      dict(name="Dwarf", desc="+1 defence, +4 max HP, -1 evasion. Built like a filing "
                                          "cabinet.",
                       defence=1, max_hp=4, evasion=-1),
    "hobgoblin":  dict(name="Hobgoblin", desc="Crits on 20% of hits instead of 5%. -1 defence. "
                                              "Fights dirty, bruises easily.",
                       defence=-1, crit_chance=0.20),
    "bog_troll":  dict(name="Bog Troll", desc="Regenerates twice as fast. -2 accuracy. The System "
                                              "stops calling you by name.",
                       accuracy=-2, regen_mult=2, address="creature"),
    "houseplant": dict(name="Sentient Houseplant", desc="Bark: +2 defence, +4 max HP. Heals while "
                                                        "standing still; safe rooms heal you "
                                                        "fully on arrival. Can't wear armour.",
                       defence=2, max_hp=4, photosynthesis=True, no_armour=True),
}

CLASSES = {
    "brawler":       dict(name="Brawler", desc="+2 attack. Solves problems with fists.",
                          power=2, skill="haymaker", pairs=("tradie",)),
    "arcanist":      dict(name="Arcanist", desc="+1 accuracy. Throws lightning at problems.",
                          accuracy=1, skill="arc_bolt"),
    "analyst":       dict(name="Analyst", desc="+1 attack, accuracy and evasion. Knows the odds and "
                                               "uses them.",
                          power=1, accuracy=1, evasion=1, skill="scout_report"),
    "alchemist":     dict(name="Alchemist", desc="+4 max HP; potions heal 50% more. Turns rubbish "
                                                 "into medicine.",
                          max_hp=4, class_potion_mult=1.5, skill="field_brew",
                          pairs=("mixologist", "parent")),
    "beastmaster":   dict(name="Beastmaster", desc="+1 defence. Your companion fights like it means "
                                                   "it.",
                          defence=1, skill="rile_up", pairs=("dog_walker",)),
    "hype_man":      dict(name="Hype Man", desc="+1 evasion. Works the crowd while working the "
                                                "room.",
                          evasion=1, skill="crowd_work", pairs=("comedian",)),
    "demolitionist": dict(name="Demolitionist", desc="+1 attack; bombs do 50% more damage. Loud.",
                          power=1, bomb_mult=1.5, skill="pocket_popper", pairs=("veteran",)),
    "quartermaster": dict(name="Quartermaster", desc="+1 defence. Knows a guy who knows a guy.",
                          defence=1, skill="supply_drop", pairs=("category_mgr", "rideshare")),
    "duellist":      dict(name="Duellist", desc="+1 accuracy, +1 evasion. Insists on the proper "
                                                "forms.",
                          accuracy=1, evasion=1, skill="riposte"),
}

SKILLS = {
    "haymaker":      dict(name="Haymaker", cooldown=10,
                          desc="A guaranteed hit on an adjacent monster for double damage."),
    "arc_bolt":      dict(name="Arc Bolt", cooldown=10, range=6,
                          desc="Zap the nearest visible monster within 6 tiles for 8 + 2 x level, "
                               "ignoring defence."),
    "scout_report":  dict(name="Scout Report", cooldown=25, duration=20,
                          desc="For 20 turns, see exact hit chances and expected damage for every "
                               "visible monster, both ways."),
    "field_brew":    dict(name="Field Brew", cooldown=12,
                          desc="Turn one piece of junk from your pack into a random potion, "
                               "anywhere."),
    "rile_up":       dict(name="Rile Up", cooldown=20, duration=5,
                          desc="Your companion does double damage for 5 turns."),
    "crowd_work":    dict(name="Crowd Work", cooldown=25, duration=10,
                          desc="For 10 turns kills earn triple viewers and your companion hits "
                               "50% harder."),
    "pocket_popper": dict(name="Pocket Popper", cooldown=15, range=6,
                          desc="Throw a free Party Popper Bomb at the nearest visible monster."),
    "supply_drop":   dict(name="Supply Drop", cooldown=999,
                          desc="Open the shop wherever you are for one purchase. Once per floor."),
    "riposte":       dict(name="Riposte", cooldown=18, charges=2,
                          desc="Parry the next 2 attacks against you and strike back each time."),
}

BONUS_STATS = ("max_hp", "power", "defence", "accuracy", "evasion")


def apply_stats(player, *sources):
    for source in sources:
        for stat in BONUS_STATS:
            setattr(player, stat, getattr(player, stat) + source.get(stat, 0))
        player.hp = max(1, player.hp + source.get("max_hp", 0))
        if "crit_chance" in source:
            player.crit_chance = source["crit_chance"]


def apply_choice(player, race, cls):
    apply_stats(player, RACES[race], CLASSES[cls])

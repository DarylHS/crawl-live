"""Races and classes, chosen on reaching floor 3.

Race nudges attributes and sometimes gives a perk; class gives an attribute bonus plus
one active skill on key 1. Attribute nudges (attrs) and flat bonuses (FLAT_BONUSES)
stack across backstory, race and class; perks are flags read with World.trait().
"""
CHOICE_FLOOR = 3

RACES = {
    "human":      dict(name="Human", desc="+1 to every attribute, +5 max HP. Adaptable, unremarkable, "
                                          "proud of both.",
                       attrs=dict(str=1, dex=1, con=1, int=1, cha=1), max_hp=5),
    "elf":        dict(name="Elf", desc="+2 DEX, +1 INT, -2 CON. Graceful, fragile, insufferable "
                                        "about it.",
                       attrs=dict(dex=2, int=1, con=-2)),
    "dwarf":      dict(name="Dwarf", desc="+2 CON, +2 STR, -2 DEX. Built like a filing cabinet.",
                       attrs=dict(con=2, str=2, dex=-2)),
    "hobgoblin":  dict(name="Hobgoblin", desc="+2 DEX; crits on 17-20 instead of just 20. -1 AC. "
                                              "Fights dirty, bruises easily.",
                       attrs=dict(dex=2), crit_range=3, ac=-1),
    "bog_troll":  dict(name="Bog Troll", desc="+2 STR, +2 CON, -2 INT, -2 CHA. Regenerates twice "
                                              "as fast. The System stops calling you by name.",
                       attrs=dict(str=2, con=2, int=-2, cha=-2), regen_mult=2, address="creature"),
    "houseplant": dict(name="Sentient Houseplant", desc="+2 CON, -2 DEX. Bark: every hit on you "
                                                        "does 1 less damage. Heals while standing "
                                                        "still; safe rooms heal you fully on "
                                                        "arrival. Can't wear armour.",
                       attrs=dict(con=2, dex=-2), dr=1, photosynthesis=True, no_armour=True),
}

CLASSES = {
    "brawler":       dict(name="Brawler", desc="+2 STR; fists hit for 1d8. Solves problems with "
                                               "fists.",
                          attrs=dict(str=2), martial_arts=True, skill="haymaker",
                          pairs=("tradie",)),
    "arcanist":      dict(name="Arcanist", desc="+2 INT. Throws lightning at problems.",
                          attrs=dict(int=2), skill="arc_bolt"),
    "analyst":       dict(name="Analyst", desc="+1 STR, +1 DEX, +1 INT, +1 to hit. Knows the odds "
                                               "and uses them.",
                          attrs=dict(str=1, dex=1, int=1), hit=1, skill="scout_report"),
    "alchemist":     dict(name="Alchemist", desc="+2 INT, +4 max HP; potions heal 50% more. Turns "
                                                 "rubbish into medicine.",
                          attrs=dict(int=2), max_hp=4, class_potion_mult=1.5, skill="field_brew",
                          pairs=("mixologist", "parent")),
    "beastmaster":   dict(name="Beastmaster", desc="+2 CHA, +1 AC. Your companion fights like it "
                                                   "means it.",
                          attrs=dict(cha=2), ac=1, skill="rile_up", pairs=("dog_walker",)),
    "hype_man":      dict(name="Hype Man", desc="+2 CHA. Works the crowd while working the room.",
                          attrs=dict(cha=2), skill="crowd_work", pairs=("comedian",)),
    "demolitionist": dict(name="Demolitionist", desc="+2 DEX; bombs do 50% more damage. Loud.",
                          attrs=dict(dex=2), bomb_mult=1.5, skill="pocket_popper",
                          pairs=("veteran",)),
    "quartermaster": dict(name="Quartermaster", desc="+2 CHA, +1 AC. Knows a guy who knows a guy.",
                          attrs=dict(cha=2), ac=1, skill="supply_drop",
                          pairs=("category_mgr", "rideshare")),
    "duellist":      dict(name="Duellist", desc="+2 DEX, +1 to hit. Insists on the proper forms.",
                          attrs=dict(dex=2), hit=1, skill="riposte"),
}

SKILLS = {
    "haymaker":      dict(name="Haymaker", cooldown=10,
                          desc="A guaranteed hit on an adjacent monster for double damage."),
    "arc_bolt":      dict(name="Arc Bolt", cooldown=10, range=6,
                          desc="Zap the nearest visible monster within 6 tiles for 6 + 2 x level "
                               "+ INT modifier. No roll to hit: lightning finds a way."),
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

# Flat bonuses a race, class or backstory can carry (summed across all three).
FLAT_BONUSES = ("max_hp", "ac", "hit", "dr")

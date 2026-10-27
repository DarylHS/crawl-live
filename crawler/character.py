"""Character creation: name, gender and backstory, chosen before the run starts.

Gender is cosmetic (it changes how the System addresses you). A backstory nudges
one attribute and gives a perk from the crawler's life before the dungeon; perks are
flags the rules check through World.trait().
"""
GENDERS = {
    "female":    dict(name="Woman", address="madam"),
    "male":      dict(name="Man", address="sir"),
    "nonbinary": dict(name="Non-binary", address="friend"),
}

BACKSTORIES = {
    "veteran":      dict(name="Military Veteran", perk="+2 DEX, +1 to hit",
                         desc="Has done worse, in worse places, for less.",
                         attrs=dict(dex=2), hit=1),
    "mixologist":   dict(name="Mixologist", perk="+2 CHA; potions heal 40% more",
                         desc="Shaken, not stirred, still bleeding.",
                         attrs=dict(cha=2), potion_mult=1.4),
    "dog_walker":   dict(name="Dog Walker", perk="+2 CON; companion starts at level 3 with +4 HP",
                         desc="Handled eight leads at once. One companion is a holiday.",
                         attrs=dict(con=2), pet_head_start=True),
    "comedian":     dict(name="Stand-up Comedian", perk="+2 CHA; +50% viewers from kills",
                         desc="Tough crowd. Literally.",
                         attrs=dict(cha=2), kill_viewer_mult=1.5),
    "parent":       dict(name="Stay-at-home Parent", perk="+2 CON, +4 max HP; rest 25% faster",
                         desc="Has survived worse on four hours' sleep.",
                         attrs=dict(con=2), max_hp=4, rest_mult=1.25),
    "tradie":       dict(name="Tradie", perk="+2 STR; crafting takes half the time",
                         desc="Brought their own tools. Quoted the dungeon for repairs.",
                         attrs=dict(str=2), craft_mult=0.5),
    "category_mgr": dict(name="Category Manager", perk="+2 INT; shop prices 15% lower, sell for more",
                         desc="Has negotiated with scarier suppliers than this.",
                         attrs=dict(int=2), buy_mult=0.85, sell_mult=1.4),
    "rideshare":    dict(name="Rideshare Driver", perk="+2 CHA; +60 minutes on every floor's timer",
                         desc="Always knows a shortcut. Five stars, would be crushed again.",
                         attrs=dict(cha=2), timer_bonus=60),
}

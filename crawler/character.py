"""Character creation: name, gender and backstory, chosen before the run starts.

Gender is cosmetic (it changes how the System addresses you). A backstory is a
small stat nudge or perk from the crawler's life before the dungeon; perks are
flags the rules check through World.trait().
"""
GENDERS = {
    "female":    dict(name="Woman", address="madam"),
    "male":      dict(name="Man", address="sir"),
    "nonbinary": dict(name="Non-binary", address="friend"),
}

BACKSTORIES = {
    "veteran":      dict(name="Military Veteran", perk="+1 defence, +1 accuracy",
                         desc="Has done worse, in worse places, for less.",
                         defence=1, accuracy=1),
    "mixologist":   dict(name="Mixologist", perk="Potions heal 25% more",
                         desc="Shaken, not stirred, still bleeding.",
                         potion_mult=1.25),
    "dog_walker":   dict(name="Dog Walker", perk="Companion starts at level 2 with +4 HP",
                         desc="Handled eight leads at once. One companion is a holiday.",
                         pet_head_start=True),
    "comedian":     dict(name="Stand-up Comedian", perk="+50% viewers from kills",
                         desc="Tough crowd. Literally.",
                         kill_viewer_mult=1.5),
    "parent":       dict(name="Stay-at-home Parent", perk="+8 max HP, rest 25% faster",
                         desc="Has survived worse on four hours' sleep.",
                         max_hp=8, rest_mult=1.25),
    "tradie":       dict(name="Tradie", perk="+2 attack, crafting takes half the time",
                         desc="Brought their own tools. Quoted the dungeon for repairs.",
                         power=2, craft_mult=0.5),
    "category_mgr": dict(name="Category Manager", perk="Shop prices 15% lower, sell for more",
                         desc="Has negotiated with scarier suppliers than this.",
                         buy_mult=0.85, sell_mult=1.4),
    "rideshare":    dict(name="Rideshare Driver", perk="+60 minutes on every floor's timer",
                         desc="Always knows a shortcut. Five stars, would be crushed again.",
                         timer_bonus=60),
}

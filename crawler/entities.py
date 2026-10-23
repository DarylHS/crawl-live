"""Player, monsters and the monster table.

Monsters are plain data in MONSTERS so new ones can be added without code.
"""
from dataclasses import dataclass

from . import config as C


@dataclass(eq=False)
class Entity:
    x: int
    y: int
    name: str
    glyph: str
    colour: tuple
    max_hp: int
    hp: int
    power: int
    defence: int
    accuracy: int = 0
    evasion: int = 0

    @property
    def alive(self):
        return self.hp > 0

    def take_damage(self, amount):
        dealt = min(self.hp, amount)
        self.hp -= dealt
        return dealt

    def heal(self, amount):
        healed = min(self.max_hp - self.hp, amount)
        self.hp += healed
        return healed


@dataclass(eq=False)
class Player(Entity):
    level: int = 1
    xp: int = 0
    kills: int = 0

    def xp_to_next(self):
        return 20 + 15 * (self.level - 1)

    def gain_xp(self, amount):
        """Add XP and apply any level-ups; returns the list of new levels."""
        self.xp += amount
        gained = []
        while self.xp >= self.xp_to_next():
            self.xp -= self.xp_to_next()
            self.level += 1
            self.max_hp += 6
            self.hp = min(self.max_hp, self.hp + 6)
            self.power += 1
            if self.level % 2 == 0:
                self.defence += 1
            if self.level % 3 == 0:
                self.accuracy += 1
            gained.append(self.level)
        return gained


@dataclass(eq=False)
class Monster(Entity):
    key: str = ""
    xp_value: int = 0
    alerted: bool = False
    unseen_turns: int = 0
    ranged: int = 0                 # attack range in tiles; 0 = melee only
    boss: bool = False
    phase: int = 1                  # bosses change behaviour as they lose HP
    stunned: int = 0                # turns left unable to act


@dataclass(eq=False)
class Pet(Entity):
    species: str = ""
    level: int = 1
    xp: int = 0
    kills: int = 0
    mode: str = "follow"            # "follow" | "stay" | "attack"
    cooldown: int = 0               # turns until the ability is ready
    downed: bool = False

    def xp_to_next(self):
        return 15 + 10 * (self.level - 1)

    def gain_xp(self, amount):
        """Add XP and apply level-ups; returns the list of new levels."""
        self.xp += amount
        gained = []
        while self.xp >= self.xp_to_next():
            self.xp -= self.xp_to_next()
            self.level += 1
            self.max_hp += 4
            self.hp = min(self.max_hp, self.hp + 4)
            self.power += 1
            if self.level % 3 == 0:
                self.defence += 1
            gained.append(self.level)
        return gained


def new_player(x, y):
    s = C.PLAYER_START
    return Player(x, y, "Crawler", "@", C.PLAYER_COLOUR, s["max_hp"], s["max_hp"],
                  s["power"], s["defence"], s["accuracy"], s["evasion"])


# min/max floor bound where a monster appears; weight is its relative frequency.
MONSTERS = {
    "gnawer":   dict(name="Sewer Gnawer", glyph="r", colour=(170, 140, 110), hp=6, power=3,
                     defence=0, accuracy=0, evasion=1, xp=3, floors=(1, 2), weight=6),
    "goblin":   dict(name="Knockoff Goblin", glyph="g", colour=(120, 190, 80), hp=9, power=4,
                     defence=0, accuracy=0, evasion=0, xp=5, floors=(1, 3), weight=5),
    "vacbot":   dict(name="Feral Vacuum Bot", glyph="v", colour=(160, 170, 190), hp=12, power=5,
                     defence=2, accuracy=0, evasion=-1, xp=8, floors=(2, 4), weight=4),
    "skeleton": dict(name="Grumpy Skeleton", glyph="s", colour=(225, 220, 200), hp=14, power=6,
                     defence=1, accuracy=1, evasion=0, xp=10, floors=(2, 4), weight=4),
    "brute":    dict(name="Tunnel Brute", glyph="B", colour=(200, 120, 70), hp=24, power=8,
                     defence=2, accuracy=1, evasion=-1, xp=18, floors=(3, 5), weight=3),
    "cultist":  dict(name="Hex Cultist", glyph="c", colour=(190, 90, 210), hp=16, power=9,
                     defence=1, accuracy=2, evasion=1, xp=16, floors=(3, 6), weight=3, ranged=5),
    "golem":    dict(name="Flesh Golem", glyph="G", colour=(210, 130, 140), hp=40, power=11,
                     defence=4, accuracy=1, evasion=-2, xp=35, floors=(5, 6), weight=2),
    "stalker":  dict(name="Shadow Stalker", glyph="S", colour=(110, 110, 230), hp=26, power=12,
                     defence=2, accuracy=3, evasion=2, xp=30, floors=(5, 6), weight=2),
}


def monster_table(depth):
    """Keys and weights of monsters allowed on this floor."""
    keys = [k for k, m in MONSTERS.items() if m["floors"][0] <= depth <= m["floors"][1]]
    return keys, [MONSTERS[k]["weight"] for k in keys]


def spawn_monster(key, x, y):
    m = MONSTERS[key]
    return Monster(x, y, m["name"], m["glyph"], m["colour"], m["hp"], m["hp"], m["power"],
                   m["defence"], m["accuracy"], m["evasion"], key=key, xp_value=m["xp"],
                   ranged=m.get("ranged", 0))


# Companion species. ability is handled in ai.take_pet_turn.
PETS = {
    "cat": dict(name="Alley Cat", glyph="f", colour=(240, 180, 90), hp=16, power=4, defence=0,
                accuracy=1, evasion=2, default_name="Mittens",
                ability="pounce", ability_name="Pounce", cooldown=16,
                desc="Fast and vain. Pounce: leaps up to 3 tiles onto a monster for double damage."),
    "dog": dict(name="Scruffy Dog", glyph="d", colour=(200, 150, 110), hp=22, power=4, defence=1,
                accuracy=0, evasion=0, default_name="Biscuit",
                ability="lick", ability_name="Lick Wounds", cooldown=25,
                desc="Loyal and sturdy. Lick Wounds: heals you when you're under half HP."),
    "budgie": dict(name="Chatty Budgie", glyph="b", colour=(120, 220, 140), hp=10, power=3,
                   defence=0, accuracy=2, evasion=4, default_name="Pickles",
                   ability="squawk", ability_name="Ear-Splitting Squawk", cooldown=20,
                   desc="Fragile, hard to hit, never stops talking. Squawk: stuns nearby "
                        "monsters for 2 turns."),
    "mouse": dict(name="Scheming Mouse", glyph="m", colour=(190, 180, 200), hp=12, power=3,
                  defence=0, accuracy=1, evasion=3, default_name="Skritch",
                  ability="dirty_trick", ability_name="Dirty Trick", cooldown=10,
                  desc="Cunning and cowardly. Dirty Trick: triple damage on a wounded monster. "
                       "Runs away when hurt."),
}

# What each companion says, by event. The showrunner picks one at random.
PET_QUIPS = {
    "cat": {
        "kill": ["Beneath me, frankly.", "Note the form. Ten out of ten.",
                 "I'll be expecting a treat for that.", "Clean up that mess, would you?"],
        "ability": ["Watch and learn.", "Pounce perfected. As usual.", "Try to keep up."],
        "level_up": ["Finally, the recognition I deserve.", "Naturally."],
        "downed": ["This is your fault.", "I am... resting. Elegantly."],
    },
    "dog": {
        "kill": ["Got it! Got it! Did I do good?", "*proud tail wag*", "Is it a toy now?"],
        "ability": ["*gentle lick*", "*worried whine, then a lick*", "You'll be okay! Lick!"],
        "level_up": ["*tail goes to maximum speed*", "*zoomies*"],
        "downed": ["*whimper*", "*sad thump of tail*"],
    },
    "budgie": {
        "kill": ["PRETTY BIRD! PRETTY BIRD!", "*flawless impression of the monster dying*",
                 "Who's a clever boy? ME!", "*plays a victory jingle it heard on the telly*"],
        "ability": ["SQUAAAAWK!", "*does a perfect smoke alarm*", "*microwave beep, but louder*",
                    "*car alarm, full volume*"],
        "level_up": ["*learns a new ringtone*", "Pretty bird gets STRONGER!"],
        "downed": ["Polly... down...", "*sad kettle whistle*"],
    },
    "mouse": {
        "kill": ["Dead-dead! I did that. Me. Remember who did that, yes-yes?",
                 "Easy-easy prey. I planned it. Every step!",
                 "Its pockets are still warm. Mine now. Fair share!",
                 "Tell the cameras it was me, not you. For the ratings."],
        "ability": ["Stab-stab, from behind! Most cunning!",
                    "Weak one, so I strike! This is called strategy.",
                    "Hee-hee. Nobody watches the small ones."],
        "level_up": ["Stronger! Soon I lead, you follow. Joke-joke. Mostly.",
                     "Promotion! Long overdue. I'll be taking your share."],
        "downed": ["Betrayed! Betrayed by everyone!", "Not my fault-fault! Tactical nap!"],
        "flee": ["Strategic retreat! Very brave retreat!",
                 "You hold them off! I'll guard... back here!",
                 "Not running! Repositioning-repositioning!"],
    },
}


def new_pet(species, name, x, y):
    s = PETS[species]
    return Pet(x, y, name or s["default_name"], s["glyph"], s["colour"], s["hp"], s["hp"],
               s["power"], s["defence"], s["accuracy"], s["evasion"], species=species)

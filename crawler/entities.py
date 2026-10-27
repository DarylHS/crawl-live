"""Player, monsters and the monster table.

Monsters are plain data in MONSTERS so new ones can be added without code.
"""
from dataclasses import dataclass, field

from . import config as C
from .attributes import ATTRS, BASE_SCORE, POINTS_PER_LEVEL, START_POINTS


@dataclass(eq=False)
class Entity:
    """Anything that fights. Combat reads: attack (to-hit bonus), ac (Armour Class),
    dmg_n / dmg_die / dmg_bonus (damage dice, e.g. 1d8+2), dr (damage reduction) and
    crit_range (how many top d20 faces crit; 1 means only a natural 20)."""
    x: int
    y: int
    name: str
    glyph: str
    colour: tuple
    max_hp: int
    hp: int
    attack: int = 0
    ac: int = 10
    dmg_n: int = 1
    dmg_die: int = 4
    dmg_bonus: int = 0
    dr: int = 0
    crit_range: int = 1

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

    def damage_text(self):
        from .dice import fmt
        return fmt(self.dmg_n, self.dmg_die, self.dmg_bonus)


@dataclass(eq=False)
class Player(Entity):
    """The player's combat numbers are derived from attributes, level and gear by
    World.refresh_stats; attrs holds the base scores the player has bought."""
    level: int = 1
    xp: int = 0
    kills: int = 0
    attrs: dict = field(default_factory=lambda: {k: BASE_SCORE for k in ATTRS})
    stat_points: int = START_POINTS

    def xp_to_next(self):
        return 30 + 40 * (self.level - 1)

    def gain_xp(self, amount):
        """Add XP and apply any level-ups; returns the list of new levels."""
        self.xp += amount
        gained = []
        while self.xp >= self.xp_to_next():
            self.xp -= self.xp_to_next()
            self.level += 1
            self.stat_points += POINTS_PER_LEVEL
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
    save: int = 0                   # bonus on saving throws (e.g. against bombs)
    tier: str = ""                  # "" | "opening" | "featured" | "headliner" (boss tiers)
    base: str = ""                  # for Acts: the monster they're an elite version of

    # Bosses have proper names ("Foreman Gristle"), so they never take an article.
    @property
    def the(self):
        return self.name if self.boss else f"the {self.name}"

    @property
    def The(self):
        return self.name if self.boss else f"The {self.name}"

    @property
    def a(self):
        if self.boss:
            return self.name
        return f"{'an' if self.name[0] in 'AEIOU' else 'a'} {self.name}"


@dataclass(eq=False)
class Pet(Entity):
    species: str = ""
    level: int = 1
    xp: int = 0
    kills: int = 0
    mode: str = "follow"            # "follow" | "stay" | "attack"
    cooldown: int = 0               # turns until the ability is ready
    downed: bool = False
    enraged: int = 0                # turns of double damage left (Beastmaster's Rile Up)

    def xp_to_next(self):
        return 30 + 35 * (self.level - 1)

    def gain_xp(self, amount):
        """Add XP and apply level-ups; returns the list of new levels."""
        self.xp += amount
        gained = []
        while self.xp >= self.xp_to_next():
            self.xp -= self.xp_to_next()
            self.level += 1
            self.max_hp += 4
            self.hp = min(self.max_hp, self.hp + 4)
            self.dmg_bonus += 1
            if self.level % 2 == 0:
                self.attack += 1
            if self.level % 3 == 0:
                self.ac += 1
            gained.append(self.level)
        return gained


def new_player(x, y):
    """Combat numbers are filled in by World.refresh_stats."""
    return Player(x, y, "Crawler", "@", C.PLAYER_COLOUR, 0, 0)


def stat_block(d):
    """Combat fields for an Entity from a data row: hp, ac, attack and damage dice."""
    n, die, bonus = d["dmg"]
    return dict(attack=d["attack"], ac=d["ac"], dmg_n=n, dmg_die=die, dmg_bonus=bonus,
                dr=d.get("dr", 0))


# min/max floor bound where a monster appears; weight is its relative frequency.
# Stat blocks: ac = Armour Class, attack = d20 bonus, dmg = (dice, sides, bonus), save = saving
# throw bonus. floors = (min, max) floor; weight = relative frequency there; drops = what it
# might be carrying (one is picked when it dies, ITEM_DROP_CHANCE of the time). An optional
# init key adds to its initiative roll (default 0); pets, bosses and Acts take it too.
MONSTERS = {
    "gnawer":   dict(name="Sewer Gnawer", glyph="r", colour=(170, 140, 110), hp=6, ac=11, attack=3,
                     dmg=(1, 4, 0), save=1, xp=3, floors=(1, 2), weight=6,
                     drops=("sock", "sock", "tonic")),
    "goblin":   dict(name="Knockoff Goblin", glyph="g", colour=(120, 190, 80), hp=9, ac=11, attack=4,
                     dmg=(1, 6, 0), save=1, xp=5, floors=(1, 3), weight=5,
                     drops=("tonic", "popper", "mug", "trophy")),
    "vacbot":   dict(name="Feral Vacuum Bot", glyph="v", colour=(160, 170, 190), hp=12, ac=13, attack=4,
                     dmg=(1, 4, 1), save=0, xp=8, floors=(2, 4), weight=4,
                     drops=("remote", "sock", "popper")),
    "skeleton": dict(name="Grumpy Skeleton", glyph="s", colour=(225, 220, 200), hp=14, ac=12, attack=5,
                     dmg=(1, 6, 1), save=2, xp=10, floors=(2, 4), weight=4,
                     drops=("pan", "jersey", "tonic", "trophy")),
    "brute":    dict(name="Tunnel Brute", glyph="B", colour=(200, 120, 70), hp=24, ac=12, attack=6,
                     dmg=(1, 10, 1), save=2, xp=18, floors=(3, 5), weight=3,
                     drops=("extinguisher", "brew", "vest")),
    "cultist":  dict(name="Hex Cultist", glyph="c", colour=(190, 90, 210), hp=16, ac=12, attack=6,
                     dmg=(2, 4, 1), save=3, xp=16, floors=(3, 6), weight=3,
                     drops=("brew", "fireworks", "remote"), ranged=5),
    "golem":    dict(name="Flesh Golem", glyph="G", colour=(210, 130, 140), hp=40, ac=14, attack=6,
                     dmg=(2, 6, 1), save=2, xp=35, floors=(5, 6), weight=2,
                     drops=("elixir", "plate", "brew")),
    "stalker":  dict(name="Shadow Stalker", glyph="S", colour=(110, 110, 230), hp=26, ac=15, attack=8,
                     dmg=(2, 6, 0), save=5, xp=30, floors=(5, 6), weight=2,
                     drops=("cleaver", "elixir", "fireworks")),
}


def monster_table(depth):
    """Keys and weights of monsters allowed on this floor."""
    keys = [k for k, m in MONSTERS.items() if m["floors"][0] <= depth <= m["floors"][1]]
    return keys, [MONSTERS[k]["weight"] for k in keys]


def spawn_monster(key, x, y):
    m = MONSTERS[key]
    return Monster(x, y, m["name"], m["glyph"], m["colour"], m["hp"], m["hp"], **stat_block(m),
                   key=key, xp_value=m["xp"], ranged=m.get("ranged", 0), save=m["save"])


# Companion species. ability is handled in ai.take_pet_turn.
PETS = {
    "cat": dict(name="Alley Cat", glyph="f", colour=(240, 180, 90), hp=16, ac=13, attack=4,
                dmg=(1, 6, 1), default_name="Mittens",
                ability="pounce", ability_name="Pounce", cooldown=18,
                desc="Fast and vain. Pounce: leaps up to 3 tiles onto a monster for double damage."),
    "dog": dict(name="Scruffy Dog", glyph="d", colour=(200, 150, 110), hp=26, ac=12, attack=3,
                dmg=(1, 6, 2), default_name="Biscuit",
                ability="lick", ability_name="Lick Wounds", cooldown=18,
                desc="Loyal and sturdy. Lick Wounds: heals you when you're under half HP."),
    "budgie": dict(name="Chatty Budgie", glyph="b", colour=(120, 220, 140), hp=14, ac=15, attack=5,
                   dmg=(1, 4, 1), default_name="Pickles",
                   ability="squawk", ability_name="Ear-Splitting Squawk", cooldown=16,
                   desc="Fragile, hard to hit, never stops talking. Squawk: stuns nearby "
                        "monsters for 2 turns."),
    "mouse": dict(name="Scheming Mouse", glyph="m", colour=(190, 180, 200), hp=20, ac=14, attack=4,
                  dmg=(1, 6, 2), default_name="Skritch",
                  ability="dirty_trick", ability_name="Dirty Trick", cooldown=8,
                  desc="Cunning and cowardly. Dirty Trick: triple damage on a hurt monster. "
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


def init_mod(entity):
    """Initiative modifier for a monster or pet: its data row's optional init key, default 0.
    Acts use their base monster's row; Headliners their boss row."""
    if isinstance(entity, Pet):
        return PETS[entity.species].get("init", 0)
    if entity.tier == "headliner":
        from .bosses import BOSSES, boss_depth
        return BOSSES[boss_depth(entity)].get("init", 0)
    return MONSTERS.get(entity.base or entity.key, {}).get("init", 0)


def new_pet(species, name, x, y):
    s = PETS[species]
    return Pet(x, y, name or s["default_name"], s["glyph"], s["colour"], s["hp"], s["hp"],
               **stat_block(s), species=species)

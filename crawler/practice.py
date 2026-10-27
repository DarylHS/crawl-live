"""Practice skills: things you get better at by doing them.

Every skill starts at level 0 and is hidden ("???") until you first use it.
Using it earns practice XP; each level needs more than the last (diminishing
returns) up to MAX_LEVEL. Effects are read by the rules through World.practice(key);
the ones that change the character sheet are folded in by World.refresh_stats.

SKILLS is data: name, what trains it (shown to the player), what each level
gives, and how much XP a use is worth. The listeners at the bottom map game
events to skill XP.
"""
import math

from . import config as C
from .items import ITEMS

MAX_LEVEL = 15
SMALL_MONSTER_HP = 12           # Stomping trains on monsters this small or smaller


def xp_to_next(level):
    """Practice needed to go from level to level + 1 (gentle at first, steep later)."""
    return math.ceil(8 * 1.45 ** level)


SKILLS = {
    # --- Fighting -----------------------------------------------------------
    "fisticuffs": dict(name="Fisticuffs", group="Fighting",
                       trains="Landing punches with no weapon equipped",
                       effect="+1 unarmed damage every 2 levels"),
    "blades": dict(name="Bladework", group="Fighting",
                   trains="Landing hits with a bladed weapon",
                   effect="+1 damage with blades every 3 levels"),
    "bludgeoning": dict(name="Bludgeoning", group="Fighting",
                        trains="Landing hits with a blunt weapon",
                        effect="+1 blunt damage every 3 levels"),
    "stomping": dict(name="Stomping", group="Fighting",
                     trains="Squashing small monsters in melee",
                     effect="+1 damage against small monsters every 2 levels"),
    "cheap_shots": dict(name="Cheap Shots", group="Fighting",
                        trains="Landing critical hits",
                        effect="Crit range +1 every 5 levels (crits on 19-20 at level 5)"),
    "giant_killer": dict(name="Giant Killer", group="Fighting",
                         trains="Damaging bosses",
                         effect="+3% damage against bosses per level"),
    "lobbing": dict(name="Lobbing", group="Fighting",
                    trains="Throwing bombs",
                    effect="+8% bomb damage per level"),
    # --- Survival -----------------------------------------------------------
    "dodging": dict(name="Dodging", group="Survival",
                    trains="Being missed by attacks",
                    effect="+1 Armour Class every 4 levels"),
    "pain_tolerance": dict(name="Pain Tolerance", group="Survival",
                           trains="Getting hit and living",
                           effect="+1 max HP per level"),
    "first_aid": dict(name="First Aid", group="Survival",
                      trains="Drinking potions",
                      effect="+8% potion healing per level"),
    "power_napping": dict(name="Power Napping", group="Survival",
                          trains="Resting in safe rooms",
                          effect="Rest heals 10% faster per level"),
    "cardio": dict(name="Cardio", group="Survival",
                   trains="Walking (lots of walking)",
                   effect="+2 minutes on each new floor's timer per level"),
    "sneaking": dict(name="Sneaking", group="Survival",
                     trains="Moving near monsters that haven't noticed you",
                     effect="Monsters notice you 1 tile later per 4 levels"),
    # --- Wheeling and dealing -----------------------------------------------
    "scavenging": dict(name="Scavenging", group="Wheeling and dealing",
                       trains="Picking things up",
                       effect="+2% chance of loot in each room per level"),
    "pickpocketing": dict(name="Pickpocketing", group="Wheeling and dealing",
                          trains="Looting gold from the fallen",
                          effect="+5% gold from kills per level"),
    "haggling": dict(name="Haggling", group="Wheeling and dealing",
                     trains="Buying and selling in the shop",
                     effect="-2% shop prices and +3% sale prices per level"),
    "gambling": dict(name="Gambling", group="Wheeling and dealing",
                     trains="Opening loot boxes",
                     effect="-5% reroll fees per level"),
    "tinkering": dict(name="Tinkering", group="Wheeling and dealing",
                      trains="Crafting",
                      effect="Crafts 8% faster, 4% bonus-item chance per level"),
    "showmanship": dict(name="Showmanship", group="Wheeling and dealing",
                        trains="Entertaining the audience",
                        effect="+3% viewers gained per level"),
    "pet_bonding": dict(name="Pet Bonding", group="Wheeling and dealing",
                        trains="Your companion fighting alongside you",
                        effect="Companion deals +5% damage per level"),
}

CARDIO_STEPS = 40                    # steps per point of Cardio practice


class Practice:
    """Tracks practice XP and levels, and listens to game events to award it."""

    def __init__(self, world):
        self.world = world
        self.levels = {k: 0 for k in SKILLS}
        self.xp = {k: 0 for k in SKILLS}
        self.used = set()            # skills discovered (practised at least once)
        self.steps = 0
        ev = world.events
        for name, fn in (("player_attack", self._attack), ("kill", self._kill),
                         ("damage_taken", self._hurt), ("dodged", self._dodged),
                         ("bomb", self._bomb), ("item_use", self._item_use), ("rest", self._rest),
                         ("step", self._step), ("item_pickup", self._pickup),
                         ("shop_buy", self._shop), ("shop_sell", self._shop),
                         ("box_opened", self._box), ("craft", self._craft),
                         ("viewers_gained", self._viewers), ("pet_hit", self._pet)):
            ev.subscribe(name, fn)

    # --- Core -------------------------------------------------------------

    def level(self, key):
        return self.levels[key]

    def gain(self, key, amount=1):
        if amount <= 0:
            return
        self.used.add(key)
        if self.levels[key] >= MAX_LEVEL:
            return
        self.xp[key] += amount
        while self.levels[key] < MAX_LEVEL and self.xp[key] >= xp_to_next(self.levels[key]):
            self.xp[key] -= xp_to_next(self.levels[key])
            self.levels[key] += 1
            self._level_up(key, self.levels[key])

    def _level_up(self, key, lvl):
        w = self.world
        w.refresh_stats()                # Pain Tolerance, Dodging and the weapon skills show up
        name = SKILLS[key]["name"]
        w.toasts.append((w.turn, f"Skill up: {name} {lvl}", "silver"))
        w.messages.add(f"{name} is now level {lvl}. {SKILLS[key]['effect']}.", C.ACCENT)
        w.events.emit("practice_level", skill=key, level=lvl, title=name,
                      many_at_3=sum(v >= 3 for v in self.levels.values()))

    # --- Listeners --------------------------------------------------------

    def _attack(self, name, d):
        if not d["hit"]:
            return
        style = self.world.weapon_style()
        self.gain({"unarmed": "fisticuffs", "blade": "blades", "blunt": "bludgeoning"}[style])
        if d["crit"]:
            self.gain("cheap_shots")
        if d.get("boss"):
            self.gain("giant_killer")
        if d.get("small"):
            self.gain("stomping")

    def _kill(self, name, d):
        if d.get("by") == "melee" and d.get("small"):
            self.gain("stomping", 2)
        self.gain("pickpocketing")

    def _hurt(self, name, d):
        if d["hp"] > 0:
            self.gain("pain_tolerance")

    def _dodged(self, name, d):
        self.gain("dodging")

    def _bomb(self, name, d):
        self.gain("lobbing", 1 + d.get("kills", 0))

    def _item_use(self, name, d):
        if ITEMS[d["item"]]["kind"] == "potion":
            self.gain("first_aid", 2)

    def _rest(self, name, d):
        self.gain("power_napping", max(1, d["turns"] // 10))

    def _step(self, name, d):
        self.steps += 1
        if self.steps % CARDIO_STEPS == 0:
            self.gain("cardio")
        if d.get("sneaky"):
            self.gain("sneaking")

    def _pickup(self, name, d):
        self.gain("scavenging")

    def _shop(self, name, d):
        self.gain("haggling")

    def _box(self, name, d):
        self.gain("gambling")

    def _craft(self, name, d):
        self.gain("tinkering", 2)

    def _viewers(self, name, d):
        self.gain("showmanship", d["amount"] // 40)

    def _pet(self, name, d):
        self.gain("pet_bonding")

    # --- Save / load ------------------------------------------------------

    def to_dict(self):
        return dict(levels=self.levels, xp=self.xp, used=sorted(self.used), steps=self.steps)

    def load(self, d):
        self.levels = {**{k: 0 for k in SKILLS}, **d["levels"]}
        self.xp = {**{k: 0 for k in SKILLS}, **d["xp"]}
        self.used, self.steps = set(d["used"]), d["steps"]

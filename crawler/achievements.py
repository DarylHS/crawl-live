"""Achievements: the only way (besides sponsors) to earn loot boxes.

ACHIEVEMENTS is data. Each rule has the event it listens to (`on`) and a
test(tracker, data) that returns True when it unlocks; the Tracker keeps the
running counts and a reference to the world. Quirky things count as much as
feats: a natural 1 earns a box, just like killing a Headliner. Each unlock pops
up on screen, the System explains what you did and what you got, and the box
remembers why it was given so the reveal screen can remind you.
"""
from dataclasses import dataclass, field

from . import config as C
from .bosses import BOSSES


@dataclass
class Tracker:
    """Running totals the rules read from."""
    world: object = None
    kills: int = 0
    pickups: int = 0
    equipped: set = field(default_factory=set)
    unarmed_kills: int = 0
    pet_kills: int = 0
    maps: int = 0
    junk_sold: int = 0
    nat1s: int = 0


def _a(name, desc, tier, on, test):
    return dict(name=name, desc=desc, tier=tier, on=on, test=test)


ACHIEVEMENTS = {
    # Feats
    "first_blood":   _a("First Blood", "Killed your first monster.", "bronze",
                        "kill", lambda t, d: t.kills >= 1),
    "pest_control":  _a("Pest Control", "Killed 15 monsters.", "bronze",
                        "kill", lambda t, d: t.kills >= 15),
    "close_call":    _a("Close Call", "Landed a kill on 25% HP or less.", "silver",
                        "kill", lambda t, d: d["player_hp"] <= d["player_max_hp"] // 4),
    "deep_diver":    _a("Deep Diver", "Reached floor 3.", "silver",
                        "floor_start", lambda t, d: d["depth"] >= 3),
    "cutting_it_fine": _a("Cutting It Fine", "Took the stairs with under 10% of the timer left.",
                          "gold", "descend", lambda t, d: d["timer_left"] < 0.1 * d["timer_max"]),
    "demolition":    _a("Demolition", "Killed two monsters with one bomb.", "silver",
                        "bomb", lambda t, d: d["kills"] >= 2),
    "pyrotechnician": _a("Pyrotechnician", "Killed three monsters with one bomb.", "gold",
                         "bomb", lambda t, d: d["kills"] >= 3),
    "opening_night": _a("Opening Night", "Took down an Opening Act.", "bronze",
                        "act_kill", lambda t, d: d["tier"] == "opening"),
    "upstaged":      _a("Upstaged", "Took down a Featured Act.", "silver",
                        "act_kill", lambda t, d: d["tier"] == "featured"),
    "locksmith":     _a("Locksmith", "Used a Headliner's key to leave a floor early.", "silver",
                        "descend", lambda t, d: d.get("early", False)),
    "one_hp_wonder": _a("One HP Wonder", "Took a hit and lived on exactly 1 HP.", "gold",
                        "damage_taken", lambda t, d: d["hp"] == 1),
    "crowd_pleaser": _a("Crowd Pleaser", "Reached 1,000 viewers.", "silver",
                        "viewers_gained", lambda t, d: t.world.viewers >= 1000),
    "best_friends":  _a("Best Friends", "Got your companion to level 3.", "silver",
                        "pet_level_up", lambda t, d: d["level"] >= 3),
    "pet_project":   _a("Pet Project", "Your companion landed 10 kills.", "silver",
                        "pet_kill", lambda t, d: t.pet_kills >= 10),
    "jack_of_all_trades": _a("Jack of All Trades", "Got 8 practice skills to level 3.", "gold",
                             "practice_level", lambda t, d: d["many_at_3"] >= 8),
    # Quirks
    "critical_darling": _a("Critical Darling", "Rolled a natural 20.", "bronze",
                           "nat20", lambda t, d: True),
    "blooper_reel":  _a("Blooper Reel", "Rolled a natural 1. The audience loved it.", "bronze",
                        "nat1", lambda t, d: True),
    "cursed_dice":   _a("Cursed Dice", "Rolled five natural 1s in one run.", "silver",
                        "nat1", lambda t, d: t.nat1s >= 5),
    "underfoot":     _a("Underfoot", "Reached Stomping level 3. Squish.", "bronze",
                        "practice_level", lambda t, d: d["skill"] == "stomping" and d["level"] >= 3),
    "bare_knuckle_tv": _a("Bare-Knuckle Television", "Killed 10 monsters with your bare hands.",
                          "silver", "kill", lambda t, d: t.unarmed_kills >= 10),
    "cartographer":  _a("Cartographer", "Collected three maps from Opening Acts.", "silver",
                        "map_found", lambda t, d: t.maps >= 3),
    "pack_rat":      _a("Pack Rat", "Picked up 10 items.", "bronze",
                        "item_pickup", lambda t, d: t.pickups >= 10),
    "hoarder":       _a("Hoarder", "Filled every slot in your pack.", "bronze",
                        "item_pickup", lambda t, d: len(t.world.inventory) >= C.INVENTORY_SIZE),
    "dressed_to_kill": _a("Dressed to Kill", "Wore a weapon and armour at once.", "bronze",
                          "equip", lambda t, d: {"weapon", "armour"} <= t.equipped),
    "dumpster_diver": _a("Dumpster Diver", "Sold five pieces of junk.", "bronze",
                         "shop_sell", lambda t, d: t.junk_sold >= 5),
    "upcycler":      _a("Upcycler", "Crafted something out of rubbish.", "bronze",
                        "craft", lambda t, d: True),
    "nap_champion":  _a("Nap Champion", "Rested for three hours in one go.", "bronze",
                        "rest", lambda t, d: d["turns"] >= 180),
}

# One per Headliner: their box tier rises with the floor.
for _depth, _b in BOSSES.items():
    ACHIEVEMENTS[f"headliner_{_depth}"] = _a(
        f"Show Stopper: {_b['name']}", f"Took down floor {_depth}'s Headliner, {_b['name']}.",
        _b["box"], "boss_kill", lambda t, d, depth=_depth: d["depth"] == depth)


class Achievements:
    def __init__(self, world):
        self.world = world
        self.unlocked = {}              # key -> turn unlocked
        self.tracker = Tracker(world)
        for ev in {a["on"] for a in ACHIEVEMENTS.values()}:
            world.events.subscribe(ev, self._on_event)
        world.events.subscribe("unequip", self._on_unequip)

    def _on_unequip(self, name, data):
        self.tracker.equipped.discard(data["slot"])

    def _on_event(self, name, data):
        t = self.tracker
        if name == "kill":
            t.kills += 1
            if data.get("by") == "melee" and data.get("style") == "unarmed":
                t.unarmed_kills += 1
        elif name == "item_pickup":
            t.pickups += 1
        elif name == "equip":
            t.equipped.add(data["slot"])
        elif name == "pet_kill":
            t.pet_kills += 1
        elif name == "map_found":
            t.maps += 1
        elif name == "nat1":
            t.nat1s += 1
        elif name == "shop_sell" and data.get("item_kind") == "junk":
            t.junk_sold += 1
        for key, a in ACHIEVEMENTS.items():
            if a["on"] == name and key not in self.unlocked and a["test"](t, data):
                self._unlock(key, a)

    def _unlock(self, key, a):
        from .loot import BOX_TIERS
        w = self.world
        self.unlocked[key] = w.turn
        box = BOX_TIERS[a["tier"]]["name"]
        w.add_toast(f"Achievement: {a['name']}", a["tier"], f"{box} box. Open it in a safe room.")
        w.messages.add(f"Achievement unlocked: {a['name']}! {a['desc']}", C.ACCENT)
        w.events.emit("achievement", key=key, title=a["name"], tier=a["tier"], turn=w.turn,
                      why=a["desc"], reward=f"a {box} box")
        w.add_box(a["tier"], f"{a['name']}. {a['desc']}")

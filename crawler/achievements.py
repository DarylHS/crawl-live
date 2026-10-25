"""Achievements: listen to the event bus and award a loot box for each.

ACHIEVEMENTS is data. Each rule is (event, test), where test(state, data)
returns True when the achievement unlocks; `state` is the running Tracker.
"""
from dataclasses import dataclass, field

from . import config as C


@dataclass
class Tracker:
    """Running totals the rules read from."""
    kills: int = 0
    pickups: int = 0
    equipped: set = field(default_factory=set)


ACHIEVEMENTS = {
    "first_blood":   dict(name="First Blood", desc="Kill your first monster.", tier="bronze",
                          on="kill", test=lambda t, d: t.kills >= 1),
    "pest_control":  dict(name="Pest Control", desc="Kill 15 monsters.", tier="bronze",
                          on="kill", test=lambda t, d: t.kills >= 15),
    "close_call":    dict(name="Close Call", desc="Land a kill at 25% HP or less.", tier="silver",
                          on="kill", test=lambda t, d: d["player_hp"] <= d["player_max_hp"] // 4),
    "deep_diver":    dict(name="Deep Diver", desc="Reach floor 3.", tier="silver",
                          on="floor_start", test=lambda t, d: d["depth"] >= 3),
    "cutting_it_fine": dict(name="Cutting It Fine", desc="Take the stairs with under 10% of the timer left.",
                          tier="gold", on="descend",
                          test=lambda t, d: d["timer_left"] < 0.1 * d["timer_max"]),
    "pack_rat":      dict(name="Pack Rat", desc="Pick up 10 items.", tier="bronze",
                          on="item_pickup", test=lambda t, d: t.pickups >= 10),
    "dressed_to_kill": dict(name="Dressed to Kill", desc="Wear a weapon and armour at once.",
                          tier="bronze", on="equip",
                          test=lambda t, d: {"weapon", "armour"} <= t.equipped),
    "demolition":    dict(name="Demolition", desc="Kill two or more monsters with one bomb.",
                          tier="silver", on="bomb", test=lambda t, d: d["kills"] >= 2),
    "giant_slayer":  dict(name="Giant Slayer", desc="Defeat a floor boss.", tier="gold",
                          on="boss_kill", test=lambda t, d: True),
    "best_friends":  dict(name="Best Friends", desc="Get your pet to level 3.", tier="silver",
                          on="pet_level_up", test=lambda t, d: d["level"] >= 3),
    "jack_of_all_trades": dict(name="Jack of All Trades", desc="Get 8 practice skills to level 3.",
                          tier="gold", on="practice_level",
                          test=lambda t, d: d["many_at_3"] >= 8),
}


class Achievements:
    def __init__(self, world):
        self.world = world
        self.unlocked = {}              # key -> turn unlocked
        self.tracker = Tracker()
        for ev in {a["on"] for a in ACHIEVEMENTS.values()}:
            world.events.subscribe(ev, self._on_event)
        world.events.subscribe("unequip", self._on_unequip)

    def _on_unequip(self, name, data):
        self.tracker.equipped.discard(data["slot"])

    def _on_event(self, name, data):
        t = self.tracker
        if name == "kill":
            t.kills += 1
        elif name == "item_pickup":
            t.pickups += 1
        elif name == "equip":
            t.equipped.add(data["slot"])
        for key, a in ACHIEVEMENTS.items():
            if a["on"] == name and key not in self.unlocked and a["test"](t, data):
                self._unlock(key, a)

    def _unlock(self, key, a):
        w = self.world
        self.unlocked[key] = w.turn
        w.toasts.append((w.turn, f"Achievement: {a['name']}", a["tier"]))
        w.messages.add(f"Achievement unlocked: {a['name']}! ({a['desc']})", C.ACCENT)
        w.events.emit("achievement", key=key, title=a["name"], tier=a["tier"], turn=w.turn)
        w.add_box(a["tier"], "achievement")

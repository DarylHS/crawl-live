"""Crafting recipes for the safe-room bench. Each recipe turns two items into one."""
from collections import Counter

CRAFT_TURNS = 10                 # floor time spent at the bench per craft

RECIPES = [
    dict(key="sock_tea", name="Sock Tea", needs=("sock", "mug"), makes="tonic",
         desc="Brew a Soggy Sock in a Sponsor Mug. It heals. Don't ask how."),
    dict(key="remote_rocket", name="Remote Rocket", needs=("remote", "popper"), makes="fireworks",
         desc="Wire a Mystery Remote into a Party Popper Bomb for a much bigger bang."),
    dict(key="trophy_blade", name="Trophy Blade", needs=("trophy", "pan"), makes="cleaver",
         desc="Grind Half a Trophy into the edge of a Dented Frying Pan."),
    dict(key="trophy_plate", name="Trophy Plating", needs=("trophy", "jersey"), makes="vest",
         desc="Bolt trophy scraps onto a Padded Gym Jersey."),
]


def can_craft(recipe, inventory):
    have = Counter(inventory)
    return all(have[k] >= n for k, n in Counter(recipe["needs"]).items())

import random
from collections import Counter

import pytest

from crawler.dice import average
from crawler.items import ITEMS
from crawler.loot import BOX_TIERS, TIERS, odds, roll_box
from crawler.world import World


def test_five_tiers_four_items_each():
    assert TIERS == list(BOX_TIERS) and len(TIERS) == 5
    for tier, box in BOX_TIERS.items():
        assert len(box["table"]) == 4
        assert all(k in ITEMS and w > 0 for k, w in box["table"])
        assert sum(p for _, p in odds(tier)) == pytest.approx(1)


def test_roll_matches_stated_odds():
    rng = random.Random(1)
    n = 20000
    for tier in TIERS:
        seen = Counter(roll_box(tier, rng) for _ in range(n))
        for key, p in odds(tier):
            assert seen[key] / n == pytest.approx(p, abs=0.02)


def test_higher_tiers_are_better_on_average():
    def value(k):
        it = ITEMS[k]
        dice = average(*it["dice"]) if "dice" in it else 0
        if it["kind"] == "bomb":
            return dice / 3
        return dice * 2 + it.get("hit", 0) + it.get("ac", 0) * 2 + it.get("heal", 0) / 5
    ev = [sum(p * value(k) for k, p in odds(t)) for t in TIERS]
    assert ev == sorted(ev) and ev[0] < ev[-1]


def test_box_opens_only_in_safe_room():
    w = World(seed=2)
    w.add_box("gold", "test")
    assert not w.open_box("gold") and w.boxes == ["gold"]
    w.player.x, w.player.y = w.floor.safe_room.centre
    assert w.open_box("gold")
    assert w.boxes == [] and len(w.inventory) == 1
    tier, key = w.last_reveal
    assert tier == "gold" and key in dict(BOX_TIERS["gold"]["table"])


def test_open_box_needs_space_and_ownership():
    w = World(seed=2)
    w.player.x, w.player.y = w.floor.safe_room.centre
    assert not w.open_box("gold")                # none owned
    w.add_box("gold", "test")
    w.inventory = ["sock"] * 16
    assert not w.open_box("gold") and w.boxes == ["gold"]

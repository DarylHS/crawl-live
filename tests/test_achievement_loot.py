"""Phase 6c: boxes come from achievements and sponsors, and remember why."""
import random

from crawler.achievements import ACHIEVEMENTS
from crawler.entities import MONSTERS, spawn_monster
from crawler.loot import TRADE_UP_COST
from crawler.world import World


def _in_safe_room(w):
    w.player.x, w.player.y = w.floor.safe_room.centre


def test_a_box_remembers_why_and_the_reveal_says_so():
    w = World(seed=1)
    w.events.emit("nat1", foe="the goblin", Foe="The goblin")          # Blooper Reel
    assert "blooper_reel" in w.achievements.unlocked
    assert any("Blooper Reel" in t[1] and len(t) == 4 for t in w.toasts)  # pop-up with reward line
    tier = ACHIEVEMENTS["blooper_reel"]["tier"]
    assert tier in w.boxes and "natural 1" in w.box_reasons[tier][0]
    _in_safe_room(w)
    assert w.open_box(tier)
    assert w.last_reason.startswith("Blooper Reel") and w.box_log[-1]["reason"] == w.last_reason


def test_reasons_stay_in_order_per_tier():
    w = World(seed=2)
    w.add_box("bronze", "first")
    w.add_box("silver", "middle")
    w.add_box("bronze", "second")
    _in_safe_room(w)
    w.open_box("bronze")
    assert w.last_reason == "first"
    w.open_box("bronze")
    assert w.last_reason == "second"


def test_trade_up_gives_the_new_box_its_own_reason():
    w = World(seed=3)
    for i in range(TRADE_UP_COST):
        w.add_box("bronze", f"b{i}")
    _in_safe_room(w)
    assert w.trade_up("bronze")
    assert w.box_reasons["bronze"] == [] and "Traded up" in w.box_reasons["silver"][0]


def test_sponsor_gift_says_who_sent_it():
    w = World(seed=4)
    w.showrunner._gain(1000)
    tier = w.boxes[0]
    assert "gift from" in w.box_reasons[tier][0].lower()


def test_boxes_only_come_from_achievements_and_sponsors():
    w = World(seed=5)
    boss = next(m for m in w.monsters if m.tier == "headliner")
    boss.hp = 0
    w._after_hit(boss, "melee")
    reasons = [r for rs in w.box_reasons.values() for r in rs]
    assert reasons and all(r.startswith(("Show Stopper", "First Blood", "A gift from"))
                           for r in reasons)


def test_monsters_drop_from_their_own_pockets():
    w = World(seed=6)
    w.loot_rng = random.Random(0)
    drops = []
    for _ in range(60):
        m = spawn_monster("goblin", w.player.x + 1, w.player.y)
        w.monsters.append(m)
        m.hp = 0
        w._after_hit(m, "melee")
        drops += w.floor_items.pop((m.x, m.y), [])
    assert drops and set(drops) <= set(MONSTERS["goblin"]["drops"])
    assert 0.1 < len(drops) / 60 < 0.45


def test_achievement_event_tells_the_system_why_and_what():
    w = World(seed=7)
    said = []
    w.events.subscribe("achievement", lambda n, d: said.append(d))
    w.events.emit("nat20", foe="the goblin", Foe="The goblin")
    assert said and said[0]["why"] and said[0]["reward"].endswith("box")

from crawler.achievements import ACHIEVEMENTS
from crawler.entities import MONSTERS
from crawler.loot import TIERS
from crawler.showrunner import LINES, MIN_VIEWERS, SPONSOR_GIFTS, START_VIEWERS
from crawler.world import World


def _kill(w, hp=None, monster="goblin", by="melee"):
    p = w.player
    w.events.emit("kill", monster=monster, depth=1, turn=w.turn, by=by,
                  player_hp=p.hp if hp is None else hp, player_max_hp=p.max_hp)


def test_five_lines_per_event_and_all_format():
    assert all(len(v) >= 5 for v in LINES.values())
    w = World(seed=1)
    for kind in LINES:
        w.showrunner._say(kind, depth=1, name="x", level=2, tier="Gold", sponsor="S", achievement="A")
    assert all(not m[0].count("{") for m in w.messages.recent(100))


def test_viewers_rise_on_kills_and_streaks_pay_more():
    w = World(seed=1)
    assert w.viewers == START_VIEWERS
    _kill(w)                                    # also unlocks First Blood
    w.turn += 20
    before = w.viewers
    _kill(w)
    single = w.viewers - before
    assert single > 0
    before = w.viewers
    _kill(w)                                    # same turn: multi-kill
    assert w.viewers - before > single


def test_clutch_kill_pays_more():
    a, b = World(seed=1), World(seed=1)
    _kill(a)
    _kill(b, hp=1)
    assert b.viewers > a.viewers


def test_viewers_decay_when_idle_but_not_below_floor():
    w = World(seed=1)
    for _ in range(40):
        w.wait()
    assert w.viewers < START_VIEWERS
    for _ in range(600):
        w.showrunner._idle("turn", {"turn": w.turn + 10})
        w.turn += 10
    assert w.viewers == MIN_VIEWERS


def test_sponsor_gift_at_threshold():
    w = World(seed=1)
    gifts = []
    w.events.subscribe("sponsor_gift", lambda n, d: gifts.append(d))
    w.showrunner._gain(SPONSOR_GIFTS[0][0])
    assert gifts and gifts[0]["tier"] == SPONSOR_GIFTS[0][1]
    assert SPONSOR_GIFTS[0][1] in w.boxes
    w.showrunner._gain(1)
    assert len(gifts) == 1                      # no repeat
    assert [t for _, t, _ in SPONSOR_GIFTS] == TIERS


def test_announcer_does_not_change_the_dungeon():
    a, b = World(seed=7), World(seed=7)
    for _ in range(30):                         # chatter on one side only
        a.showrunner._say("kill", name="x")
    assert a.floor.tiles == b.floor.tiles and a.floor_items == b.floor_items
    assert a.rng.random() == b.rng.random()


def test_achievements_unlock_once_and_award_boxes():
    w = World(seed=3)
    assert len(ACHIEVEMENTS) == 10
    _kill(w)
    assert "first_blood" in w.achievements.unlocked
    assert w.boxes.count("bronze") >= 1 and any("First Blood" in t[1] for t in w.toasts)
    n = len(w.boxes)
    _kill(w)
    assert len(w.boxes) == n and w.achievements.tracker.kills == 2
    assert sum("First Blood" in t[1] for t in w.toasts) == 1


def test_close_call_and_cutting_it_fine():
    w = World(seed=3)
    _kill(w, hp=2)
    assert "close_call" in w.achievements.unlocked
    w.events.emit("descend", depth=1, turn=5, timer_left=10, timer_max=720)
    assert "cutting_it_fine" in w.achievements.unlocked


def test_dressed_to_kill_and_pack_rat_and_demolition():
    w = World(seed=3)
    w.inventory = ["pan", "jersey"]
    w.equip(0)
    assert "dressed_to_kill" not in w.achievements.unlocked
    w.equip(0)
    assert "dressed_to_kill" in w.achievements.unlocked
    for _ in range(10):
        w.events.emit("item_pickup", item="sock")
    assert "pack_rat" in w.achievements.unlocked
    w.events.emit("bomb", item="popper", kills=2)
    assert "demolition" in w.achievements.unlocked


def test_deep_diver_via_descend():
    w = World(seed=3)
    w.new_floor(2)
    assert "deep_diver" not in w.achievements.unlocked
    w.new_floor(3)
    assert "deep_diver" in w.achievements.unlocked


def test_every_monster_has_viewer_value():
    assert all("xp" in m for m in MONSTERS.values())

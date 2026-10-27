from crawler.achievements import ACHIEVEMENTS
from crawler.entities import MONSTERS
from crawler.loot import TIERS
from crawler.showrunner import LINES, MIN_VIEWERS, SPONSOR_GIFTS, START_VIEWERS
from crawler.world import World


def _kill(w, hp=None, monster="goblin", by="melee"):
    p = w.player
    w.events.emit("kill", monster=monster, depth=1, turn=w.turn, by=by,
                  player_hp=p.hp if hp is None else hp, player_max_hp=p.max_hp)


def test_every_event_has_mild_and_spicy_lines_that_format():
    w = World(seed=1)
    ctx = dict(depth=1, name="x", level=2, tier="Gold", sponsor="S", achievement="A", pet="P",
               ability="B", boss="Boss", title="Elf Duellist", item="Sock", value=2, ev="7",
               deal="Gloop Blitz", foe="the goblin", Foe="The goblin",
               why="Rolled a natural 1.", reward="a Bronze box")
    for kind, pools in LINES.items():
        assert len(pools["mild"]) >= 2 and len(pools["spicy"]) >= 3, kind
        assert len(pools["mild"]) + len(pools["spicy"]) >= 5, kind
        for line in pools["mild"] + pools["spicy"]:
            text = line.format_map(dict(ctx, hero="Daz", address="madam"))   # KeyError if unknown
            assert "{" not in text, (kind, line)
    for kind in LINES:
        w.showrunner._say(kind, **ctx)
    assert all("{" not in m[0] for m in w.messages.recent(200))


def test_sass_level_controls_spice(monkeypatch):
    from crawler import config as C
    for level, expect in ((0, "mild"), (10, "spicy")):
        monkeypatch.setattr(C, "SASS_LEVEL", level)
        w = World(seed=2)
        w.messages.lines.clear()
        for _ in range(20):
            w.showrunner._say("player_death")
        said = {m[0].removeprefix("SYSTEM: ") for m in w.messages.recent(20)}
        pool = {line.format_map({"address": w.address, "hero": w.hero_name})
                for line in LINES["player_death"][expect]}
        assert said <= pool


def test_box_reactions_follow_the_roll():
    from crawler.showrunner import box_kind
    assert box_kind("silver", "trophy") == "box_junk"
    assert box_kind("legendary", "katana") == "box_jackpot"
    assert box_kind("silver", "brew") == "box_meh"
    assert box_kind("silver", "vest") == "box_good"          # 22 vs 13.7 +/- 6.1
    assert box_kind("platinum", "elixir") == "box_meh"       # 30 vs 30.9 +/- 10.0
    assert box_kind("platinum", "fireworks") == "box_bad"    # 20 < 30.9 - 10.0
    assert box_kind("legendary", "fireworks") == "box_bad"   # 20 vs 42.5 +/- 13.8
    w = World(seed=3)
    w.events.emit("box_opened", tier="legendary", item="katana", rerolled=False)
    assert "Katana" in w.messages.recent(1)[0][0]


def test_address_follows_gender_and_race():
    w = World(seed=4, hero=dict(name="Daz", gender="male", backstory="veteran"))
    assert w.address == "sir" and w.hero_name == "Daz"
    w.new_floor(3)
    w.choose_class("bog_troll", "brawler")
    assert w.address == "creature"


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
    assert len(ACHIEVEMENTS) >= 30 and all(a["desc"].endswith(".") for a in ACHIEVEMENTS.values())
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

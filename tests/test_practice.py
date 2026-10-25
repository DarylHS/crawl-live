"""Practice skills: XP and levels, permanent gains, effects in the rules, save and telemetry."""
import random

from crawler import config as C
from crawler import save
from crawler import world as world_mod
from crawler.entities import spawn_monster
from crawler.practice import CARDIO_STEPS, MAX_LEVEL, SKILLS, xp_to_next
from crawler.world import World

from test_phase3 import _clear, _free_tiles_near, _play


def test_xp_curve_is_increasing_and_capped():
    costs = [xp_to_next(n) for n in range(MAX_LEVEL)]
    assert costs == sorted(costs) and costs[0] >= 1
    w = World(seed=1)
    w.training.gain("stomping", 10_000)
    assert w.practice("stomping") == MAX_LEVEL
    w.training.gain("stomping", 50)                 # no XP past the cap
    assert w.practice("stomping") == MAX_LEVEL


def test_skills_are_hidden_until_used_and_level_up_announces():
    w = World(seed=2)
    t = w.training
    assert len(SKILLS) >= 20 and not t.used
    levels = []
    w.events.subscribe("practice_level", lambda _, d: levels.append(d["level"]))
    t.gain("haggling", xp_to_next(0))
    assert "haggling" in t.used and w.practice("haggling") == 1 and levels == [1]
    assert any("Skill up: Haggling 1" in toast[1] for toast in w.toasts)


def test_stat_gains_apply_once_per_level():
    w = World(seed=3)
    p = w.player
    hp, ev = p.max_hp, p.evasion
    t = w.training
    while w.practice("pain_tolerance") < 3:
        t.gain("pain_tolerance")
    while w.practice("dodging") < 4:
        t.gain("dodging")
    assert p.max_hp == hp + 3 and p.evasion == ev + 1


def _adjacent_gnawer(w):
    _clear(w)
    x, y = _free_tiles_near(w, w.player.x, w.player.y, 1)[0]
    m = spawn_monster("gnawer", x, y)
    m.hp = 999                                  # survives every hit; max_hp still "small"
    w.monsters.append(m)
    return m


def test_stomping_adds_damage_against_small_monsters(monkeypatch):
    seen = []
    real = world_mod.attack
    monkeypatch.setattr(world_mod, "attack", lambda *a, **k: seen.append(k) or real(*a, **k))
    w = World(seed=4)
    m = _adjacent_gnawer(w)
    w.training.levels["stomping"] = 5
    w._player_attack(m)
    assert seen[-1]["bonus"] == 2               # unarmed, no fisticuffs yet: all from stomping


def test_hitting_trains_the_matching_weapon_skill():
    w = World(seed=5)
    m = _adjacent_gnawer(w)
    for _ in range(10):                         # a few swings, so at least one lands
        w._player_attack(m)
    assert {"fisticuffs", "stomping"} <= w.training.used
    w.equipment["weapon"] = "cleaver"
    for _ in range(10):
        w._player_attack(m)
    assert "blades" in w.training.used


def test_sneaking_shortens_notice_range():
    w = World(seed=6)
    assert w.notice_range() == C.FOV_RADIUS
    w.training.levels["sneaking"] = 8
    assert w.notice_range() == C.FOV_RADIUS - 2


def test_haggling_and_gambling_change_prices():
    w = World(seed=7)
    key = next(iter(w.shop.stock))
    buy, sell, fee = w.buy_price(key), w.sell_price(key), w.reroll_fee("gold")
    w.training.levels.update(haggling=10, gambling=10)
    assert w.buy_price(key) < buy and w.sell_price(key) >= sell and w.reroll_fee("gold") < fee


def test_cardio_trains_by_walking_and_extends_the_next_timer():
    w = World(seed=8)
    w.player.max_hp = w.player.hp = 1000
    _play(w, random.Random(1), CARDIO_STEPS * 3)
    assert "cardio" in w.training.used
    w.training.levels["cardio"] = 4
    base = C.floor_turns(2) + w.trait("timer_bonus", 0)
    w.new_floor(2)
    assert w.timer_max == base + 8


def test_save_round_trip_keeps_practice(tmp_path):
    w = World(seed=9)
    w.training.gain("scavenging", 30)
    w.training.gain("first_aid", 3)
    path = tmp_path / "slot.json"
    save.save(w, path)
    v = save.load(path)
    assert v.training.levels == w.training.levels and v.training.xp == w.training.xp
    assert v.training.used == w.training.used


def test_telemetry_has_one_practice_row_per_skill():
    from crawler.telemetry import Telemetry
    w = World(seed=10)
    t = Telemetry(w, source="bot", run_id=1)
    w.training.gain("lobbing", 10)
    tables = t.tables()
    assert len(tables["practice"]) == len(SKILLS)
    row = next(r for r in tables["practice"] if r["skill"] == "lobbing")
    assert row["level"] == w.practice("lobbing") and row["used"]
    assert tables["runs"][0]["practice_levels"] == sum(w.training.levels.values())

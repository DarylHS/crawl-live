import random

from crawler import config as C
from crawler.combat import attack, expected_damage, hit_chance
from crawler.entities import new_player, spawn_monster


def test_hit_chance_clamped():
    p, m = new_player(0, 0), spawn_monster("goblin", 1, 0)
    p.accuracy = 100
    assert hit_chance(p, m) == C.HIT_MAX
    p.accuracy = -100
    assert hit_chance(p, m) == C.HIT_MIN


def test_damage_at_least_one_even_vs_huge_defence():
    rng = random.Random(0)
    p, m = new_player(0, 0), spawn_monster("golem", 1, 0)
    m.defence, p.accuracy = 999, 100
    for _ in range(50):
        m.hp = m.max_hp
        res = attack(p, m, rng)
        assert not res.hit or res.damage == 1


def test_simulated_damage_matches_expected():
    rng = random.Random(42)
    p, m = new_player(0, 0), spawn_monster("skeleton", 1, 0)
    m.max_hp = 10**9
    n, total = 40_000, 0
    for _ in range(n):
        m.hp = m.max_hp
        total += attack(p, m, rng).damage
    assert abs(total / n - expected_damage(p, m)) < 0.05


def test_level_up_raises_stats():
    p = new_player(0, 0)
    hp, power = p.max_hp, p.power
    levels = p.gain_xp(p.xp_to_next())
    assert levels == [2]
    assert p.max_hp == hp + 6 and p.power == power + 1

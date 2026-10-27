"""Dice combat: d20 + attack bonus vs AC, natural 1s and 20s, damage dice, saves."""
import random

from crawler.combat import attack, expected_damage, hit_chance, saving_throw
from crawler.dice import chance_to_hit, d20, dice_distribution, needed_roll
from crawler.entities import new_player, spawn_monster
from crawler.world import World


def _player():
    return World(seed=1).player


def test_natural_one_misses_and_twenty_hits_whatever_the_numbers():
    p, m = _player(), spawn_monster("goblin", 1, 0)
    p.attack = 100
    assert hit_chance(p, m) == 19 / 20             # only a natural 1 misses
    p.attack = -100
    assert hit_chance(p, m) == 1 / 20              # only a natural 20 hits


def test_hit_chance_is_five_percent_per_point():
    # Needing 11+ on a d20 is 50%; each point of bonus is one more face.
    assert chance_to_hit(0, 11)[0] == 0.5
    assert chance_to_hit(3, 11)[0] == 0.65
    assert needed_roll(3, 11) == 8


def test_advantage_matches_two_dice_maths():
    # Advantage fails only if both dice fail: 1 - (1 - p)^2.
    p = chance_to_hit(0, 11)[0]
    assert abs(chance_to_hit(0, 11, advantage=1)[0] - (1 - (1 - p) ** 2)) < 1e-12
    assert abs(chance_to_hit(0, 11, advantage=-1)[0] - p ** 2) < 1e-12


def test_wider_crit_range_crits_more():
    assert chance_to_hit(0, 99, crit_range=1)[1] == 1 / 20
    assert chance_to_hit(0, 99, crit_range=4)[1] == 4 / 20


def test_dice_distribution_sums_to_one_and_has_the_right_mean():
    dist = dice_distribution(3, 6)
    assert abs(sum(dist.values()) - 1) < 1e-12
    assert abs(sum(t * q for t, q in dist.items()) - 10.5) < 1e-12


def test_simulated_damage_matches_expected():
    rng = random.Random(42)
    p, m = _player(), spawn_monster("skeleton", 1, 0)
    m.max_hp = 10**9
    n, total = 40_000, 0
    for _ in range(n):
        m.hp = m.max_hp
        total += attack(p, m, rng).damage
    assert abs(total / n - expected_damage(p, m)) < 0.05


def test_damage_reduction_never_takes_a_hit_below_one():
    rng = random.Random(1)
    p, m = _player(), spawn_monster("goblin", 1, 0)
    m.dr, p.attack = 999, 100
    for _ in range(50):
        m.hp = m.max_hp
        res = attack(p, m, rng)
        assert not res.hit or res.damage == 1


def test_attack_result_reports_the_roll():
    rng = random.Random(3)
    p, m = _player(), spawn_monster("goblin", 1, 0)
    res = attack(p, m, rng)
    assert 1 <= res.roll <= 20 and res.total == res.roll + p.attack and res.target == m.ac
    assert f"vs AC {m.ac}" in res.dice_text()


def test_saving_throw_and_d20_bounds():
    rng = random.Random(5)
    for _ in range(200):
        face, rolls = d20(rng, advantage=1)
        assert face == max(rolls) and 1 <= face <= 20
    saved, face = saving_throw(rng, 100, 10)
    assert saved == (face != 1)


def test_level_up_gives_attribute_points_not_stats():
    p = new_player(0, 0)
    pts = p.stat_points
    assert p.gain_xp(p.xp_to_next()) == [2]
    assert p.stat_points == pts + 2

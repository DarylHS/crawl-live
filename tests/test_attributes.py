"""Attributes: spending points, modifiers, and how backstory, race, class and gear feed the sheet."""
import pytest

from crawler.attributes import ATTRS, START_POINTS, mod, proficiency
from crawler.world import World


def test_modifier_table():
    assert [mod(s) for s in (8, 9, 10, 11, 12, 14, 18)] == [-1, -1, 0, 0, 1, 2, 4]
    assert [proficiency(lvl) for lvl in (1, 4, 5, 9, 13)] == [2, 2, 3, 4, 5]


def test_spending_points_raises_the_score_and_the_sheet():
    w = World(seed=1)
    p = w.player
    assert p.stat_points == START_POINTS
    hit, dmg = p.attack, p.dmg_bonus
    assert w.spend_point("str") and w.spend_point("str")          # 10 -> 12: +1
    assert p.attack == hit + 1 and p.dmg_bonus == dmg + 1
    ac = p.ac
    assert w.spend_point("dex") and w.spend_point("dex")
    assert p.ac == ac + 1
    hp = p.max_hp
    assert w.spend_point("con") and w.spend_point("con")
    assert p.max_hp == hp + p.level and p.hp == p.max_hp           # extra HP arrives healed
    assert p.stat_points == 0 and not w.spend_point("cha")
    assert not w.spend_point("wisdom")


def test_backstory_race_and_class_nudge_scores():
    w = World(seed=2, hero=dict(name="T", gender="female", backstory="tradie"))
    assert w.score("str") == 12
    w.choose_class("dwarf", "brawler")
    assert w.score("str") == 16 and w.score("con") == 12 and w.score("dex") == 8
    assert w.player.dmg_die == 8                                   # Brawler fists are 1d8


def test_blades_use_the_better_of_str_and_dex():
    w = World(seed=3)
    for _ in range(4):
        w.spend_point("dex")                                       # DEX 14, STR 10
    w.inventory = ["cleaver"]
    w.equip(0)
    assert w.player.dmg_bonus >= 2 + w.mod("dex")
    w.inventory.append("pan")
    w.equip(0)                                                     # blunt: back to STR
    assert w.player.dmg_bonus == w.mod("str") + 2


def test_heavy_armour_caps_dexterity():
    w = World(seed=4)
    for _ in range(6):
        w.spend_point("dex")                                       # DEX 16: +3
    w.inventory = ["plate"]
    w.equip(0)
    assert w.player.ac == 10 + 0 + 4                               # plate: no DEX bonus


def test_level_up_points_and_hp():
    w = World(seed=5)
    p = w.player
    hp = p.max_hp
    p.gain_xp(p.xp_to_next())
    w.refresh_stats()
    assert p.stat_points == START_POINTS + 2 and p.max_hp > hp


@pytest.mark.parametrize("attr", list(ATTRS))
def test_every_attribute_can_be_raised(attr):
    w = World(seed=6)
    before = w.score(attr)
    assert w.spend_point(attr) and w.score(attr) == before + 1

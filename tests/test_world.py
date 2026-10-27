import random

import pytest

from crawler import config as C
from crawler.dungeon import NEIGHBOURS_8, STAIRS
from crawler.entities import spawn_monster
from crawler.world import World


def _clear(world):
    world.monsters.clear()


def _free_neighbour(world):
    p = world.player
    for dx, dy in NEIGHBOURS_8:
        x, y = p.x + dx, p.y + dy
        if world.floor.walkable(x, y) and not world.floor.is_safe(x, y):
            return dx, dy
    raise AssertionError("player boxed in")


def test_bump_attack_damages_monster():
    w = World(seed=3)
    _clear(w)
    dx, dy = _free_neighbour(w)
    m = spawn_monster("golem", w.player.x + dx, w.player.y + dy)
    w.monsters.append(m)
    w.player.attack = 100
    assert w.move_player(dx, dy)
    assert m.hp < m.max_hp
    assert (w.player.x, w.player.y) != (m.x, m.y)


def test_kill_awards_xp_and_emits_event():
    w = World(seed=4)
    _clear(w)
    kills = []
    w.events.subscribe("kill", lambda name, data: kills.append(data))
    dx, dy = _free_neighbour(w)
    m = spawn_monster("gnawer", w.player.x + dx, w.player.y + dy)
    m.hp = 1
    w.monsters.append(m)
    w.player.attack = 100
    w.move_player(dx, dy)
    assert kills and kills[0]["monster"] == "gnawer"
    assert w.player.kills == 1 and w.player.xp == m.xp_value
    assert m not in w.monsters


def test_timer_collapse_kills_player():
    w = World(seed=5)
    _clear(w)
    w.timer = 2
    w.wait()
    assert w.state == "playing"
    w.wait()
    assert w.state == "dead" and "collapsed" in w.death_cause


def test_descend_moves_to_next_floor_and_resets_timer():
    w = World(seed=6)
    w.player.x, w.player.y = w.floor.stairs[0]
    w.timer -= 100
    assert w.descend()
    assert w.depth == 2 and w.timer == C.floor_turns(2)


def test_final_floor_needs_the_boss_dead():
    w = World(seed=7)
    w.new_floor(C.NUM_FLOORS)
    w.player.x, w.player.y = w.floor.stairs[0]
    assert w.exit_sealed and not w.descend()
    boss = next(m for m in w.monsters if m.boss)
    boss.hp = 0
    w._after_hit(boss, "melee")
    assert not w.exit_sealed
    w.descend()
    assert w.state == "victory"


def test_descend_without_stairs_does_nothing():
    w = World(seed=8)
    assert not w.descend()
    assert w.depth == 1


def test_rest_only_in_safe_room_and_costs_time():
    w = World(seed=9)
    _clear(w)
    w.player.hp = 5
    assert not w.rest()
    w.player.x, w.player.y = w.floor.safe_room.centre
    before = w.timer
    assert w.rest()
    assert w.player.hp == w.player.max_hp
    assert w.timer < before


def test_no_fighting_in_safe_room():
    w = World(seed=10)
    _clear(w)
    sr = w.floor.safe_room
    w.player.x, w.player.y = sr.x, sr.y   # corner of safe room
    # Put a monster just outside the room, adjacent diagonally.
    mx, my = sr.x - 1, sr.y - 1
    w.floor.tiles[my][mx] = 1
    m = spawn_monster("goblin", mx, my)
    m.alerted = True
    w.monsters.append(m)
    hp = w.player.hp
    assert not w.move_player(-1, -1)
    for _ in range(20):
        w.wait()
    assert w.player.hp >= hp
    assert m.hp == m.max_hp


@pytest.mark.parametrize("seed", range(12))
def test_random_play_smoke(seed):
    """A random bot plays many turns: no crashes, monsters never enter safe rooms."""
    rng = random.Random(seed)
    w = World(seed=seed)
    w.player.max_hp = w.player.hp = 10_000   # keep it alive to cover more floors
    for _ in range(4000):
        if w.state != "playing":
            break
        if w.on_stairs and rng.random() < 0.5:
            w.descend()
        elif w.in_safe_room and rng.random() < 0.05:
            w.rest()
        else:
            w.move_player(*rng.choice(NEIGHBOURS_8))
        for m in w.monsters:
            assert not w.floor.is_safe(m.x, m.y)
            assert w.floor.walkable(m.x, m.y)
        positions = [(m.x, m.y) for m in w.monsters]
        assert len(positions) == len(set(positions))
        assert (w.player.x, w.player.y) not in positions
    assert w.turn > 0


def test_stairs_reachable_on_every_floor():
    w = World(seed=11)
    for depth in range(1, C.NUM_FLOORS + 1):
        w.new_floor(depth)
        dist = w.floor.distance_map(w.player.x, w.player.y)
        for x, y in w.floor.stairs:
            assert w.floor.tiles[y][x] == STAIRS
            assert dist[y * w.floor.width + x] > 0

import random

import pytest

from crawler import config as C
from crawler.dungeon import FLOOR, STAIRS, WALL, Floor, compute_fov, generate_floor

SEEDS = range(25)


@pytest.mark.parametrize("seed", SEEDS)
def test_every_open_tile_reachable_from_start(seed):
    rng = random.Random(seed)
    for depth in range(1, C.NUM_FLOORS + 1):
        floor = generate_floor(rng, depth)
        sx, sy = floor.start_room.centre
        dist = floor.distance_map(sx, sy)
        for y in range(floor.height):
            for x in range(floor.width):
                if floor.tiles[y][x] != WALL:
                    assert dist[y * floor.width + x] >= 0, (seed, depth, x, y)


@pytest.mark.parametrize("seed", SEEDS)
def test_stairs_and_safe_room_placement(seed):
    floor = generate_floor(random.Random(seed), 1)
    assert len(floor.stairs) == C.STAIRS_PER_FLOOR
    for x, y in floor.stairs:
        assert floor.tiles[y][x] == STAIRS
        assert not floor.safe[y][x]
        assert not floor.start_room.contains(x, y)
    assert floor.safe_room is not floor.start_room
    assert not floor.is_safe(*floor.start_room.centre)
    assert sum(map(sum, floor.safe)) == floor.safe_room.w * floor.safe_room.h


def test_border_is_always_wall():
    floor = generate_floor(random.Random(1), 3)
    for x in range(floor.width):
        assert floor.tiles[0][x] == WALL and floor.tiles[-1][x] == WALL
    for y in range(floor.height):
        assert floor.tiles[y][0] == WALL and floor.tiles[y][-1] == WALL


def _open_box(w=21, h=21):
    floor = Floor(w, h, 1)
    for y in range(1, h - 1):
        for x in range(1, w - 1):
            floor.tiles[y][x] = FLOOR
    return floor


def test_fov_open_room_respects_radius():
    floor = _open_box()
    vis = compute_fov(floor, 10, 10, radius=5)
    assert (10, 10) in vis and (14, 10) in vis and (10, 6) in vis
    assert (16, 10) not in vis
    assert all(floor.in_bounds(x, y) for x, y in vis)


def test_fov_blocked_by_wall():
    floor = _open_box()
    for y in range(1, 20):
        floor.tiles[y][12] = WALL          # a full-height wall
    vis = compute_fov(floor, 10, 10, radius=8)
    assert (12, 10) in vis                 # the wall itself is seen
    assert (14, 10) not in vis             # but not what's behind it

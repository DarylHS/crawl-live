"""First-person proof of concept: it renders every floor, and movement maps to the facing."""
import pygame
import pytest

from crawler.bosses import BOSSES
from crawler.entities import MONSTERS, PETS
from crawler.ui.firstperson import VIEW_H, VIEW_W, FirstPersonView, creature_sprite
from crawler.world import World


@pytest.fixture(autouse=True)
def _pygame():
    pygame.init()
    yield
    pygame.quit()


def test_renders_each_floor_with_the_overlays():
    w = World(seed=4, pet=("dog", "Rex"))
    v = FirstPersonView()
    screen = pygame.Surface((1280, 768))
    for depth in range(1, 7):
        if depth > 1:
            w.new_floor(depth)
        assert v.render(w).get_size() == (VIEW_W, VIEW_H)
        v.draw(screen, w, pygame.Rect(0, 0, 1024, 640))


def test_every_creature_has_a_sprite():
    keys = list(MONSTERS) + [f"boss_{d}" for d in BOSSES] + list(PETS)
    for k in keys:
        s = creature_sprite(k, (200, 100, 50))
        assert s.get_size() == (32, 32) and s.get_bounding_rect().width > 8


def test_steps_are_relative_to_facing():
    v = FirstPersonView()
    v.facing = 0                                   # north
    assert v.relative("forward") == (0, -1) and v.relative("right") == (1, 0)
    v.turn(1)                                      # east
    assert v.relative("forward") == (1, 0) and v.relative("left") == (0, -1)
    v.turn(-2)                                     # west
    assert v.relative("back") == (1, 0)


def test_forward_attacks_a_diagonal_monster_ahead():
    from crawler.entities import spawn_monster
    w = World(seed=5)
    w.monsters.clear()
    p = w.player
    v = FirstPersonView()
    v.facing = 1
    m = spawn_monster("goblin", p.x + 1, p.y - 1)  # front-left when facing east
    w.monsters.append(m)
    target, step = v.target_ahead(w)
    assert target is m and step == (1, -1)

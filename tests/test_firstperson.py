"""First-person proof of concept: it renders every floor, and movement maps to the facing."""
import pygame
import pytest

from crawler import config as C
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


def _minimap_pixel(v, screen, x, y):
    r, s, (ox, oy) = v.minimap_rect, v.minimap_scale, v.minimap_origin
    assert ox <= x < ox + r.width // s and oy <= y < oy + r.height // s, "tile outside the minimap"
    return tuple(screen.get_at((r.x + (x - ox) * s, r.y + (y - oy) * s)))[:3]


def test_minimap_is_readable_and_tracks_exploring():
    from crawler.bosses import spawn_act
    from crawler.dungeon import STAIRS
    from crawler.ui import firstperson as fpv
    w = World(seed=6)
    w.monsters.clear()
    v = FirstPersonView()
    screen = pygame.Surface((1280, 768))
    rect = pygame.Rect(0, 0, 1024, 640)
    f, p = w.floor, w.player
    v.draw(screen, w, rect)
    ox, oy, tw, th = v.minimap_window(w)
    assert (tw, th) == fpv.MM_WINDOW and ox <= p.x < ox + tw and oy <= p.y < oy + th
    far = next((x, y) for y in range(oy, oy + th) for x in range(ox, ox + tw)
               if f.tiles[y][x] != STAIRS and f.walkable(x, y) and not f.safe[y][x]
               and (x, y) not in w.visible and abs(x - p.x) + abs(y - p.y) > 6)
    assert not f.explored[far[1]][far[0]]
    assert _minimap_pixel(v, screen, *far) != fpv.MM_FLOOR      # unexplored: backing only
    w._act_reward(spawn_act("opening", "goblin", far[0], far[1]))   # an Opening Act's map
    assert f.explored[far[1]][far[0]]
    v.draw(screen, w, rect)                                     # only the changed tiles redraw
    assert _minimap_pixel(v, screen, *far) == fpv.MM_FLOOR
    seen = next((x, y) for x, y in w.visible if f.tiles[y][x] != STAIRS and not f.safe[y][x]
                and max(abs(x - p.x), abs(y - p.y)) > 3 and f.walkable(x, y))
    assert _minimap_pixel(v, screen, *seen) == fpv.MM_IN_VIEW

    sx, sy = f.stairs[0]                                        # stand near the stairs to see them
    for dx, dy in ((x, y) for x in range(-3, 4) for y in range(-3, 4) if max(abs(x), abs(y)) == 3):
        if f.walkable(sx + dx, sy + dy):
            p.x, p.y = sx + dx, sy + dy
            w.update_fov()
            if (sx, sy) in w.visible:
                break
    v.draw(screen, w, rect)
    assert w.stairs_locked and _minimap_pixel(v, screen, sx, sy) == C.DANGER
    w.has_key = True
    v.draw(screen, w, rect)
    assert _minimap_pixel(v, screen, sx, sy) == C.ACCENT
    assert sum(fpv.MM_FLOOR) > 2 * sum(C.FLOOR_LIT)              # clearly lighter than before


def test_minimap_window_follows_you_and_stays_on_the_floor():
    from crawler.ui import firstperson as fpv
    w = World(seed=6)
    v = FirstPersonView()
    f, p = w.floor, w.player
    mw, mh = fpv.MM_WINDOW
    for x, y in ((0, 0), (f.width - 1, f.height - 1), (f.width // 2, f.height // 2)):
        p.x, p.y = x, y
        ox, oy, tw, th = v.minimap_window(w)
        assert 0 <= ox and ox + tw <= f.width and 0 <= oy and oy + th <= f.height
        assert ox <= x < ox + tw and oy <= y < oy + th
    assert (ox + mw // 2, oy + mh // 2) == (p.x, p.y)              # centred in the middle
    assert fpv.MM_SCALE >= 4 and mw * fpv.MM_SCALE <= 1024 // 4    # readable, and a corner only


def test_caches_follow_the_floor_object_not_its_id():
    """id() of a freed floor can be reused by the next one; the caches must still rebuild."""
    import numpy as np
    from crawler.dungeon import WALL
    w = World(seed=7)
    v = FirstPersonView()
    screen = pygame.Surface((1280, 768))
    rect = pygame.Rect(0, 0, 1024, 640)
    for depth in (2, 3, 2, 3):
        w.new_floor(depth)
        v.draw(screen, w, rect)
        assert v._floor is w.floor and v._mm_floor is w.floor and v._faced_floor is w.floor
        assert (v.solid == (np.array(w.floor.tiles) == WALL)).all()
        assert (v._mm_seen == np.array(w.floor.explored, bool)).all()


def test_hurt_flash_only_on_real_damage():
    w = World(seed=4)
    v = FirstPersonView()
    screen = pygame.Surface((1280, 768))
    rect = pygame.Rect(0, 0, 1024, 640)
    p = w.player
    v.draw(screen, w, rect)
    p.max_hp -= 1                                  # choosing Elf: 34 -> 33 max HP
    p.hp = min(p.hp, p.max_hp)
    v.draw(screen, w, rect)
    assert v.flash == 0
    p.hp -= 2                                      # a real hit
    v.draw(screen, w, rect)
    assert v.flash > 0
    v.flash = 0
    p.max_hp -= 1                                  # a hit in the same turn as a max HP change
    p.hp -= 3
    v.draw(screen, w, rect)
    assert v.flash > 0


def test_step_for_angle_rounds_to_the_nearest_of_8():
    from crawler.ui.firstperson import step_for_angle
    assert step_for_angle(0) == (0, -1)
    assert step_for_angle(22) == (0, -1) and step_for_angle(23) == (1, -1)
    assert step_for_angle(44) == (1, -1) and step_for_angle(46) == (1, -1)
    assert step_for_angle(68) == (1, 0) and step_for_angle(90) == (1, 0)
    assert step_for_angle(135) == (1, 1) and step_for_angle(180) == (0, 1)
    assert step_for_angle(359) == (0, -1) and step_for_angle(360) == (0, -1)
    assert step_for_angle(-45) == (-1, -1) and step_for_angle(-90) == (-1, 0)
    assert step_for_angle(-135) == (-1, 1) and step_for_angle(-400) == (-1, -1)


def test_back_and_strafe_at_45_degrees():
    v = FirstPersonView()
    v.angle = 45                                   # north-east
    assert v.relative("forward") == (1, -1) and v.relative("back") == (-1, 1)
    assert v.relative("left") == (-1, -1) and v.relative("right") == (1, 1)
    v.angle = 50                                   # off the line: still the nearest 45
    assert v.relative("right") == (1, 1) and v.facing == 1 and v.compass() == "NE"


def test_tapped_turns_land_on_45_degree_lines():
    v = FirstPersonView()
    v.angle = 90
    v.tap_turn(-1)
    assert v.angle == 45
    v.tap_turn(-1)
    v.tap_turn(-1)
    assert v.angle == 315
    v.angle = 30                                   # after free look: on to the next line
    v.tap_turn(1)
    assert v.angle == 45
    v.angle = 30
    v.tap_turn(-1)
    assert v.angle == 0


def test_target_ahead_in_8_ways():
    from crawler.entities import spawn_monster
    w = World(seed=5)
    w.monsters.clear()
    p = w.player
    v = FirstPersonView()
    v.angle = 10                                   # just east of north: ahead is north
    nw = spawn_monster("goblin", p.x - 1, p.y - 1)
    ne = spawn_monster("goblin", p.x + 1, p.y - 1)
    n = spawn_monster("goblin", p.x, p.y - 1)
    w.monsters += [nw, ne, n]
    assert v.target_ahead(w) == (n, (0, -1))       # straight ahead first
    w.monsters.remove(n)
    assert v.target_ahead(w) == (ne, (1, -1))      # then the diagonal nearer in angle
    v.angle = 350
    assert v.target_ahead(w) == (nw, (-1, -1))
    w.monsters[:] = [spawn_monster("goblin", p.x + 1, p.y)]
    v.angle = 40                                   # ahead is NE; east is 45 degrees off it
    assert v.target_ahead(w)[1] == (1, 0)
    v.angle = 180
    assert v.target_ahead(w) == (None, None)


def test_camera_glides_at_walking_speed_and_settles_on_the_tile_centre():
    from crawler.ui import firstperson as fpv
    w = World(seed=4)
    v = FirstPersonView()
    v.update_camera(w)
    w.player.x += 1
    v.update_camera(w, 0.1)                        # a tenth of a second: 0.4 of a tile
    assert abs(v.glide_left(w) - (1 - fpv.WALK_SPEED * 0.1)) < 1e-6
    for _ in range(10):
        v.update_camera(w, 0.05)
    assert v.glide_left(w) == 0 and v.cam[:2] == [w.player.x + 0.5, w.player.y + 0.5]


def test_open_facing_picks_the_longest_open_run():
    from crawler.ui.firstperson import open_facing

    class Floor:                                   # a plus shape: short north arm, long west arm
        open_ = {(5, 5), (5, 4), (6, 5), (6, 5), (4, 5), (3, 5), (2, 5), (5, 6), (5, 7)}

        def walkable(self, x, y):
            return (x, y) in self.open_

    assert open_facing(Floor(), 5, 5) == 3
    assert open_facing(Floor(), 5, 4) == 2         # the dead end faces back down the corridor
    Floor.open_ = {(5, 5)}
    assert open_facing(Floor(), 5, 5, prefer=2) == 2   # boxed in: keep the old facing


def test_combat_settles_the_angle_and_glides_to_the_tile_centre():
    w = World(seed=4)
    v = FirstPersonView()
    p = w.player
    v.angle = 130
    v.update_camera(w, 1)                          # snapped where we were looking
    v.cam[0] += 0.4                                # mid-glide, a little off the tile centre
    v.set_combat(True)
    assert v.grid and v.angle == 90
    v.update_camera(w, 0.02)
    assert v.cam != [p.x + 0.5, p.y + 0.5, v.cam[2]]   # glides, doesn't jump
    for _ in range(100):
        v.update_camera(w, 0.02)
    assert v.cam[:2] == [p.x + 0.5, p.y + 0.5] and not v.animating(w)
    assert v.relative("forward") == (1, 0) and v.relative("left") == (0, -1)
    v.set_combat(False)
    assert not v.grid and v.angle == 90            # free look resumes from the settled angle

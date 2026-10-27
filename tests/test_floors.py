"""Phase 6b: big floors, timed stairs, the Headliner's key, Acts and wandering monsters."""
from crawler import config as C
from crawler.bosses import MAP_RADIUS, acts_per_floor
from crawler.entities import MONSTERS
from crawler.world import World


def _headliner(w):
    return next(m for m in w.monsters if m.tier == "headliner")


def test_floors_are_big_with_three_stairwells():
    w = World(seed=1)
    assert (w.floor.width, w.floor.height) == (C.MAP_W, C.MAP_H)
    assert len(w.floor.stairs) == C.STAIRS_PER_FLOOR


def test_stairs_open_at_half_time_from_arrival():
    w = World(seed=2)
    w.new_floor(2)
    w.player.x, w.player.y = w.floor.stairs[0]
    assert w.stairs_locked and not w.descend()
    assert w.stairs_wait == C.floor_turns(2) // 2
    opened = []
    w.events.subscribe("stairs_open", lambda n, d: opened.append(d))
    for _ in range(w.stairs_wait):
        w._tick_clock()
    assert not w.stairs_locked and opened and w.descend() and w.depth == 3


def test_timer_bonus_does_not_delay_the_stairs():
    a = World(seed=3, hero=dict(name="R", gender="male", backstory="rideshare"))
    b = World(seed=3)
    assert a.timer > b.timer and a.stairs_wait == b.stairs_wait


def test_headliner_drops_a_key_that_opens_the_stairs():
    w = World(seed=4)
    boss = _headliner(w)
    boss.hp = 0
    w._after_hit(boss, "melee")
    assert w.has_key and not w.stairs_locked
    assert w.floor_items.get((boss.x, boss.y))                     # and a top-shelf item
    w.player.x, w.player.y = w.floor.stairs[0]
    assert w.descend() and not w.has_key                          # one floor only


def test_acts_per_floor_and_rewards():
    w = World(seed=5)
    w.new_floor(4)
    n_open, n_feat = acts_per_floor(4)
    acts = [m for m in w.monsters if m.tier in ("opening", "featured")]
    assert sum(m.tier == "opening" for m in acts) == n_open
    assert sum(m.tier == "featured" for m in acts) == n_feat
    for m in acts:
        assert m.boss and m.base in MONSTERS and m.max_hp > MONSTERS[m.base]["hp"]

    opening = next(m for m in acts if m.tier == "opening")
    for row in w.floor.explored:
        row[:] = [False] * len(row)
    opening.hp = 0
    w._after_hit(opening, "melee")
    f = w.floor
    revealed = sum(map(sum, f.explored))
    assert revealed > 50
    assert all(abs(x - opening.x) <= MAP_RADIUS and abs(y - opening.y) <= MAP_RADIUS
               for y in range(f.height) for x in range(f.width) if f.explored[y][x])

    featured = next(m for m in w.monsters if m.tier == "featured")
    featured.hp = 0
    w._after_hit(featured, "melee")
    assert len(w.floor_items[(featured.x, featured.y)]) == 2


def test_monsters_wander_in_out_of_sight_but_bosses_never_return():
    w = World(seed=6)
    w.player.max_hp = w.player.hp = 10_000
    bosses = {m.name for m in w.monsters if m.boss}
    for m in [m for m in w.monsters if not m.boss]:
        w.monsters.remove(m)
    spawned = []
    w.events.subscribe("monster_spawned", lambda n, d: spawned.append(d["monster"]))
    for _ in range(400):
        w._tick_clock()
    assert spawned and all(k in MONSTERS for k in spawned)
    assert {m.name for m in w.monsters if m.boss} == bosses
    assert sum(not m.boss for m in w.monsters) <= w._spawn_cap
    for m in w.monsters:
        assert not w.floor.is_safe(m.x, m.y)

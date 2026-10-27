import pytest

from crawler import config as C
from crawler.dungeon import NEIGHBOURS_8
from crawler.entities import spawn_monster
from crawler.items import ITEMS, floor_loot_table
from crawler.world import World


@pytest.fixture
def w():
    world = World(seed=11)
    world.monsters.clear()
    world.floor_items.clear()
    return world


def _in_safe(world):
    world.player.x, world.player.y = world.floor.safe_room.centre
    world.update_fov()


def test_item_data_is_consistent():
    assert len(ITEMS) >= 15
    kinds = {i["kind"] for i in ITEMS.values()}
    assert kinds == {"weapon", "armour", "potion", "bomb", "junk"}
    for depth in range(1, C.NUM_FLOORS + 1):
        keys, weights = floor_loot_table(depth)
        assert keys and all(k in ITEMS for k in keys) and all(x > 0 for x in weights)


def test_pickup_and_drop(w):
    p = w.player
    w.floor_items[(p.x, p.y)] = ["tonic", "sock"]
    assert w.pickup()
    assert w.inventory == ["tonic", "sock"] and (p.x, p.y) not in w.floor_items
    assert not w.pickup()                       # nothing left
    assert w.drop(0)
    assert w.inventory == ["sock"] and w.floor_items[(p.x, p.y)] == ["tonic"]


def test_pickup_respects_pack_size(w):
    w.inventory = ["sock"] * C.INVENTORY_SIZE
    w.floor_items[(w.player.x, w.player.y)] = ["tonic"]
    assert not w.pickup()
    assert len(w.inventory) == C.INVENTORY_SIZE


def test_equip_swaps_and_changes_stats(w):
    p = w.player
    hit = p.attack
    assert (p.dmg_n, p.dmg_die) == (1, 4)                 # fists
    w.inventory = ["pan", "katana"]
    w.equip(0)
    assert p.dmg_die == 6 and w.equipment["weapon"] == "pan"
    w.equip(0)                                  # katana replaces the pan
    assert p.dmg_die == 10 and p.attack == hit + ITEMS["katana"]["hit"] and w.inventory == ["pan"]
    assert w.unequip("weapon")
    assert p.dmg_die == 4 and p.attack == hit and sorted(w.inventory) == ["katana", "pan"]


def test_potion_heals_and_takes_a_turn(w):
    w.player.hp = 5
    w.inventory = ["tonic"]
    turn = w.turn
    assert w.use_item(0)
    assert w.player.hp >= 5 + ITEMS["tonic"]["heal"] and w.inventory == [] and w.turn == turn + 1


def test_potion_refused_at_full_health(w):
    w.inventory = ["tonic"]
    assert not w.use_item(0) and w.inventory == ["tonic"]


def test_bomb_hits_blast_radius_only(w):
    p = w.player
    near = [(dx, dy) for dx, dy in NEIGHBOURS_8 if w.floor.walkable(p.x + dx, p.y + dy)][0]
    a = spawn_monster("goblin", p.x + near[0], p.y + near[1])
    a.hp = 1                                    # dies even if it makes its save
    far = spawn_monster("goblin", a.x + 5, a.y + 5)     # outside the blast; position is never walked
    w.monsters += [a, far]
    w.visible = {(a.x, a.y)}
    w.inventory = ["popper"]
    kills = []
    w.events.subscribe("bomb", lambda n, d: kills.append(d["kills"]))
    assert w.use_item(0)
    assert a not in w.monsters and far in w.monsters and far.hp == far.max_hp
    assert kills == [1]


def test_bomb_needs_a_target_and_no_safe_room(w):
    w.inventory = ["popper"]
    assert not w.use_item(0) and w.inventory == ["popper"]
    _in_safe(w)
    assert not w.use_item(0)


def test_junk_is_not_usable(w):
    w.inventory = ["sock"]
    assert not w.use_item(0) and w.inventory == ["sock"]


def test_monster_drops_use_loot_rng(w, monkeypatch):
    monkeypatch.setattr(C, "ITEM_DROP_CHANCE", 1.0)
    p = w.player
    dx, dy = [d for d in NEIGHBOURS_8 if w.floor.walkable(p.x + d[0], p.y + d[1])][0]
    m = spawn_monster("gnawer", p.x + dx, p.y + dy)
    m.hp = 1
    w.monsters.append(m)
    p.attack = 100
    w.move_player(dx, dy)
    assert len(w.floor_items.get((m.x, m.y), [])) == 1


def test_new_floors_scatter_items():
    seen = sum(len(World(seed=s).floor_items) for s in range(10))
    assert seen > 10

"""Pet, classes and skills, bosses, ranged monsters, crafting and save/load."""
import random

import pytest

from crawler import config as C
from crawler import save
from crawler.ai import cheb
from crawler.bosses import BOSSES, acts_per_floor
from crawler.classes import CHOICE_FLOOR
from crawler.crafting import CRAFT_TURNS, RECIPES
from crawler.dungeon import NEIGHBOURS_8
from crawler.entities import PETS, spawn_monster
from crawler.items import ITEMS
from crawler.world import World


def _clear(w):
    w.monsters.clear()
    w.floor_items.clear()


def _free_tiles_near(w, x, y, radius):
    taken = {(m.x, m.y) for m in w.monsters} | {(w.player.x, w.player.y)}
    if w.active_pet:
        taken.add((w.pet.x, w.pet.y))
    return [(x + dx, y + dy) for dx in range(-radius, radius + 1) for dy in range(-radius, radius + 1)
            if w.floor.walkable(x + dx, y + dy) and not w.floor.is_safe(x + dx, y + dy)
            and (x + dx, y + dy) not in taken]


# --- Pet ---------------------------------------------------------------------

def test_pet_starts_next_to_player_and_follows_floors():
    w = World(seed=1, pet=("dog", "Rex"))
    assert w.pet.name == "Rex" and cheb(w.pet, w.player) == 1
    w.new_floor(2)
    assert cheb(w.pet, w.player) == 1


def test_default_pet_name():
    assert World(seed=1, pet=("cat", "")).pet.name == PETS["cat"]["default_name"]


def test_swap_places_with_pet():
    w = World(seed=2, pet=("dog", "Rex"))
    _clear(w)
    p, pet = w.player, w.pet
    old, target = (p.x, p.y), (pet.x, pet.y)
    assert w.move_player(pet.x - p.x, pet.y - p.y)
    assert (p.x, p.y) == target


def test_pet_attacks_adjacent_monster_and_earns_xp():
    w = World(seed=3, pet=("dog", "Rex"))
    _clear(w)
    pet = w.pet
    x, y = _free_tiles_near(w, pet.x, pet.y, 1)[0]
    m = spawn_monster("gnawer", x, y)
    m.hp = 1
    w.monsters.append(m)
    pet.attack = 100
    w.wait()
    assert m not in w.monsters and pet.kills == 1 and pet.xp > 0


def test_pet_command_cycles_modes():
    w = World(seed=3, pet=("cat", "Tom"))
    modes = [w.pet.mode]
    for _ in range(3):
        w.command_pet()
        modes.append(w.pet.mode)
    assert modes == ["follow", "attack", "stay", "follow"]


def test_cat_pounces_from_range():
    w = World(seed=4, pet=("cat", "Tom"))
    _clear(w)
    pet = w.pet
    spots = [s for s in _free_tiles_near(w, pet.x, pet.y, 3)
             if max(abs(s[0] - pet.x), abs(s[1] - pet.y)) == 3]
    m = spawn_monster("golem", *spots[0])
    w.monsters.append(m)
    w.visible = {(m.x, m.y)}
    from crawler.ai import take_pet_turn
    take_pet_turn(w)
    assert cheb(pet, m) == 1 and pet.cooldown == PETS["cat"]["cooldown"]


def test_dog_licks_wounds():
    w = World(seed=5, pet=("dog", "Rex"))
    _clear(w)
    w.player.hp = 5
    w.wait()
    assert w.player.hp > 6 and w.pet.cooldown > 0


def test_pet_downed_then_revived_in_safe_room():
    w = World(seed=6, pet=("dog", "Rex"))
    _clear(w)
    pet = w.pet
    x, y = _free_tiles_near(w, pet.x, pet.y, 1)[0]
    m = spawn_monster("stalker", x, y)
    m.attack, m.alerted = 100, True
    w.monsters.append(m)
    pet.hp = 1
    for _ in range(20):                          # hit chance caps at 95%
        if not pet.downed:
            w.monster_attack_pet(m)
    assert pet.downed and w.active_pet is None
    w.monsters.clear()
    assert not w.revive_pet()                    # not in a safe room
    w.player.x, w.player.y = w.floor.safe_room.centre
    before = w.timer
    assert w.revive_pet()
    assert not pet.downed and pet.hp == pet.max_hp
    assert before - w.timer == C.PET_REVIVE_TURNS


def test_monsters_never_stand_on_the_pet():
    w = World(seed=7, pet=("cat", "Tom"))
    w.player.max_hp = w.player.hp = 10_000
    rng = random.Random(7)
    for _ in range(1500):
        if w.state != "playing":
            break
        if w.on_stairs and not w.exit_sealed and rng.random() < 0.5:
            w.descend()
        else:
            w.move_player(*rng.choice(NEIGHBOURS_8))
        pet = w.active_pet
        if pet:
            assert all((m.x, m.y) != (pet.x, pet.y) for m in w.monsters)


# --- Classes and skills -------------------------------------------------------

def test_class_choice_offered_on_floor_three():
    w = World(seed=8)
    w.new_floor(CHOICE_FLOOR - 1)
    assert not w.pending_choice
    w.new_floor(CHOICE_FLOOR)
    assert w.pending_choice
    p = w.player
    hp, ac, hit = p.max_hp, p.ac, p.attack
    assert w.choose_class("elf", "analyst")             # DEX 10 -> 13, CON 10 -> 8, +1 to hit
    assert not w.pending_choice and p.ac == ac + 1 and p.max_hp == hp - p.level
    assert p.attack == hit + 1
    assert not w.choose_class("human", "brawler")        # only once


def test_skill_needs_a_class_and_respects_cooldown():
    w = World(seed=9)
    _clear(w)
    assert not w.use_skill()
    w.choose_class("human", "analyst")
    assert w.use_skill() and w.scout_turns > 0
    assert not w.use_skill()                              # recharging
    for _ in range(30):
        w.wait()
    assert w.skill_cooldown == 0 and w.scout_turns == 0


def test_haymaker_always_hits_double():
    w = World(seed=10)
    _clear(w)
    w.choose_class("human", "brawler")
    x, y = _free_tiles_near(w, w.player.x, w.player.y, 1)[0]
    m = spawn_monster("golem", x, y)
    m.ac = 100
    w.monsters.append(m)
    assert w.use_skill()
    assert m.hp < m.max_hp


def test_arc_bolt_hits_nearest_visible():
    w = World(seed=11)
    _clear(w)
    w.choose_class("elf", "arcanist")
    x, y = _free_tiles_near(w, w.player.x, w.player.y, 3)[0]
    m = spawn_monster("golem", x, y)
    w.monsters.append(m)
    w.visible = {(m.x, m.y)}
    assert w.use_skill()
    assert m.max_hp - m.hp == 6 + 2 * w.player.level + w.mod("int")


# --- Bosses and ranged monsters ---------------------------------------------

@pytest.mark.parametrize("depth", range(1, C.NUM_FLOORS + 1))
def test_one_boss_per_floor_by_the_furthest_stairs(depth):
    w = World(seed=12)
    w.new_floor(depth)
    bosses = [m for m in w.monsters if m.tier == "headliner"]
    assert len(bosses) == 1 and bosses[0].name == BOSSES[depth]["name"]
    n_open, n_feat = acts_per_floor(depth)
    tiers = [m.tier for m in w.monsters if m.boss]
    assert tiers.count("opening") <= n_open and tiers.count("featured") <= n_feat
    assert tiers.count("opening") + tiers.count("featured") >= 1
    sx, sy = w.floor.stairs[-1]
    room = next(r for r in w.floor.rooms if r.contains(sx, sy))
    assert room.contains(bosses[0].x, bosses[0].y)


def test_boss_kill_awards_box_achievement_and_viewers():
    w = World(seed=13)
    boss = next(m for m in w.monsters if m.tier == "headliner")
    viewers = w.viewers
    boss.hp = 0
    w._after_hit(boss, "melee")
    assert BOSSES[1]["box"] in w.boxes and "headliner_1" in w.achievements.unlocked
    assert any(BOSSES[1]["name"] in r for r in w.box_reasons[BOSSES[1]["box"]])
    assert w.viewers >= viewers + 150


def test_final_boss_phase_two_calls_for_help():
    w = World(seed=14)
    w.new_floor(C.NUM_FLOORS)
    boss = next(m for m in w.monsters if m.tier == "headliner")
    count, bonus = len(w.monsters), boss.dmg_bonus
    boss.hp = boss.max_hp // 2
    w._after_hit(boss, "melee")
    assert boss.phase == 2 and boss.dmg_bonus > bonus and boss.ranged
    assert len(w.monsters) > count
    w._after_hit(boss, "melee")                          # no second trigger
    assert boss.phase == 2


def test_ranged_monster_shoots_from_distance():
    w = World(seed=15)
    _clear(w)
    p = w.player
    spot = next(s for s in _free_tiles_near(w, p.x, p.y, 4)
                if max(abs(s[0] - p.x), abs(s[1] - p.y)) >= 3)
    m = spawn_monster("cultist", *spot)
    m.attack = 100
    w.monsters.append(m)
    hp = p.hp
    for _ in range(10):
        w.visible = {(m.x, m.y)} | w.visible
        from crawler.ai import take_monster_turns
        take_monster_turns(w)
    assert p.hp < hp


# --- Crafting -----------------------------------------------------------------

def test_crafting_in_safe_room_only_and_costs_time():
    w = World(seed=16)
    _clear(w)
    recipe = RECIPES[0]
    w.inventory = list(recipe["needs"])
    assert not w.craft(0)
    w.player.x, w.player.y = w.floor.safe_room.centre
    before = w.timer
    assert w.craft(0)
    assert w.inventory == [recipe["makes"]] and before - w.timer == CRAFT_TURNS
    assert not w.craft(0)                                # parts used up


def test_recipes_reference_real_items():
    assert len(RECIPES) == 4
    for r in RECIPES:
        assert r["makes"] in ITEMS and all(k in ITEMS for k in r["needs"])


# --- Save / load --------------------------------------------------------------

def _play(w, rng, n):
    for _ in range(n):
        if w.state != "playing":
            return
        w.move_player(*rng.choice(NEIGHBOURS_8))


def test_save_round_trip_and_identical_future(tmp_path):
    w = World(seed=17, pet=("cat", "Tom"))
    w.player.max_hp = w.player.hp = 1000
    _play(w, random.Random(1), 150)
    w.inventory = ["tonic", "sock"]
    w.boxes = ["gold"]
    w.choose_class("elf", "brawler")
    path = tmp_path / "slot.json"
    save.save(w, path)
    v = save.load(path)
    assert save.to_dict(v) == save.to_dict(w)

    # Same inputs after loading give the same game.
    _play(w, random.Random(2), 200)
    _play(v, random.Random(2), 200)
    assert save.to_dict(v) == save.to_dict(w)


def test_load_rejects_wrong_version(tmp_path):
    w = World(seed=18)
    d = save.to_dict(w)
    d["version"] = 99
    with pytest.raises(ValueError):
        save.from_dict(d)


# --- Budgie and mouse --------------------------------------------------------

def test_four_companions_each_with_quips():
    from crawler.entities import PET_QUIPS
    assert set(PETS) == {"cat", "dog", "budgie", "mouse"}
    for species in PETS:
        quips = PET_QUIPS[species]
        assert all(quips[k] for k in ("kill", "ability", "level_up", "downed"))
        w = World(seed=1, pet=(species, ""))
        assert w.pet.name == PETS[species]["default_name"]


def test_budgie_squawk_stuns_nearby_monsters():
    from crawler.ai import take_monster_turns, take_pet_turn
    w = World(seed=20, pet=("budgie", "Pickles"))
    _clear(w)
    p = w.player
    spots = _free_tiles_near(w, p.x, p.y, 2)[:2]
    ms = [spawn_monster("golem", x, y) for x, y in spots]
    w.monsters += ms
    w.visible = {(m.x, m.y) for m in ms} | w.visible
    take_pet_turn(w)
    assert all(m.stunned == 2 for m in ms) and w.pet.cooldown == PETS["budgie"]["cooldown"]
    where = [(m.x, m.y) for m in ms]
    take_monster_turns(w)
    assert [(m.x, m.y) for m in ms] == where and all(m.stunned == 1 for m in ms)


def test_mouse_dirty_trick_on_wounded_monster():
    from crawler.ai import take_pet_turn
    w = World(seed=21, pet=("mouse", "Skritch"))
    _clear(w)
    pet = w.pet
    x, y = _free_tiles_near(w, pet.x, pet.y, 1)[0]
    m = spawn_monster("golem", x, y)
    m.hp = m.max_hp // 2
    w.monsters.append(m)
    pet.attack = 100
    for _ in range(5):                       # 95% hit cap
        if pet.cooldown:
            break
        take_pet_turn(w)
    assert pet.cooldown == PETS["mouse"]["cooldown"]


def test_mouse_runs_away_when_hurt():
    from crawler.ai import take_pet_turn
    w = World(seed=22, pet=("mouse", "Skritch"))
    _clear(w)
    pet, p = w.pet, w.player
    far = max(_free_tiles_near(w, p.x, p.y, 4), key=lambda s: max(abs(s[0] - p.x), abs(s[1] - p.y)))
    pet.x, pet.y = far
    x, y = _free_tiles_near(w, pet.x, pet.y, 1)[0]
    m = spawn_monster("gnawer", x, y)
    w.monsters.append(m)
    pet.hp = 2
    before = cheb(pet, p)
    take_pet_turn(w)
    assert cheb(pet, p) < before and m.hp == m.max_hp
    assert any("Skritch:" in t for t, _ in w.messages.recent(5))


def test_boss_names_read_naturally():
    w = World(seed=23)
    boss = next(m for m in w.monsters if m.tier == "headliner")
    w.player.hp = 1
    w.player.ac = -100
    for _ in range(40):
        if w.state == "dead":
            break
        w.monster_attack(boss)
    assert w.death_cause == f"Killed by {boss.name} on floor 1"
    text = " ".join(t for t, _ in w.messages.recent(50))
    assert "The The" not in text and "a The" not in text
    m = spawn_monster("goblin", 0, 0)
    assert (m.the, m.The, m.a) == ("the Knockoff Goblin", "The Knockoff Goblin", "a Knockoff Goblin")


def test_following_pet_joins_the_players_fight():
    w = World(seed=24, pet=("dog", "Rex"))
    _clear(w)
    p, pet = w.player, w.pet
    # A monster next to the player but not next to the pet.
    spot = next(s for s in _free_tiles_near(w, p.x, p.y, 1)
                if max(abs(s[0] - pet.x), abs(s[1] - pet.y)) >= 2)
    m = spawn_monster("golem", *spot)
    m.stunned = 99                                      # keep it still
    w.monsters.append(m)
    w.visible = w.visible | {spot}
    from crawler.ai import take_pet_turn
    for _ in range(4):
        take_pet_turn(w)
    assert cheb(pet, m) == 1

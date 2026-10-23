"""Monster and pet behaviour.

A monster becomes alerted when it is in the player's field of view and gives
up after MONSTER_LOSE_TRACK turns out of sight. Alerted monsters step down a
shared distance map towards the player; idle ones occasionally wander.
Ranged monsters shoot when they have the player in sight at range.
Monsters never enter safe-room tiles and never attack into them.
"""
from . import config as C
from .dungeon import NEIGHBOURS_8
from .entities import PETS

CHASE_RADIUS = 25
PET_LEASH = 2                   # a following pet stays within this many tiles
POUNCE_RANGE = 3


def cheb(a, b):
    return max(abs(a.x - b.x), abs(a.y - b.y))


def _free(world, x, y, occupied, allow_safe=False):
    floor = world.floor
    return (floor.walkable(x, y) and (allow_safe or not floor.is_safe(x, y))
            and (x, y) not in occupied and (x, y) != (world.player.x, world.player.y))


def _step_down(world, ent, dist, occupied, allow_safe=False):
    """The free neighbouring tile with the lowest distance, or None."""
    w = world.floor.width
    best, step = dist[ent.y * w + ent.x], None
    if best == -1:
        return None
    for dx, dy in NEIGHBOURS_8:
        nx, ny = ent.x + dx, ent.y + dy
        if not _free(world, nx, ny, occupied, allow_safe):
            continue
        d = dist[ny * w + nx]
        if d != -1 and d < best:
            best, step = d, (nx, ny)
    return step


def take_monster_turns(world):
    player, floor, rng = world.player, world.floor, world.rng
    dist = floor.distance_map(player.x, player.y, max_dist=CHASE_RADIUS, avoid_safe=True)
    occupied = {(m.x, m.y) for m in world.monsters}
    pet = world.active_pet
    if pet:
        occupied.add((pet.x, pet.y))
    player_safe = floor.is_safe(player.x, player.y)

    for m in list(world.monsters):          # bosses can summon help mid-loop
        if world.state != "playing":
            return
        seen = (m.x, m.y) in world.visible
        if seen:
            m.alerted, m.unseen_turns = True, 0
        elif m.alerted:
            m.unseen_turns += 1
            if m.unseen_turns > C.MONSTER_LOSE_TRACK:
                m.alerted = False

        step = None
        if m.alerted:
            gap = cheb(m, player)
            if gap == 1 and not player_safe:
                world.monster_attack(m)
                continue
            pet = world.active_pet
            if pet and cheb(m, pet) == 1 and not floor.is_safe(pet.x, pet.y):
                world.monster_attack_pet(m)
                continue
            if (m.ranged and seen and 2 <= gap <= m.ranged and not player_safe
                    and rng.random() < C.RANGED_ATTACK_CHANCE):
                world.monster_attack(m, ranged=True)
                continue
            step = _step_down(world, m, dist, occupied)
        elif not m.boss and rng.random() < C.MONSTER_WANDER_CHANCE:
            dx, dy = rng.choice(NEIGHBOURS_8)
            if _free(world, m.x + dx, m.y + dy, occupied):
                step = (m.x + dx, m.y + dy)

        if step:
            occupied.discard((m.x, m.y))
            m.x, m.y = step
            occupied.add(step)


def take_pet_turn(world):
    """The companion's turn: ability if ready, then fight, then move by mode."""
    pet = world.active_pet
    if not pet or world.state != "playing":
        return
    floor, player = world.floor, world.player
    spec = PETS[pet.species]
    if pet.cooldown:
        pet.cooldown -= 1
    pet_safe = floor.is_safe(pet.x, pet.y)
    occupied = {(m.x, m.y) for m in world.monsters}

    if not pet.cooldown:
        if (spec["ability"] == "lick" and player.hp < player.max_hp * 0.5
                and cheb(pet, player) <= 1):
            world.pet_lick()
            return
        if spec["ability"] == "pounce" and pet.mode != "stay" and not pet_safe:
            targets = [m for m in world.monsters if (m.x, m.y) in world.visible
                       and 2 <= cheb(pet, m) <= POUNCE_RANGE]
            for t in sorted(targets, key=lambda m: m.hp):
                spots = [(t.x + dx, t.y + dy) for dx, dy in NEIGHBOURS_8
                         if _free(world, t.x + dx, t.y + dy, occupied)]
                if spots:
                    pet.x, pet.y = min(spots, key=lambda s: max(abs(s[0] - pet.x),
                                                                abs(s[1] - pet.y)))
                    world.pet_pounce(t)
                    return

    if not pet_safe:
        adjacent = [m for m in world.monsters if cheb(pet, m) == 1]
        if adjacent:
            world.pet_attack(min(adjacent, key=lambda m: m.hp))
            return

    target = None
    if pet.mode == "attack":
        seen = [m for m in world.monsters if (m.x, m.y) in world.visible]
        if seen:
            target = min(seen, key=lambda m: cheb(pet, m))
    if target is None and pet.mode != "stay" and cheb(pet, player) > PET_LEASH:
        target = player
    if target is None:
        return
    dist = floor.distance_map(target.x, target.y, max_dist=40)
    step = _step_down(world, pet, dist, occupied, allow_safe=True)
    if step:
        pet.x, pet.y = step

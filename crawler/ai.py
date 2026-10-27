"""Monster and pet behaviour.

A monster becomes alerted when it is in the player's field of view and gives
up after MONSTER_LOSE_TRACK turns out of sight. Alerted monsters step down a
shared distance map towards the player; idle ones occasionally wander.
Ranged monsters shoot when they have the player in sight at range.
Monsters never enter safe-room tiles and never attack into them.

Outside combat every monster acts once per turn. In combat (World.combat) the
monsters and the pet in the fight act in initiative order instead, each able to
step and then attack (take_combat_turn, take_pet_turn(combat=True)); a step out of a
hostile's reach first gives it an attack of opportunity (World.opportunity_attacks).
A pounce is a leap, not a step, and doesn't provoke.
"""
from . import config as C
from .dungeon import NEIGHBOURS_8
from .entities import PETS

CHASE_RADIUS = 25
PET_LEASH = 2                   # a following pet stays this close and defends you within it
POUNCE_RANGE = 3
SQUAWK_RANGE = 3
MOUSE_FLEE_FRAC = 0.3           # the mouse runs back to you below this much HP


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


def chase_map(world):
    """Distance map towards the player, cached until the player moves or the floor changes."""
    player = world.player
    key = (world.floor, player.x, player.y)
    cache = getattr(world, "_chase_cache", None)
    if cache is None or cache[0][0] is not key[0] or cache[0][1:] != key[1:]:
        cache = world._chase_cache = (key, world.floor.distance_map(
            player.x, player.y, max_dist=CHASE_RADIUS, avoid_safe=True))
    return cache[1]


def _notice(world, m):
    """Update a monster's alert from what it can see; returns True if it sees you."""
    seen = (m.x, m.y) in world.visible and cheb(m, world.player) <= world.notice_range()
    if seen:
        m.alerted, m.unseen_turns = True, 0
    elif m.alerted:
        m.unseen_turns += 1
        if m.unseen_turns > C.MONSTER_LOSE_TRACK:
            m.alerted = False
    return seen


def _melee(world, m):
    """Attack the player, else the pet, if adjacent and outside the safe room."""
    floor, player = world.floor, world.player
    if cheb(m, player) == 1 and not floor.is_safe(player.x, player.y):
        world.monster_attack(m)
        return True
    pet = world.active_pet
    if pet and cheb(m, pet) == 1 and not floor.is_safe(pet.x, pet.y):
        world.monster_attack_pet(m)
        return True
    return False


def _shoot(world, m, seen):
    player = world.player
    if (m.ranged and seen and 2 <= cheb(m, player) <= m.ranged
            and not world.floor.is_safe(player.x, player.y)
            and world.rng.random() < C.RANGED_ATTACK_CHANCE):
        world.monster_attack(m, ranged=True)
        return True
    return False


def _occupied(world):
    occupied = {(m.x, m.y) for m in world.monsters}
    pet = world.active_pet
    if pet:
        occupied.add((pet.x, pet.y))
    return occupied


def take_monster_turns(world):
    """Every monster outside combat acts once. A monster that becomes alerted joins (or
    starts) combat instead, and from then on acts in initiative order."""
    rng = world.rng
    dist = chase_map(world)
    occupied = _occupied(world)

    for m in list(world.monsters):          # bosses can summon help mid-loop
        if world.state != "playing":
            return
        if (world.combat and m in world.combat) or m in world._acted:
            continue                        # combatants act in initiative order, once a round
        if m not in world.monsters:
            continue                        # killed by a riposte earlier in the loop
        if m.stunned:
            m.stunned -= 1
            continue
        seen = _notice(world, m)
        if m.alerted and world.join_combat(m):
            continue                        # rolling initiative takes its turn

        step = None
        if m.alerted:
            if _melee(world, m) or _shoot(world, m, seen):
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


def take_combat_turn(world, m):
    """A monster's turn in combat: attack if adjacent, else shoot or step towards you and
    then attack if the step ends adjacent (a move plus an action)."""
    if m.stunned:
        m.stunned -= 1
        return
    seen = _notice(world, m)
    if not m.alerted:
        world.leave_combat(m)               # lost track of you
        return
    if _melee(world, m) or _shoot(world, m, seen):
        return
    step = _step_down(world, m, chase_map(world), _occupied(world))
    if step and world.opportunity_attacks(m, *step):        # leaving reach provokes
        m.x, m.y = step
        _melee(world, m)


def take_pet_turn(world, combat=False):
    """The companion's turn: ability if ready, then fight, then move by mode. In combat a
    plain step may be followed by an attack if it ends next to a monster."""
    pet = world.active_pet
    if not pet or world.state != "playing":
        return
    floor, player = world.floor, world.player
    spec = PETS[pet.species]
    if pet.cooldown:
        pet.cooldown -= 1
    pet_safe = floor.is_safe(pet.x, pet.y)
    occupied = {(m.x, m.y) for m in world.monsters}

    if spec["ability"] == "dirty_trick" and pet.hp < pet.max_hp * MOUSE_FLEE_FRAC:
        # Cowardice: run back to the player and don't pick fights.
        if cheb(pet, player) > 1:
            dist = floor.distance_map(player.x, player.y, max_dist=40)
            step = _step_down(world, pet, dist, occupied, allow_safe=True)
            if step and (not combat or world.opportunity_attacks(pet, *step)):
                pet.x, pet.y = step
                world.pet_flees()
        return

    if not pet.cooldown:
        if spec["ability"] == "squawk" and not pet_safe:
            near = [m for m in world.monsters if (m.x, m.y) in world.visible
                    and cheb(m, player) <= SQUAWK_RANGE and not m.stunned]
            if len(near) >= 2 or any(cheb(m, player) == 1 for m in near):
                world.pet_squawk(near)
                return
        if spec["ability"] == "dirty_trick" and not pet_safe:
            wounded = [m for m in world.monsters if cheb(pet, m) == 1 and m.hp <= m.max_hp * 0.6]
            if wounded:
                world.pet_dirty_trick(min(wounded, key=lambda m: m.hp))
                return
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
    elif pet.mode == "follow":
        # Help with whatever is fighting the player.
        threats = [m for m in world.monsters if (m.x, m.y) in world.visible
                   and cheb(m, player) <= PET_LEASH and not floor.is_safe(m.x, m.y)]
        if threats:
            target = min(threats, key=lambda m: cheb(pet, m))
    if target is None and pet.mode != "stay" and cheb(pet, player) > PET_LEASH:
        target = player
    if target is None:
        return
    dist = floor.distance_map(target.x, target.y, max_dist=40)
    step = _step_down(world, pet, dist, occupied, allow_safe=True)
    if step and (not combat or world.opportunity_attacks(pet, *step)):
        pet.x, pet.y = step
        if combat and not floor.is_safe(pet.x, pet.y):
            adjacent = [m for m in world.monsters if cheb(pet, m) == 1]
            if adjacent:
                world.pet_attack(min(adjacent, key=lambda m: m.hp))

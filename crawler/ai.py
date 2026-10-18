"""Monster behaviour.

A monster becomes alerted when it is in the player's field of view and gives
up after MONSTER_LOSE_TRACK turns out of sight. Alerted monsters step down a
shared distance map towards the player; idle ones occasionally wander.
Monsters never enter safe-room tiles and never attack into them.
"""
from . import config as C
from .dungeon import NEIGHBOURS_8

CHASE_RADIUS = 25


def _free(world, x, y, occupied):
    floor = world.floor
    return (floor.walkable(x, y) and not floor.is_safe(x, y)
            and (x, y) not in occupied and (x, y) != (world.player.x, world.player.y))


def take_monster_turns(world):
    player, floor, rng = world.player, world.floor, world.rng
    w = floor.width
    dist = floor.distance_map(player.x, player.y, max_dist=CHASE_RADIUS, avoid_safe=True)
    occupied = {(m.x, m.y) for m in world.monsters}
    player_safe = floor.is_safe(player.x, player.y)

    for m in world.monsters:
        if not player.alive:
            return
        if (m.x, m.y) in world.visible:
            m.alerted, m.unseen_turns = True, 0
        elif m.alerted:
            m.unseen_turns += 1
            if m.unseen_turns > C.MONSTER_LOSE_TRACK:
                m.alerted = False

        step = None
        if m.alerted:
            if max(abs(m.x - player.x), abs(m.y - player.y)) == 1 and not player_safe:
                world.monster_attack(m)
                continue
            best = dist[m.y * w + m.x]
            if best != -1:
                for dx, dy in NEIGHBOURS_8:
                    nx, ny = m.x + dx, m.y + dy
                    if not _free(world, nx, ny, occupied):
                        continue
                    d = dist[ny * w + nx]
                    if d != -1 and d < best:
                        best, step = d, (nx, ny)
        elif rng.random() < C.MONSTER_WANDER_CHANCE:
            dx, dy = rng.choice(NEIGHBOURS_8)
            if _free(world, m.x + dx, m.y + dy, occupied):
                step = (m.x + dx, m.y + dy)

        if step:
            occupied.discard((m.x, m.y))
            m.x, m.y = step
            occupied.add(step)

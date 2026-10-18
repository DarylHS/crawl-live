"""Balance probe: a bot explores and fights while time allows, rests in the
safe room when hurt, then heads for the nearest stairs. Grows into
analysis/bot.py in Phase 5.

Usage: python analysis/balance_probe.py [runs]
"""
import sys
from collections import Counter
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from crawler.dungeon import NEIGHBOURS_8
from crawler.world import World


def cheb(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def step_towards(w, tx, ty):
    f, p = w.floor, w.player
    dist = f.distance_map(tx, ty)
    best, move = dist[p.y * f.width + p.x], None
    for dx, dy in NEIGHBOURS_8:
        nx, ny = p.x + dx, p.y + dy
        if f.walkable(nx, ny):
            d = dist[ny * f.width + nx]
            if d != -1 and d < best:
                best, move = d, (dx, dy)
    return move


def choose(w):
    p, f = w.player, w.floor
    pos = (p.x, p.y)
    adj = [m for m in w.monsters if cheb((m.x, m.y), pos) == 1]
    if adj and not w.in_safe_room:
        return ("move", (adj[0].x - p.x, adj[0].y - p.y))
    if w.on_stairs and (w.timer < w.timer_max * 0.4 or all(f.explored[r.centre[1]][r.centre[0]] for r in f.rooms)):
        return ("descend", None)
    hurt = p.hp < p.max_hp * 0.5
    if hurt and w.in_safe_room and w.timer > 120:
        return ("rest", None)
    target = None
    if hurt and w.timer > 200:
        target = f.safe_room.centre
    elif w.timer > w.timer_max * 0.4:
        seen = [m for m in w.monsters if (m.x, m.y) in w.visible]
        if seen:
            target = (seen[0].x, seen[0].y)
        else:
            rooms = [r.centre for r in f.rooms if not f.explored[r.centre[1]][r.centre[0]]]
            if rooms:
                target = min(rooms, key=lambda c: cheb(c, pos))
    if target is None:
        if w.on_stairs:
            return ("descend", None)
        target = min(f.stairs, key=lambda s: cheb(s, pos))
    mv = step_towards(w, *target)
    return ("move", mv) if mv else ("wait", None)


def play(seed):
    w = World(seed)
    while w.state == "playing":
        act, arg = choose(w)
        before = w.turn, w.depth
        if act == "move":
            ok = w.move_player(*arg)
        elif act == "descend":
            ok = w.descend()
        elif act == "rest":
            ok = w.rest()
        else:
            ok = w.wait()
        if not ok:
            w.wait()
    return w


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    outcome, levels = Counter(), Counter()
    for seed in range(n):
        w = play(seed)
        key = "victory" if w.state == "victory" else (
            f"floor {w.depth} " + ("collapse" if "collapsed" in w.death_cause else "killed"))
        outcome[key] += 1
        levels[w.depth] += w.player.level
    for k, v in sorted(outcome.items()):
        print(f"{k:22s} {v:4d} ({v / n:.0%})")

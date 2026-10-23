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
from crawler.items import ITEMS
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


def score(key):
    it = ITEMS[key]
    return it.get("power", 0) * 2 + it.get("accuracy", 0) + it.get("defence", 0) * 2 + it.get("evasion", 0)


def manage_items(w):
    """Free actions: wear the best gear, and open every box while in a safe room."""
    if w.in_safe_room:
        while w.boxes and w.open_box(w.boxes[0]):
            pass
    for slot in ("weapon", "armour"):
        cur = w.equipment[slot]
        best = max((k for k in w.inventory if ITEMS[k]["kind"] == slot), key=score, default=None)
        if best and (cur is None or score(best) > score(cur)):
            w.equip(w.inventory.index(best))


def worth_taking(w, xy):
    return len(w.inventory) < 16 and any(ITEMS[k]["kind"] != "junk" for k in w.floor_items[xy])


def best_of(w, kind):
    held = [i for i, k in enumerate(w.inventory) if ITEMS[k]["kind"] == kind]
    return held[0] if held else None


def choose(w):
    p, f = w.player, w.floor
    pos = (p.x, p.y)
    if pos in w.floor_items and worth_taking(w, pos):
        return ("pickup", None)
    adj_n = sum(1 for m in w.monsters if cheb((m.x, m.y), pos) == 1)
    if p.hp < p.max_hp * 0.45 and not w.in_safe_room:
        potion = best_of(w, "potion")
        if potion is not None:
            return ("use", potion)
    if adj_n >= 2 or any((m.x, m.y) in w.visible and m.key in ("golem", "brute") for m in w.monsters):
        bomb = best_of(w, "bomb")
        if bomb is not None and any(cheb((m.x, m.y), pos) <= 3 for m in w.monsters
                                    if (m.x, m.y) in w.visible):
            return ("use", bomb)
    adj = [m for m in w.monsters if cheb((m.x, m.y), pos) == 1]
    if adj and not w.in_safe_room:
        return ("move", (adj[0].x - p.x, adj[0].y - p.y))
    if w.on_stairs and (w.timer < w.timer_max * 0.4 or all(f.explored[r.centre[1]][r.centre[0]] for r in f.rooms)):
        return ("descend", None)
    hurt = p.hp < p.max_hp * 0.5
    loot = [xy for xy in w.floor_items if xy in w.visible and worth_taking(w, xy)]
    if loot and not hurt and w.timer > w.timer_max * 0.4:
        mv = step_towards(w, *min(loot, key=lambda c: cheb(c, pos)))
        if mv:
            return ("move", mv)
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
        manage_items(w)
        act, arg = choose(w)
        if act == "move":
            ok = w.move_player(*arg)
        elif act == "descend":
            ok = w.descend()
        elif act == "rest":
            ok = w.rest()
        elif act == "pickup":
            ok = w.pickup()
        elif act == "use":
            ok = w.use_item(arg)
        else:
            ok = w.wait()
        if not ok:
            w.wait()
    return w


if __name__ == "__main__":
    n = int(sys.argv[1]) if len(sys.argv) > 1 else 200
    outcome, levels, viewers, unlocked = Counter(), Counter(), [], Counter()
    for seed in range(n):
        w = play(seed)
        key = "victory" if w.state == "victory" else (
            f"floor {w.depth} " + ("collapse" if "collapsed" in w.death_cause else "killed"))
        outcome[key] += 1
        levels[w.depth] += w.player.level
        viewers.append(w.viewers)
        unlocked.update(w.achievements.unlocked.keys())
    for k, v in sorted(outcome.items()):
        print(f"{k:22s} {v:4d} ({v / n:.0%})")
    viewers.sort()
    print(f"viewers: median {viewers[n // 2]:,}, p90 {viewers[n * 9 // 10]:,}, max {viewers[-1]:,}")
    print("achievements:", ", ".join(f"{k} {v / n:.0%}" for k, v in sorted(unlocked.items())))

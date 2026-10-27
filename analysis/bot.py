"""Headless bot: plays Crawl Live! many times and logs every run for analysis.

The bot explores and fights while time allows, picks up and equips gear, sells
junk, keeps three potions from the shop, opens boxes in safe rooms, rests when
hurt, then heads for the nearest stairs (or the final boss once the exit is
sealed). Each run's companion, race and class rotate with the seed, and every
sponsor contract is accepted or declined by a coin flip, so the runs form a
randomised experiment on deals.

Usage:
  python analysis/bot.py --runs 500 --workers 4        # writes runs/bot_*.csv
  python analysis/bot.py --runs 100 --summary-only     # quick balance check
"""
import argparse
import random
import sys
import time
from collections import Counter
from multiprocessing import Pool
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from crawler.dice import average
from crawler.dungeon import NEIGHBOURS_8
from crawler.items import ITEMS
from crawler.character import BACKSTORIES, GENDERS
from crawler.classes import CLASSES as CLASS_TABLE, RACES as RACE_TABLE
from crawler.entities import PETS
from crawler.telemetry import RUNS_DIR, Telemetry, write_tables
from crawler.world import World

PET_ORDER = list(PETS)


def cheb(a, b):
    return max(abs(a[0] - b[0]), abs(a[1] - b[1]))


def step_towards(w, tx, ty):
    """One step downhill on a distance map from the target (cached until the target moves)."""
    f, p = w.floor, w.player
    cache = getattr(w, "_bot_route", None)
    if cache and cache[0] is f and cache[1] == (tx, ty):
        dist = cache[2]
    else:
        dist = f.distance_map(tx, ty)
        w._bot_route = (f, (tx, ty), dist)
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
    if it["kind"] == "weapon":
        return average(*it["dice"]) * 2 + it.get("hit", 0) + it.get("dmg", 0) * 2
    return it.get("ac", 0) * 2


# Attribute targets per class: the bot raises whichever attribute is furthest below its
# target, so each build leans into its class while keeping enough Constitution to live.
FIGHT_ATTR = {"duellist": "dex", "demolitionist": "dex"}
CLASS_ATTR = {"arcanist": "int", "alchemist": "int", "beastmaster": "cha", "hype_man": "cha",
              "quartermaster": "cha"}


def spend_points(w, cls):
    fight = FIGHT_ATTR.get(cls, "str")
    targets = {fight: 18, "con": 16, CLASS_ATTR.get(cls, "dex"): 14}
    while w.player.stat_points:
        gaps = {a: t - w.score(a) for a, t in targets.items()}
        attr = max(gaps, key=gaps.get) if max(gaps.values()) > 0 else fight
        if not w.spend_point(attr):
            break


def manage_items(w):
    """Free actions: wear the best gear; in safe rooms open boxes, sell junk, buy potions."""
    if w.in_safe_room:
        while w.boxes and w.open_box(w.boxes[0]):
            pass
        for i in reversed(range(len(w.inventory))):
            if ITEMS[w.inventory[i]]["kind"] == "junk":
                w.shop_sell(i)
        potions = sum(ITEMS[k]["kind"] == "potion" for k in w.inventory)
        for key in ("elixir", "brew", "tonic"):
            while potions < 3 and w.shop.stock[key].on_hand and w.gold >= w.buy_price(key) + 10:
                if not w.shop_buy(key):
                    break
                potions += 1
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
    if w.cls and not w.skill_cooldown and not w.in_safe_room:
        seen_near = [m for m in w.monsters if (m.x, m.y) in w.visible and cheb((m.x, m.y), pos) <= 6]
        kinds = [ITEMS[k]["kind"] for k in w.inventory]
        sk = w.skill
        pet_fighting = w.active_pet and any(cheb((m.x, m.y), (w.pet.x, w.pet.y)) == 1 for m in w.monsters)
        if (sk == "haymaker" and adj) or (sk in ("arc_bolt", "pocket_popper") and seen_near) \
                or (sk == "scout_report" and seen_near and not w.scout_turns) \
                or (sk == "field_brew" and "junk" in kinds and kinds.count("potion") < 4) \
                or (sk == "rile_up" and pet_fighting) \
                or (sk == "crowd_work" and seen_near and not w.hype_turns) \
                or (sk == "riposte" and adj and not w.riposte) \
                or (sk == "supply_drop" and kinds.count("potion") < 2 and w.gold >= 25):
            return ("skill", None)
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
    if w.in_safe_room and w.pet and w.pet.downed and w.timer > 150:
        return ("revive", None)
    target = None
    boss = next((m for m in w.monsters if m.boss), None)
    if hurt and w.timer > 200:
        target = f.safe_room.centre
    elif w.exit_sealed and boss:
        target = (boss.x, boss.y)
    elif w.timer > w.timer_max * 0.4:
        # Bosses are optional before the last floor: only take them on when healthy.
        seen = [m for m in w.monsters if (m.x, m.y) in w.visible
                and (not m.boss or p.hp > p.max_hp * 0.8)]
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


RACES = tuple(RACE_TABLE)
CLASSES = tuple(CLASS_TABLE)
STORIES = tuple(BACKSTORIES)


def run_config(seed):
    """Companion, backstory, gender, race and class for a seed.

    Each is drawn independently from a seeded RNG, so every combination turns up and
    no choice is tied to another by the rotation.
    """
    pick = random.Random(seed * 7919 + 13)
    return dict(pet=PET_ORDER[seed % len(PET_ORDER)], race=pick.choice(RACES),
                cls=pick.choice(CLASSES), backstory=pick.choice(STORIES),
                gender=pick.choice(list(GENDERS)))


def play(seed, pet=None, deals="random", telemetry=False):
    """Play one run. deals is "random" (coin flip per offer), "accept" or "decline"."""
    cfg = run_config(seed)
    pet = pet or cfg["pet"]
    w = World(seed, pet=(pet, "") if pet != "none" else None,
              hero=dict(name="Bot", gender=cfg["gender"], backstory=cfg["backstory"]))
    tel = Telemetry(w, source="bot", run_id=f"bot{seed:05d}", meta=dict(deals=deals)) \
        if telemetry else None
    coin = random.Random(seed ^ 0xB07)
    while w.state == "playing":
        if w.pending_choice:
            w.choose_class(cfg["race"], cfg["cls"])
        if w.pending_offer:
            take = coin.random() < 0.5 if deals == "random" else deals == "accept"
            w.accept_contract() if take else w.decline_contract()
        spend_points(w, cfg["cls"])
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
        elif act == "skill":
            ok = w.use_skill()
            if ok and w.remote_shop:
                for key in ("brew", "tonic"):
                    if w.shop.stock[key].on_hand and w.gold >= w.buy_price(key) and w.shop_buy(key):
                        break
                w.remote_shop = False
        elif act == "revive":
            ok = w.revive_pet()
        else:
            ok = w.wait()
        if not ok:
            w.wait()
    return w, (tel.tables() if tel else None)


def _worker(job):
    seed, pet, deals, telemetry = job
    w, tables = play(seed, pet, deals, telemetry)
    summary = dict(outcome="victory" if w.state == "victory" else
                   f"floor {w.depth} " + ("collapse" if "collapsed" in w.death_cause else "killed"),
                   pet=w.pet.species if w.pet else "none", cls=w.cls, race=w.race,
                   backstory=w.backstory, won=w.state == "victory",
                   viewers=w.viewers, gold=sum(f["gold"] for f in w.floor_stats),
                   boxes=len(w.box_log), achievements=list(w.achievements.unlocked),
                   skills=dict(w.training.levels))
    return summary, tables


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--runs", type=int, default=200)
    ap.add_argument("--start", type=int, default=0, help="first seed")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--pet", choices=PET_ORDER + ["none"], help="force one companion")
    ap.add_argument("--deals", choices=("random", "accept", "decline"), default="random")
    ap.add_argument("--out", default=str(RUNS_DIR))
    ap.add_argument("--summary-only", action="store_true", help="don't write CSVs")
    ap.add_argument("--no-events", action="store_true", help="skip the large events table")
    args = ap.parse_args()

    log = not args.summary_only
    jobs = [(s, args.pet, args.deals, log) for s in range(args.start, args.start + args.runs)]
    if log:
        for name in ("runs", "floors", "boxes", "shop", "practice", "events"):
            path = Path(args.out) / f"bot_{name}.csv"
            if path.exists() and args.start == 0:
                path.unlink()               # a fresh generation replaces the old data
    t0 = time.time()
    summaries = []
    with Pool(args.workers) as pool:
        # chunksize > 1 keeps workers busy; results arrive in seed order for reproducible CSVs.
        for summary, tables in pool.imap(_worker, jobs, chunksize=4):
            summaries.append(summary)
            if log:
                write_tables(tables, args.out, prefix="bot_",
                             skip=("events",) if args.no_events else ())
    n = len(summaries)
    print(f"{n} runs in {time.time() - t0:.0f}s with {args.workers} workers")
    for k, v in sorted(Counter(s["outcome"] for s in summaries).items()):
        print(f"  {k:22s} {v:5d} ({v / n:.0%})")
    for key in ("pet", "backstory", "race", "cls"):
        groups = Counter(s[key] for s in summaries if s[key])
        wins = Counter(s[key] for s in summaries if s[key] and s["won"])
        print(f"  win rate by {key}: " + ", ".join(f"{g} {wins[g] / c:.0%} of {c}"
                                                  for g, c in sorted(groups.items())))
    med = lambda xs: sorted(xs)[len(xs) // 2]
    print(f"  median viewers {med([s['viewers'] for s in summaries]):,}, gold "
          f"{med([s['gold'] for s in summaries])}, boxes {med([s['boxes'] for s in summaries])}")
    means = {k: sum(s["skills"][k] for s in summaries) / n for k in summaries[0]["skills"]}
    print("  mean practice level: " + ", ".join(f"{k} {v:.1f}" for k, v in
                                                sorted(means.items(), key=lambda kv: -kv[1])))


if __name__ == "__main__":
    main()

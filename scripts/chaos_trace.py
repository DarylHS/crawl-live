"""Chaos trace harness, Python side (port plan 6.4 extension, added at the S8 close-out).

A seeded random "chaos" player drives crawler.world.World through every player action the hunter and
walk policies never reach: class choice, class skills, bombs, crafting, shop buying and selling, box
opening, rerolls and trade-ups, pet commands and revival, resting, stairs with and without the
Headliner's key, contract offers and stat points. Every step it writes one JSON line holding most of the
World's state (position, stats, inventory, boxes, shop, practice, RNG digests, floor stats) plus the
events and messages emitted since the previous line. godot/tools/chaos.gd mirrors this file line for
line; scripts/chaos_diff.py compares the two.

    python scripts/chaos_trace.py --seeds 0-9 --steps 600 --out-dir DIR     # DIR/chaos_<seed>.jsonl
    python scripts/chaos_trace.py --seed 3 --steps 600 --out run.jsonl

Deterministic: the harness uses its own random.Random(seed ^ 0x5C8) and nothing else is random.

--mute LIST (default achievements,showrunner,funfacts): comma list of the subsystems to neutralise. While
the Godot side still has a P1 stand-in for a subsystem (Achievements: T1, FunFacts: T3) that subsystem must
be muted here and in chaos.gd; the real Showrunner (T2) is ported, so run with --mute achievements,funfacts.
Muting replaces the real Python Achievements._unlock, Showrunner._gain and _say, or FunFacts._say with
no-ops, and leaves out the events and messages they would add (achievement; viewers_gained, sponsor_gift and
showmanship practice_level; fun_fact). --mute none compares everything.
--mute-standins / --no-mute-standins are kept as aliases for the full list and none. Muting is the only deviation from an unmodified Python World."""
import argparse
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))
from crawler.world import World  # noqa: E402
from crawler.dungeon import NEIGHBOURS_8  # noqa: E402
from py_trace import mon_string, state_digest  # noqa: E402

RACES = ['human', 'elf', 'dwarf', 'hobgoblin', 'bog_troll', 'houseplant']
CLASSES = ['brawler', 'arcanist', 'analyst', 'alchemist', 'beastmaster', 'hype_man', 'demolitionist', 'quartermaster', 'duellist']
TIERS = ['bronze', 'silver', 'gold', 'platinum', 'legendary']
SHOPKEYS = ['tonic', 'brew', 'elixir', 'popper', 'fireworks', 'jersey', 'vest', 'pan', 'cleaver']
ATTRS = ['str', 'dex', 'con', 'int', 'cha']
PETS = ['none', 'cat', 'dog', 'budgie', 'mouse']
GENDERS = ['female', 'male', 'nonbinary']
BACKS = ['veteran', 'mixologist', 'dog_walker', 'comedian', 'parent', 'tradie', 'category_mgr', 'rideshare']
SUBSYSTEMS = ("achievements", "showrunner", "funfacts")
MUTED_EVENTS = {"achievements": {"achievement"}, "showrunner": {"viewers_gained", "sponsor_gift"}, "funfacts": {"fun_fact"}}
MUTED_FILES = {"achievements": "achievements.py", "showrunner": "showrunner.py", "funfacts": "funfacts.py"}


def parse_mute(text):
    """'achievements,funfacts' -> {'achievements', 'funfacts'}; 'none' -> empty; 'all' -> everything."""
    if text in ("", "none"):
        return set()
    names = set(SUBSYSTEMS) if text == "all" else set(text.split(","))
    bad = names - set(SUBSYSTEMS)
    if bad:
        raise SystemExit(f"unknown subsystem(s) to mute: {sorted(bad)}")
    return names


def run(seed, steps, path, mute=frozenset(SUBSYSTEMS)):
    """Play one chaos run and write its JSON Lines trace to `path`."""
    out = open(path, "w")
    SKIP = set().union(*(MUTED_EVENTS[m] for m in mute))
    files = tuple(MUTED_FILES[m] for m in mute)
    pet = PETS[seed % 5]
    hero = None if seed % 4 == 0 else {"name": "H", "gender": GENDERS[seed % 3], "backstory": BACKS[(seed // 3) % 8]}
    c = seed % 54
    race = RACES[c % 6]; cls = CLASSES[(c // 6) % 9]
    w = World(seed, pet=(pet, "") if pet != "none" else None, hero=hero)
    if "achievements" in mute:
        w.achievements._unlock = lambda *a, **k: None
    if "showrunner" in mute:
        w.showrunner._gain = lambda *a, **k: None
        w.showrunner._say = lambda *a, **k: None
    if "funfacts" in mute:
        w.funfacts._say = lambda *a, **k: None
    evs = []; msgs = []
    oemit = w.events.emit
    def emit(name, **d):
        if not (name in SKIP or ("showrunner" in mute and name == "practice_level" and d.get("skill") == "showmanship")):
            evs.append([name, json.loads(json.dumps(d))])
        oemit(name, **d)
    w.events.emit = emit
    oadd = w.messages.add
    def madd(text, colour=None):
        fn = sys._getframe(1).f_code.co_filename
        if not fn.endswith(files):
            msgs.append(text)
        if colour is None:
            oadd(text)
        else:
            oadd(text, colour)
    w.messages.add = madd
    p = w.player
    rng = random.Random(seed ^ 0x5C8)

    def cheb(ax, ay, bx, by): return max(abs(ax - bx), abs(ay - by))
    def free(x, y):
        return (w.floor.walkable(x, y) and not w.floor.is_safe(x, y) and w.monster_at(x, y) is None
                and w.pet_at(x, y) is None and not (x == p.x and y == p.y))
    def ring(cx, cy, d):
        for dy in range(-d, d + 1):
            for dx in range(-d, d + 1):
                if max(abs(dx), abs(dy)) == d and free(cx + dx, cy + dy):
                    return (cx + dx, cy + dy)
        return None
    def put(xy):
        if xy is not None:
            p.x, p.y = xy; w.update_fov()
    def to_safe():
        r = w.floor.safe_room
        for y in range(r.y, r.y + r.h):
            for x in range(r.x, r.x + r.w):
                if w.floor.walkable(x, y) and w.floor.is_safe(x, y) and w.monster_at(x, y) is None and w.pet_at(x, y) is None:
                    p.x, p.y = x, y; w.update_fov(); return
    def first_idx(keys):
        for i, k in enumerate(w.inventory):
            if k in keys: return i
        return -1

    def dump(n, tag, ok):
        pt = w.pet
        cb = w.combat
        rec = [n, tag, bool(ok) if ok is not None else None, w.turn, w.depth, w.state, w.timer, w.timer_max, w.stairs_open_turn,
               p.x, p.y, p.hp, p.max_hp, p.xp, p.level, p.kills, p.stat_points, dict(p.attrs), p.ac, p.attack, p.dmg_n, p.dmg_die, p.dmg_bonus, p.dr,
               w.gold, mon_string(w.monsters),
               ";".join(f"{x},{y}:{','.join(v)}" for (x, y), v in w.floor_items.items()),
               [pt.x, pt.y, pt.hp, pt.max_hp, pt.xp, pt.level, pt.kills, pt.cooldown, pt.downed, pt.mode, pt.enraged] if pt else None,
               [cb.round, [cb.budget[k] for k in sorted(cb.budget)], [r[1].name + ":" + str(r[2]) + ":" + str(r[3]) for r in cb.order]] if cb else None,
               w.riposte, w.has_key, w.exit_sealed, list(w.inventory), dict(w.equipment), list(w.boxes),
               {k: list(v) for k, v in w.box_reasons.items()}, json.loads(json.dumps(w.box_log)),
               list(w.last_reveal) if w.last_reveal else None, w.last_reason,
               w.race, w.cls, w.pending_choice, w.skill_cooldown, w.scout_turns, w.hype_turns, w.remote_shop,
               w.contract, w.pending_offer, w.death_cause,
               [w.shop.stock[k].on_hand for k in SHOPKEYS], [w.shop.bought[k] for k in SHOPKEYS], [w.shop.missed[k] for k in SHOPKEYS], len(w.shop.log),
               dict(w.training.levels), dict(w.training.xp), w.training.steps,
               json.loads(json.dumps(w.floor_stats)),
               state_digest(w.rng)[:16], state_digest(w.loot_rng)[:16], state_digest(w.shop.rng)[:16], state_digest(w.deal_rng)[:16],
               sum(map(sum, w.floor.explored)), evs[:], msgs[:]]
        out.write(json.dumps(rec, separators=(",", ":")) + "\n"); evs.clear(); msgs.clear()

    def act(n, tag, ok):
        dump(n, tag, ok)
        return ok

    # --- setup
    p.level = 6 + (seed % 7) * 2; w.refresh_stats(); p.hp = p.max_hp
    for k in ["popper", "fireworks", "popper", "tonic", "brew", "sock", "mug", "remote", "trophy", "pan", "jersey"]:
        if len(w.inventory) < 16:
            w.inventory.append(k)
    w.gold += 300
    for i, t in enumerate(["bronze", "bronze", "bronze", "bronze", "silver", "silver", "silver", "gold"]):
        w.add_box(t, "r%d" % i)
    if seed % 5 == 0:
        for k, v in [("tinkering", 8), ("power_napping", 5), ("first_aid", 5), ("lobbing", 5), ("haggling", 5), ("gambling", 5)]:
            w.training.levels[k] = v
    if seed % 3 != 0:
        if first_idx(["jersey"]) >= 0:
            act(-1, "equip", w.use_item(first_idx(["jersey"])))
        act(-1, "choose_class", w.choose_class(race, cls))
    dump(-1, "setup", None)

    def safe_block(n):
        to_safe(); dump(n, "tp_safe", None)
        act(n, "rest", w.rest())
        act(n, "craft", w.craft(rng.randrange(4)))
        act(n, "bomb_safe", w.use_item(first_idx(["popper", "fireworks"])) if first_idx(["popper", "fireworks"]) >= 0 else None)
        act(n, "skill_safe", w.use_skill())
        act(n, "buy", w.shop_buy(SHOPKEYS[rng.randrange(9)]))
        act(n, "sell", w.shop_sell(rng.randrange(max(1, len(w.inventory)))))
        act(n, "revive", w.revive_pet())
        act(n, "open", w.open_box(w.boxes[rng.randrange(len(w.boxes))]) if w.boxes else None)
        if rng.random() < 0.6:
            act(n, "reroll", w.reroll())
        act(n, "trade", w.trade_up(TIERS[rng.randrange(5)]))
        act(n, "potion_safe", w.use_item(first_idx(["tonic", "brew", "elixir"])) if first_idx(["tonic", "brew", "elixir"]) >= 0 else None)

    def stairs_block(n):
        s = w.floor.stairs[rng.randrange(len(w.floor.stairs))]
        if w.monster_at(s[0], s[1]) is None and w.pet_at(s[0], s[1]) is None:
            p.x, p.y = s[0], s[1]; w.update_fov()
        if rng.random() < 0.75:
            w.has_key = True
        dump(n, "tp_stairs", None)
        ok = act(n, "descend", w.descend())
        if not ok:
            act(n, "wait", w.wait())

    for n in range(steps):
        if w.state != "playing":
            break
        if w.pending_choice:
            act(n, "choose_class", w.choose_class(race, cls))
        if w.pending_offer:
            if rng.random() < 0.5:
                act(n, "accept", w.accept_contract())
            else:
                act(n, "decline", w.decline_contract())
        if p.stat_points > 0 and rng.random() < 0.3:
            act(n, "spend", w.spend_point(ATTRS[rng.randrange(5)]))
        if n % 20 == 0:
            kind = (n // 20) % 10
            if kind in (0, 6):
                safe_block(n)
            elif kind in (2, 7):
                stairs_block(n)
            elif kind in (1, 9):
                if w.monsters:
                    m = w.monsters[rng.randrange(len(w.monsters))]
                    put(ring(m.x, m.y, 1)); dump(n, "tp_mon", None)
                    if kind == 9:
                        act(n, "skill", w.use_skill())
            elif kind == 3:
                for k in ["fireworks", "popper", "tonic", "elixir", "sock", "mug", "trophy", "remote", "cleaver", "vest"]:
                    if len(w.inventory) < 16 and rng.random() < 0.5:
                        w.inventory.append(k)
                w.add_box(TIERS[rng.randrange(3)], "grant%d" % n)
                if seed % 2 == 1 and (n // 200) % 2 == 1:
                    w.gold = 0
                else:
                    w.gold += 100
                dump(n, "grant", None)
            elif kind == 4:
                if w.monsters:
                    m = w.monsters[rng.randrange(len(w.monsters))]
                    put(ring(m.x, m.y, 2 + rng.randrange(2)))
                    if rng.random() < 0.5:
                        for o in w.monsters:
                            if cheb(o.x, o.y, m.x, m.y) <= 2:
                                o.hp = min(o.hp, 2)
                    dump(n, "tp_bomb", None)
                    i = first_idx(["fireworks", "popper"])
                    act(n, "bomb", w.use_item(i) if i >= 0 else None)
                    act(n, "skill", w.use_skill())
            elif kind == 5:
                tgt = None
                for m in w.monsters:
                    if m.boss or m.tier:
                        tgt = m; break
                if tgt is not None:
                    put(ring(tgt.x, tgt.y, 1)); dump(n, "tp_boss", None)
            elif kind == 8:
                p.hp = max(1, p.max_hp // 2)
                if w.pet is not None and not w.pet.downed:
                    w.pet.hp = 1
                dump(n, "hurt", None)
        if w.state != "playing":
            break
        if seed % 4 != 3 and p.hp < p.max_hp // 4:
            p.hp = p.max_hp // 2
        a = rng.randrange(24)
        if a <= 1 or (a <= 7 and not any(cheb(m.x, m.y, p.x, p.y) == 1 for m in w.monsters)):
            d = NEIGHBOURS_8[rng.randrange(8)]
            tag, ok = "move", w.move_player(d[0], d[1])
        elif a <= 7:
            m = next(m for m in w.monsters if cheb(m.x, m.y, p.x, p.y) == 1)
            tag, ok = "attack", w.move_player(m.x - p.x, m.y - p.y)
        elif a == 8:
            tag, ok = "wait", w.wait()
        elif a == 9:
            tag, ok = "pickup", w.pickup()
        elif a == 10:
            tag, ok = "drop", w.drop(rng.randrange(max(1, len(w.inventory))))
        elif a <= 12:
            tag, ok = "use", w.use_item(rng.randrange(max(1, len(w.inventory))))
        elif a == 13:
            tag, ok = "unequip", w.unequip(["weapon", "armour"][rng.randrange(2)])
        elif a <= 15:
            tag, ok = "skill", w.use_skill()
        elif a == 16:
            tag, ok = "rest", w.rest()
        elif a == 17:
            tag, ok = "craft", w.craft(rng.randrange(4))
        elif a == 18:
            tag, ok = "buy", w.shop_buy(SHOPKEYS[rng.randrange(9)])
        elif a == 19:
            tag, ok = "sell", w.shop_sell(rng.randrange(max(1, len(w.inventory))))
        elif a == 20:
            tag, ok = "command", w.command_pet()
        elif a == 21:
            tag, ok = "revive", w.revive_pet()
        elif a == 22:
            r = rng.randrange(3)
            if r == 0:
                tag, ok = "open", w.open_box(TIERS[rng.randrange(5)])
            elif r == 1:
                tag, ok = "reroll", w.reroll()
            else:
                tag, ok = "trade", w.trade_up(TIERS[rng.randrange(5)])
        else:
            tag, ok = "descend", w.descend()
        dump(n, tag, ok)
        if not ok and w.state == "playing":
            act(n, "wait", w.wait())
    dump(steps, "end", None)
    out.close()



def seeds_arg(text):
    lo, _, hi = text.partition("-")
    return list(range(int(lo), int(hi or lo) + 1))


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--seed", type=int, help="a single seed (with --out)")
    ap.add_argument("--seeds", help="A-B or N (with --out-dir)")
    ap.add_argument("--steps", type=int, default=600)
    ap.add_argument("--out", help="output file for --seed")
    ap.add_argument("--out-dir", help="directory for chaos_<seed>.jsonl files")
    ap.add_argument("--mute", default="achievements,showrunner,funfacts",
                    help="comma list of achievements,showrunner,funfacts to neutralise (or all, none)")
    ap.add_argument("--mute-standins", action=argparse.BooleanOptionalAction, default=None,
                    help="alias: --mute-standins is --mute all, --no-mute-standins is --mute none")
    a = ap.parse_args()
    mute = parse_mute(a.mute if a.mute_standins is None else ("all" if a.mute_standins else "none"))
    if a.seed is not None and a.out:
        run(a.seed, a.steps, a.out, mute)
    elif a.seeds and a.out_dir:
        Path(a.out_dir).mkdir(parents=True, exist_ok=True)
        for s in seeds_arg(a.seeds):
            run(s, a.steps, f"{a.out_dir}/chaos_{s}.jsonl", mute)
    else:
        ap.error("give --seed N --out FILE, or --seeds A-B --out-dir DIR")


if __name__ == "__main__":
    main()

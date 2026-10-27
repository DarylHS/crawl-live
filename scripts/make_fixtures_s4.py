#!/usr/bin/env python3
"""Fixtures from real Python for the Godot S4 tests (encounter, bosses, items, loot, crafting,
contracts, shop).

Usage: make_fixtures_s4.py out.json

Sibling of make_fixtures_s2.py (same encoding, see make_fixtures.py). For seeds 0-199 one scripted
sequence of steps runs against two CountingRandom streams: loot (seed ^ 0x100F; box rolls and floor
loot draws) and shop (seed ^ 0x5A0F; Poisson demand). Step kinds:

  box          roll_box for every tier (each tier three times first, then random tiers)
  floor_table  floor_loot_table(depth), depths 0-8
  floor_draw   n weighted choices from floor_loot_table(depth), and the (tonic, brew, elixir) 6/3/1 draw
  odds         odds, box_stats, next_tier, reroll_fee, tier name
  item         value, glyph, describe for an item key
  craft        can_craft for each recipe against a random inventory (duplicates included)
  boss, act    spawn_boss / init_mod / boss_depth / acts_per_floor, spawn_act for any base monster
  enc          an Encounter driven through add / remove / react / ready / spend / reset with ties
  effect       contracts.effect(world, name, default) for contracts, none and an unknown name
  preview      contracts.preview(world, key) for a world-like (floor_stats, monsters, player, timer)
  shop_*       a persistent Shop: new, many days (end_of_floor), buys, take-backs, mutations,
               direct Poisson draws, views of prices and policy numbers, save/load round trips

Every step stores its arguments, its result, then [loot words, loot digest16, shop words, shop
digest16]. The step script is drawn from random.Random(seed * 1013 + 29); the Godot side replays
only the recorded arguments. Imports crawler read-only.
"""
import json
import random
import sys
from dataclasses import asdict
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from make_fixtures_s2 import (CountingRandom, build, digest16, enc, monster_spec,  # noqa: E402
                              player_spec)
from crawler.bosses import (ACT_NAMES, BOSSES, acts_per_floor, boss_depth, spawn_act,  # noqa: E402
                            spawn_boss)
from crawler.contracts import CONTRACTS, effect, preview  # noqa: E402
from crawler.crafting import RECIPES, can_craft  # noqa: E402
from crawler.encounter import Encounter  # noqa: E402
from crawler.entities import MONSTERS, PETS, init_mod  # noqa: E402
from crawler.items import ITEMS, describe, floor_loot_table, glyph, value  # noqa: E402
from crawler.loot import BOX_TIERS, TIERS, box_stats, next_tier, odds, reroll_fee, roll_box  # noqa: E402
from crawler.shop import BASE_DEMAND, Shop  # noqa: E402

SEEDS = range(200)


class FakeWorld:
    """The members contracts.preview / effect read from a World."""

    def __init__(self, contract, timer, floor_stats, monsters, player):
        self.contract, self.timer, self.floor_stats = contract, timer, floor_stats
        self.monsters, self.player = monsters, player

    def timer_text(self, turns=None):
        t = self.timer if turns is None else turns
        return f"{t // 60}h {t % 60:02d}m"


# --- step generation -----------------------------------------------------------------------------

def gen_enc(sr):
    n = sr.randint(3, 8)
    specs = [["player", "", []]]
    for _ in range(n - 1):
        if sr.random() < 0.2:
            specs.append(["pet", sr.choice(list(PETS)), []])
        else:
            specs.append(["monster", sr.choice(list(MONSTERS)), []])
    ops = []
    for _ in range(sr.randint(10, 26)):
        r = sr.random()
        i = sr.randrange(n)
        if r < 0.45:
            ops.append(["add", i, sr.choice([6, 8, 8, 10, 12, 12, 14, 20, 1]), sr.choice([0, 0, 2, 2, 4, -1])])
        elif r < 0.52:
            ops.append(["remove", i])
        elif r < 0.60:
            ops.append(["react", i])
        elif r < 0.66:
            ops.append(["ready", i])
        elif r < 0.74:
            ops.append(["spend", sr.choice(["move", "action", "bonus"])])
        elif r < 0.78:
            ops.append(["reset"])
        else:
            ops.append(["look", i])
    return ["enc", specs, ops]


def gen_preview(sr):
    depth = sr.randint(1, 6)
    boss_heavy = sr.random() < 0.1
    keys = list(MONSTERS)
    monsters = [monster_spec(sr, sr.choice(keys), depth) for _ in range(sr.randint(1, 6))]
    for spec in monsters:
        if sr.random() < (0.9 if boss_heavy else 0.2):
            spec[2].append(["boss", True])
    stats = []
    for d in range(sr.choice([1, 1, 2, 3, 4, 5])):
        v0 = sr.randint(50, 600)
        stats.append(dict(depth=d + 1, damage_taken=sr.randint(0, 40), gold=sr.randint(0, 200),
                          kills=sr.randint(0, 20), viewers_start=v0,
                          viewers_end=v0 + sr.choice([-30, 0, 5, 120, 340, 900, sr.randint(-50, 500)])))
    stats[-1].pop("viewers_end")            # the open floor has no end yet; preview ignores it
    return ["preview", sr.choice(list(CONTRACTS)), player_spec(sr, depth), monsters, stats,
            sr.randint(1, 900)]


def gen_step(sr):
    r = sr.random()
    if r < 0.16:
        return ["box", sr.choice(TIERS)]
    if r < 0.20:
        return ["floor_table", sr.randint(0, 8)]
    if r < 0.28:
        return ["floor_draw", sr.randint(1, 6), sr.randint(1, 6)]
    if r < 0.33:
        return ["odds", sr.choice(TIERS)]
    if r < 0.40:
        return ["item", sr.choice(list(ITEMS))]
    if r < 0.46:
        inv = [sr.choice(list(ITEMS)) for _ in range(sr.randint(0, 5))]
        if sr.random() < 0.7:
            rec = sr.choice(RECIPES)
            inv += list(rec["needs"]) + ([rec["needs"][0]] if sr.random() < 0.3 else [])
            sr.shuffle(inv)
        return ["craft", inv]
    if r < 0.56:
        if sr.random() < 0.5:
            return ["boss", sr.randint(1, 6), sr.randint(0, 99), sr.randint(0, 59)]
        return ["act", sr.choice(["opening", "featured"]), sr.choice(list(ACT_NAMES)),
                sr.randint(0, 99), sr.randint(0, 59)]
    if r < 0.66:
        return gen_enc(sr)
    if r < 0.74:
        name = sr.choice(["gold_mult", "viewer_mult", "timer_mult", "rest_mult", "monster_damage",
                          "monster_hp_mult", "bonus_box", "nonsense"])
        con = sr.choice([None, "", "nope"] + list(CONTRACTS) * 2)
        return ["effect", con, name, sr.choice([1, 1, 0, 2.5])]
    return gen_preview(sr)


def gen_shop_step(sr, state):
    r = sr.random()
    if r < 0.56:
        state["depth"] = min(6, max(1, state["depth"] + sr.choice([0, 1, 1, -1, 0])))
        return ["shop_day", state["depth"]]
    if r < 0.70:
        return ["shop_buy", sr.choice(list(BASE_DEMAND))]
    if r < 0.76:
        return ["shop_back", sr.choice(list(BASE_DEMAND) + ["sock"])]
    if r < 0.84:
        k = sr.choice(list(BASE_DEMAND))
        return sr.choice([["shop_set", k, "on_hand", sr.choice([0, 1, 2, 5, 20])],
                          ["shop_set", k, "bought", sr.randint(0, 25)],
                          ["shop_set", k, "missed", sr.randint(0, 6)],
                          ["shop_set", k, "on_order", sr.randint(0, 9)],
                          ["shop_set", k, "forecast", sr.choice([0.0, 0.5, 4.25, 9.0])]])
    if r < 0.92:
        return ["poisson", sr.choice([0.0, 0.2, 0.5, 1.0, 3.3, 6.6, 10.0, 12.5, 0.4 * 1.5])]
    return ["shop_view"]


# --- execution -------------------------------------------------------------------------------------

def run_enc(step):
    _, specs, ops = step
    ents = [build(s) for s in specs]
    idx = {id(x): i for i, x in enumerate(ents)}
    e = Encounter(ents[0])
    out = []
    for op in ops:
        res = None
        k = op[0]
        if k == "add":
            e.add(ents[op[1]], op[2], op[3])
        elif k == "remove":
            e.remove(ents[op[1]])
        elif k == "react":
            e.react(ents[op[1]])
        elif k == "ready":
            e.ready(ents[op[1]])
        elif k == "spend":
            e.spend(op[1])
        elif k == "reset":
            e.reset_budget()
        elif k == "look":
            x = ents[op[1]]
            inside = x in e
            res = [inside, e.can_react(x), e.total(x) if inside else None,
                   [idx[id(y)] for y in e.before(x)] if inside else None,
                   [idx[id(y)] for y in e.after(x)] if inside else None]
        out.append([res, [idx[id(y)] for y in e.entities], [idx[id(y)] for y in e.monsters],
                    [e.total(y) for y in e.entities], [e.has(p) for p in ("move", "action", "bonus")],
                    e.turn_over, sorted(idx[id(y)] for y in e.reacted), [row[0] for row in e.order]])
    return out


def shop_view(shop, only=None):
    """[rows, bought, missed, log length]; rows for every item, or only the named one."""
    rows = []
    for k, s in shop.stock.items():
        if only is not None and k != only:
            continue
        rows.append([k, s.on_hand, s.forecast, s.on_order, len(s.history),
                     s.history[-1] if s.history else None, shop.price(k), shop.reorder_point(k),
                     shop.safety_stock(k), shop.order_up_to(k), Shop.sell_price(k)])
    return [rows, dict(shop.bought), dict(shop.missed), len(shop.log)]


def run_step(step, loot, shop_rng, ctx):
    k = step[0]
    if k == "box":
        return [roll_box(step[1], loot)]
    if k == "floor_table":
        keys, weights = floor_loot_table(step[1])
        return [keys, weights]
    if k == "floor_draw":
        keys, weights = floor_loot_table(step[1])
        picks = [loot.choices(keys, weights)[0] for _ in range(step[2])]
        return [picks, loot.choices(("tonic", "brew", "elixir"), (6, 3, 1))[0]]
    if k == "odds":
        t = step[1]
        return [odds(t), list(box_stats(t)), next_tier(t), reroll_fee(t), BOX_TIERS[t]["name"]]
    if k == "item":
        return [value(step[1]), glyph(step[1]), describe(step[1])]
    if k == "craft":
        return [[can_craft(r, step[1]) for r in RECIPES]]
    if k == "boss":
        _, depth, x, y = step
        b = spawn_boss(depth, x, y)
        return [asdict(b), init_mod(b), boss_depth(b), list(acts_per_floor(depth))]
    if k == "act":
        _, tier, base, x, y = step
        a = spawn_act(tier, base, x, y)
        return [asdict(a), init_mod(a)]
    if k == "enc":
        return run_enc(step)
    if k == "effect":
        _, con, name, default = step
        return [effect(FakeWorld(con, 100, [], [], None), name, default)]
    if k == "preview":
        _, key, pspec, mspecs, stats, timer = step
        player = build(pspec)
        monsters = [build(s) for s in mspecs]
        lines = preview(FakeWorld(None, timer, [dict(s) for s in stats], monsters, player), key)
        return [lines, [m.dmg_bonus for m in monsters]]
    if k == "shop_new":
        ctx["shop"] = Shop(shop_rng)
        return shop_view(ctx["shop"])
    s = ctx["shop"]
    if k == "shop_day":
        before = len(s.log)
        s.end_of_floor(step[1])
        return [s.log[before:]] + shop_view(s)
    if k == "shop_buy":
        got = s.buy(step[1])
        return [got] + shop_view(s, step[1])
    if k == "shop_back":
        s.take_back(step[1])
        return shop_view(s, step[1])
    if k == "shop_set":
        _, key, field, val = step
        if field == "bought":
            s.bought[key] = val
        elif field == "missed":
            s.missed[key] = val
        else:
            setattr(s.stock[key], field, val)
        return shop_view(s, key)
    if k == "poisson":
        return [s._poisson(step[1])]
    if k == "shop_save":
        d = json.loads(json.dumps(s.to_dict()))
        s2 = Shop(random.Random(0))
        s2.load(d)
        d0 = s.to_dict()
        return [d0["stock"], d0["bought"], d0["missed"], len(d0["log"]), d0["log"][-1], s2.to_dict() == d0]
    if k == "shop_view":
        return shop_view(s)
    raise ValueError(k)


def seed_run(seed):
    sr = random.Random(seed * 1013 + 29)
    loot = CountingRandom(seed ^ 0x100F)
    shop_rng = CountingRandom(seed ^ 0x5A0F)
    ctx = {}
    steps = [["box", t] for t in TIERS for _ in range(3)]
    for _ in range(25):
        steps.append(gen_step(sr))
    state = {"depth": 1}
    steps.append(["shop_new"])
    for _ in range(sr.randint(34, 48)):
        steps.append(gen_shop_step(sr, state))
        if sr.random() < 0.25:
            steps.append(gen_step(sr))
    steps.append(["shop_save"])
    out = []
    for step in steps:
        res = run_step(step, loot, shop_rng, ctx)
        out.append(enc([step, res, [loot.words, digest16(loot), shop_rng.words, digest16(shop_rng)]]))
    return {"seed": seed, "steps": out}


# --- tables --------------------------------------------------------------------------------------

def tables():
    out = {}
    out["boss_blocks"] = [[enc(d), enc(asdict(spawn_boss(d, 3, 4))), enc(init_mod(spawn_boss(d, 3, 4))),
                           enc(BOSSES[d].get("final", False)), enc(list(acts_per_floor(d)))]
                          for d in range(1, 7)]
    out["acts"] = [[enc([t, b]), enc(asdict(spawn_act(t, b, 5, 6))), enc(init_mod(spawn_act(t, b, 5, 6)))]
                   for t in ("opening", "featured") for b in ACT_NAMES]
    out["acts_per_floor"] = [[enc(d), enc(list(acts_per_floor(d)))] for d in range(0, 12)]
    out["items"] = [[enc(k), enc(value(k)), enc(glyph(k)), enc(describe(k))] for k in ITEMS]
    out["loot"] = [[enc(t), enc(odds(t)), enc(list(box_stats(t))), enc(next_tier(t)), enc(reroll_fee(t))]
                   for t in TIERS]
    out["shop_open"] = [[enc(k), enc(Shop(random.Random(1)).stock[k].on_hand),
                         enc(Shop(random.Random(1)).price(k))] for k in BASE_DEMAND]
    return out


def main():
    out = {"tables": tables(), "seeds": [seed_run(s) for s in SEEDS]}
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()

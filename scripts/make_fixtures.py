#!/usr/bin/env python3
"""Fixtures from real Python for the Godot foundations tests (port plan sections 6.4 and 9.1, slice S1).

Usage: make_fixtures.py out.json

Produces, from Python 3.12+ itself, many inputs with the exact output Python gives for the
operations godot/rules/py/py_math.gd, py_fmt.gd and py_json.gd reimplement, plus every constant of
crawler/config.py. godot/tests/test_py_math.gd, test_py_fmt.gd, test_py_json.gd and
test_game_config.gd compare the Godot results to these exactly. scripts/gd_test.sh writes the file
into a temp dir (FIXTURES env var) on every run; it is not committed.

Encoding (JSON numbers are doubles in Godot, so nothing numeric is a JSON number):
  None "n:"   bool "b:1"/"b:0"   int "i:<dec>"   float "f:<16 hex digits of the IEEE-754 bits>"
  str "s:<text>"   list/tuple {"l": [...]}   dict {"d": [[key, value], ...]} (insertion order)
Seeded (random.Random(20260101)), so the output is reproducible. Imports crawler read-only.
"""
import json
import random
import struct
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from crawler import config as C  # noqa: E402
from crawler.dice import average, chance_to_hit  # noqa: E402
from crawler.lines import LINES  # noqa: E402
from crawler.loot import BOX_TIERS, box_stats  # noqa: E402

rng = random.Random(20260101)


def enc(v):
    if v is None:
        return "n:"
    if isinstance(v, bool):
        return "b:1" if v else "b:0"
    if isinstance(v, int):
        return f"i:{v}"
    if isinstance(v, float):
        return "f:%016x" % struct.unpack(">Q", struct.pack(">d", v))[0]
    if isinstance(v, str):
        return "s:" + v
    if isinstance(v, (list, tuple)):
        return {"l": [enc(x) for x in v]}
    if isinstance(v, dict):
        return {"d": [[enc(k), enc(x)] for k, x in v.items()]}
    raise TypeError(type(v))


def rand_floats(n, lo, hi):
    return [rng.uniform(lo, hi) for _ in range(n)]


def ties(lo, hi):
    return [k + 0.5 for k in range(lo, hi)]


def math_cases():
    out = {}
    # Integer floor division and modulo, every sign combination, including exact multiples.
    pairs = [(a, b) for a in range(-13, 14) for b in (-7, -4, -3, -2, -1, 1, 2, 3, 4, 5, 7, 10)]
    pairs += [(rng.randint(-10**6, 10**6), rng.choice([-1, 1]) * rng.randint(1, 5000)) for _ in range(500)]
    pairs += [(9, 2), (8, 2), (-1, 2), (10, 2), (7, -2), (60, 60), (-60, 60), (-1, 60), (125, 60)]
    out["intdiv"] = [[enc(a), enc(b), enc(a // b), enc(a % b)] for a, b in pairs]
    fl = [(rng.uniform(-400, 400), rng.choice([-1, 1]) * rng.uniform(0.1, 90)) for _ in range(300)]
    fl += [(x, y) for x in (-720.0, -45.0, -22.5, 0.0, 22.5, 45.0, 359.9, 360.0, 720.0) for y in (360.0, 90.0, -360.0, 8.0)]
    fl += [(-0.0, 5.0), (0.0, -5.0), (-5.0, 5.0), (5.0, -5.0), (-360.0, 360.0)]
    out["floatmod"] = [[enc(a), enc(b), enc(a % b)] for a, b in fl]
    # round(x): ties, products the game forms, random values, big values.
    xs = ties(-30, 30) + [0.5, -0.5, 1.5, 2.5, -1.5, -2.5, 12.5, 10 * 1.25, 0.49999999999999994, -0.49999999999999994,
                          2.5000000000000004, 1e15 + 0.5, 4503599627370497.5, 2.0 ** 52, -(2.0 ** 52) - 1.0, 1e18, -3e17]
    for mult in (1.5, 2, 3, 1.03, 1.1, 1.25, 0.7, 0.85, 1.4, 1.2, 0.6, 2.5):
        for base in range(0, 40):
            xs.append(base * mult)
            xs.append((base + 2) * mult)
    for price in (3, 6, 12, 25, 40, 55, 90):
        for scarcity in (0, 0.3, 1, 1.0, 1.7, 2.5):
            xs.append(price * (1 + 0.6 * scarcity))
            xs.append(price * 0.4)
    xs += rand_floats(800, -500, 500) + rand_floats(200, -3, 3)
    out["round"] = [[enc(float(x)), enc(round(x))] for x in xs]
    # round(x, n): the game uses 2 and 3; also 0 and 1.
    rn = []
    for x in rand_floats(500, -50, 50) + [k / 8 for k in range(-40, 40)] + [1 / 3, 2 / 3, 0.0005, 0.0015, 2.675, 1.005, 0.1 + 0.2,
                                                                         5 / 7, 123.4565, 1e-5, 999.9995]:
        for n in (0, 1, 2, 3):
            rn.append([enc(float(x)), enc(n), enc(round(x, n))])
    for hp in range(0, 60, 7):
        for mx in (34, 41, 48, 55, 62, 69):
            if hp <= mx:
                rn.append([enc(hp / mx), enc(3), enc(round(hp / mx, 3))])
    out["round_n"] = rn
    # sum() of floats: expected_damage-shaped lists (probability * integer) and random ones.
    sums = []
    for _ in range(400):
        n = rng.randint(1, 20)
        sums.append([rng.choice([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12]) / rng.choice([20, 6, 36, 4, 8]) * rng.randint(1, 12)
                     for _ in range(n)])
    for _ in range(150):
        sums.append([rng.uniform(-1000, 1000) for _ in range(rng.randint(1, 40))])
    for _ in range(100):
        sums.append([rng.choice([0.1, 0.2, 0.3, 1e16, -1e16, 1.0, 1e-8, 0.7]) for _ in range(rng.randint(2, 12))])
    sums += [[0.1] * 10, [0.1, 0.2, 0.3], [1e100, 1.0, -1e100], [1.0, 1e100, 1.0, -1e100], [float("inf"), 1.0], [5.0]]
    out["fsum"] = [[enc(s), enc(sum(s))] for s in sums]
    # sorted(key=), including reverse and tuple keys; min/max first extreme wins.
    sorts = []
    for _ in range(150):
        n = rng.randint(0, 14)
        items = [[rng.randint(0, 5), i] for i in range(n)]          # many ties
        for rev in (False, True):
            sorts.append(["int", items, rev, [x[1] for x in sorted(items, key=lambda x: x[0], reverse=rev)]])
        tup = [[(rng.randint(0, 3), rng.choice([0.5, 1.5, 2.0]), rng.choice("abc")), i] for i in range(n)]
        sorts.append(["tuple", [[list(k), i] for k, i in tup], False, [x[1] for x in sorted(tup, key=lambda x: x[0])]])
        words = [[rng.choice(["b", "a", "ab", "B", "z", "aa"]), i] for i in range(n)]
        sorts.append(["str", words, False, [x[1] for x in sorted(words, key=lambda x: x[0])]])
        fl_items = [[rng.choice([0.5, 1.0, 1.5, 2.0, -1.0]), i] for i in range(n)]
        sorts.append(["float", fl_items, True, [x[1] for x in sorted(fl_items, key=lambda x: x[0], reverse=True)]])
    out["sort"] = [[enc(kind), enc(items), enc(rev), enc(order)] for kind, items, rev, order in sorts]
    ext = []
    for _ in range(150):
        n = rng.randint(1, 12)
        items = [[rng.randint(0, 4), i] for i in range(n)]
        ext.append([enc(items), enc(min(items, key=lambda x: x[0])[1]), enc(max(items, key=lambda x: x[0])[1])])
    out["extreme"] = ext
    # Python tuple ordering.
    tc = []
    for _ in range(200):
        a = [rng.randint(0, 2) for _ in range(rng.randint(0, 4))]
        b = [rng.randint(0, 2) for _ in range(rng.randint(0, 4))]
        tc.append([enc(a), enc(b), enc((a > b) - (a < b))])
    out["tuple_cmp"] = tc
    return out


def game_floats():
    """Floats the game writes: hp_frac, ev, forecasts, chances, averages, quotients."""
    vals = []
    for mx in range(20, 90, 3):
        for hp in range(0, mx + 1, 3):
            vals.append(round(hp / mx, 3))
            vals.append(hp / mx)
    for tier in BOX_TIERS:
        ev, sd = box_stats(tier)
        vals += [ev, sd, round(ev, 2), round(sd, 3)]
    for n in range(1, 5):
        for sides in (4, 6, 8, 10, 12, 20):
            for b in (-2, 0, 3):
                vals.append(average(n, sides, b))
    for bonus in range(-3, 12):
        for target in range(8, 22):
            for crit in (1, 3):
                vals += list(chance_to_hit(bonus, target, crit))
    vals += [0.1, 0.2, 0.30000000000000004, 0.3, 0.7, 1.25, 0.6, 0.25, 0.04, 0.97, 0.45, 1.5, 2.0, 3.0, 100.0, 1.0, 0.5, 0.0, 12.0,
             0.1 + 0.7, 1 / 3, 2 / 3, 1 / 7, 45 * 0.97, 50 * 0.97 ** 3, 0.5 * 1.4 * 0.6, 3.0 * 1.1, 1.45 ** 5, 8 * 1.45 ** 3,
             1e-4, 1.5e-4, 9.999e-5, 1e15, 1e16, 1.5e16, 123456789012345.0, 1e22, 1e23, 5e-324, 1.7976931348623157e308,
             -0.0, -1.5, -0.001, 2.5e-5, 1e-5]
    return vals


class Safe(dict):
    def __missing__(self, key):
        return "?"


def fmt_cases():
    out = {}
    g = game_floats()
    out["repr_game"] = [[enc(x), enc(repr(x))] for x in g]
    edge = []
    for e in range(-30, 31):
        edge += [10.0 ** e, 1.5 * 10.0 ** e, 9.0 * 10.0 ** e, 123456.0 * 10.0 ** e]
    edge += [float(k) for k in range(-30, 40)] + [k / 10 for k in range(-60, 60)] + [k / 100 for k in range(0, 300)]
    out["repr_edge"] = [[enc(x), enc(repr(x))] for x in edge]
    rnd = [rng.random() for _ in range(2000)] + [rng.uniform(-1e6, 1e6) for _ in range(1000)] + \
          [rng.random() * 10.0 ** rng.randint(-20, 25) for _ in range(1000)] + [rng.random() * 100 / 3 for _ in range(500)]
    out["repr_random"] = [[enc(x), enc(repr(x))] for x in rnd]
    # {:.nf}, {:+.nf}, {:.n%}, {:+.n%}, {:,.0f}.
    fx = ties(-12, 12) + [k / 8 for k in range(-40, 40)] + [k / 100 for k in range(-250, 250, 7)] + g[:600] + \
        rand_floats(800, -200, 200) + rand_floats(400, -1, 1) + [-0.4, -0.04, 0.05, 0.95, 0.995, 2.675, 1e6, 1234567.891, -1234567.891,
                                                                  1e15, float("nan"), float("inf"), float("-inf"), -0.0, 0.0]
    fixed, pct, thou = [], [], []
    for x in fx:
        for n in (0, 1, 2, 3):
            fixed.append([enc(x), enc(n), enc(f"{x:.{n}f}"), enc(f"{x:+.{n}f}")])
        for n in (0, 1, 2):
            pct.append([enc(x), enc(n), enc(f"{x:.{n}%}"), enc(f"{x:+.{n}%}")])
        thou.append([enc(x), enc(f"{x:,.0f}"), enc(f"{x:,.2f}")])
    out["fixed"], out["percent"], out["thousands_fixed"] = fixed, pct, thou
    ints = [0, 1, -1, 9, 10, 99, 100, 999, 1000, 1001, -999, -1000, -1234567, 1234567, 10 ** 9, -10 ** 12, 12, 7, 60, 125]
    ints += [rng.randint(-10 ** 7, 10 ** 7) for _ in range(300)]
    out["ints"] = [[enc(n), enc(f"{n:+d}"), enc(f"{n:,}"), enc(f"{n:02d}"), enc(f"{n:05d}"), enc(f"{n:>3}"), enc(f"{n:<4}")]
                   for n in ints]
    caps = ["opening_act", "silver", "GOLD", "bronze", "", "a", "hello world", "123abc", "x Y z", "headliner", "Featured", "eCLAIR"]
    out["capitalize"] = [[enc(s), enc(s.capitalize())] for s in caps]
    # str() of scalars and containers, repr() of strings.
    vals = [None, True, False, 0, -3, 12, 0.1, 0.5, 2.0, 1e-5, 1e16, "text", "it's", 'say "hi"', "both ' and \"", "tab\there", "nl\n", "",
            [1, 2.5, "a"], [], {}, {"a": 1, "b": [True, None]}, (1, 2), 1.25, 100.0]
    out["str"] = [[enc(v), enc(str(v)), enc(repr(v))] for v in vals]
    # format_map with the _Safe missing-key rule: every real System line, plus brace edge cases.
    templates = []
    for d in LINES.values():
        for lst in d.values():
            templates += list(lst)
    ctx_pool = {"hero": "Zed", "address": "sir", "depth": 3, "item": "Dented Frying Pan", "tier": "Silver", "value": 22, "ev": "14",
                "gold": 45, "viewers": 1200, "name": "Sewer Gnawer", "amount": 5, "boss": "The Grease Trap King", "pet": "Mittens",
                "sponsor": "Gloop Energy", "hp": 7, "damage": 6, "turns": 120, "xp": 3, "ratio": 0.25, "flag": True}
    fm = []
    for t in templates:
        partial = dict(list(ctx_pool.items())[:4])
        for ctx in (dict(ctx_pool), partial, {}):
            fm.append([enc(t), enc(ctx), enc(t.format_map(Safe(ctx)))])
    for t in ["{{literal}} {a}", "{a}{b}", "x {missing} y", "{{}}", "{a} and {a}", "{x}", "100%", "no braces"]:
        for ctx in ({"a": 1.5, "b": None, "x": False}, {}):
            fm.append([enc(t), enc(ctx), enc(t.format_map(Safe(ctx)))])
    out["format_map"] = fm
    return out


def json_cases():
    values = [
        None, True, False, 0, 1, -7, 10 ** 12, 0.5, -0.0, 1e-5, 1e16, 0.1 + 0.2, 1.0, 100.0, float("nan"), float("inf"), float("-inf"),
        "", "plain", 'quote " and \\ slash', "line\nbreak\ttab\r", "\x01\x1f", "café", "☃ snow", "emoji \U0001f600", "\x7f",
        [], {}, [1, 2.5, "x", None, True], {"a": 1, "b": [1, 2, {"c": None}], "z": 0.25, "k": {}},
        {"version": 7, "seed": 5, "rng": [[1, 2, 3], None], "tiles": [[0, 1], [1, 0]], "pos": [3, 4]},
        {"zeta": 1, "alpha": 2, "mid": 3}, {"x": [[], [[]], {}]}, {1: "int key", 2.5: "float key", True: "bool key", None: "none key"},
        {"hp_frac": 0.875, "ev": 14.25, "chance": 0.3, "name": "Roöt"},
    ]
    return [[enc(v), enc(json.dumps(v)), enc(json.dumps(v, ensure_ascii=False)), enc(json.dumps(v, indent=1, ensure_ascii=False)),
             enc(json.dumps(v, indent=2))] for v in values]


def config_cases():
    return [[enc(name), enc(list(v) if isinstance(v, tuple) else v)] for name, v in vars(C).items()
            if name.isupper() and not name.startswith("_")]


def main():
    out = {"math": math_cases(), "fmt": fmt_cases(), "json": json_cases(), "config": config_cases(),
           "config_floor_turns": [[enc(d), enc(C.floor_turns(d))] for d in range(1, 8)]}
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()

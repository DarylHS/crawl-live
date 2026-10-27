#!/usr/bin/env python3
"""Export the Python game content to godot/data/*.json (port plan section 4).

    python scripts/export_content.py            # write godot/data/*.json and manifest.json
    python scripts/export_content.py --check    # exit 1 if regenerating would change any file

Imports crawler.* read-only. One JSON file per table: indent=1, ensure_ascii=False,
sort_keys=False (Python insertion order is the order the rules iterate), UTF-8, trailing
newline. Tuples become arrays, int keys become strings, achievement lambdas become rule objects.
manifest.json lists, per file, the sha256, the Python sources and `float_paths` (RFC 6901
JSON pointers, relative to the document root, to every leaf that is a Python float);
godot/rules/content.gd converts every other number to int.

Self-checks run before anything is written: achievement rules agree with the Python
lambdas on generated cases around every threshold, line placeholders are plain
identifiers, every cross-table key reference resolves, and floats have <= 15 significant digits.
"""
import argparse
import ast
import hashlib
import inspect
import itertools
import json
import os
import string
import subprocess
import sys
import types
from decimal import Decimal
from pathlib import Path

sys.dont_write_bytecode = True
os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
os.environ.setdefault("SDL_AUDIODRIVER", "dummy")
os.environ.setdefault("PYGAME_HIDE_SUPPORT_PROMPT", "1")

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
OUT = ROOT / "godot" / "data"
GENERATOR_VERSION = 1

from crawler import (achievements as A, ai, attributes, bosses, character, classes,  # noqa: E402
                     config as C, contracts, crafting, dungeon, encounter, entities, funfacts,
                     items, lines, loot, practice, shop, showrunner, telemetry, world as W)

if sys.version_info < (3, 12):
    sys.exit("export_content.py needs Python 3.12+ (the port targets 3.12+ semantics)")


# --- Conversion -----------------------------------------------------------------------

def conv(v):
    """Python content value to a JSON-able value (insertion order kept)."""
    if isinstance(v, dict):
        return {str(k): conv(x) for k, x in v.items()}
    if isinstance(v, (list, tuple)):
        return [conv(x) for x in v]
    if isinstance(v, (set, frozenset)):
        raise TypeError("sets have no stable order; convert explicitly")
    if isinstance(v, float):
        digits = len(Decimal(repr(v)).as_tuple().digits)
        assert digits <= 15, f"float {v!r} has more than 15 significant digits"
        assert v == v and v not in (float("inf"), float("-inf")), "non-finite float"
        return v
    if v is None or isinstance(v, (bool, int, str)):
        return v
    raise TypeError(f"cannot export {type(v)}: {v!r}")


def _defined_here(module):
    """Names assigned at the top level of the module's own source (so imported names are skipped)."""
    tree = ast.parse(inspect.getsource(module))
    names = set()
    for node in tree.body:
        targets = node.targets if isinstance(node, ast.Assign) else \
            [node.target] if isinstance(node, ast.AnnAssign) else []
        for t in targets:
            for n in ast.walk(t):
                if isinstance(n, ast.Name):
                    names.add(n.id)
    return names


def upper_names(module, exclude=()):
    """Public UPPER_CASE constants a module defines itself, in definition order
    (not imported names, functions or paths)."""
    own = _defined_here(module)
    return {k: v for k, v in vars(module).items()
            if k.isupper() and k in own and k not in exclude
            and isinstance(v, (int, float, str, tuple, list, dict))}


def pointer(parts):
    return "".join("/" + str(p).replace("~", "~0").replace("/", "~1") for p in parts)


def float_paths(node, parts=()):
    out = []
    if isinstance(node, dict):
        for k, v in node.items():
            out += float_paths(v, parts + (k,))
    elif isinstance(node, list):
        for i, v in enumerate(node):
            out += float_paths(v, parts + (i,))
    elif isinstance(node, float):
        out.append(pointer(parts))
    return out


# --- Achievement rules (4.4) ----------------------------------------------------------

def _r(kind, **kw):
    return dict(kind=kind, **kw)


ACHIEVEMENT_RULES = {
    "first_blood": _r("counter_gte", counter="kills", n=1),
    "pest_control": _r("counter_gte", counter="kills", n=15),
    "close_call": _r("field_lte_floordiv", field="player_hp", of="player_max_hp", div=4),
    "deep_diver": _r("field_gte", field="depth", n=3),
    "cutting_it_fine": _r("field_lt_frac", field="timer_left", of="timer_max", frac=0.1),
    "demolition": _r("field_gte", field="kills", n=2),
    "pyrotechnician": _r("field_gte", field="kills", n=3),
    "opening_night": _r("field_eq", field="tier", value="opening"),
    "upstaged": _r("field_eq", field="tier", value="featured"),
    "locksmith": _r("field_true", field="early"),
    "one_hp_wonder": _r("field_eq", field="hp", value=1),
    "crowd_pleaser": _r("world_gte", stat="viewers", n=1000),
    "best_friends": _r("field_gte", field="level", n=3),
    "pet_project": _r("counter_gte", counter="pet_kills", n=10),
    "jack_of_all_trades": _r("field_gte", field="many_at_3", n=8),
    "critical_darling": _r("always"),
    "blooper_reel": _r("always"),
    "cursed_dice": _r("counter_gte", counter="nat1s", n=5),
    "underfoot": _r("all", rules=[_r("field_eq", field="skill", value="stomping"),
                                  _r("field_gte", field="level", n=3)]),
    "bare_knuckle_tv": _r("counter_gte", counter="unarmed_kills", n=10),
    "cartographer": _r("counter_gte", counter="maps", n=3),
    "pack_rat": _r("counter_gte", counter="pickups", n=10),
    "hoarder": _r("world_gte", stat="inventory_len", n_config="INVENTORY_SIZE"),
    "dressed_to_kill": _r("equipped_all", slots=["weapon", "armour"]),
    "dumpster_diver": _r("counter_gte", counter="junk_sold", n=5),
    "upcycler": _r("always"),
    "nap_champion": _r("field_gte", field="turns", n=180),
}
for _depth in bosses.BOSSES:
    ACHIEVEMENT_RULES[f"headliner_{_depth}"] = _r("field_eq", field="depth", value=_depth)


def rule_test(rule, t, d):
    """Python twin of AchievementRules.test (the interpreter the GDScript port mirrors)."""
    k = rule["kind"]
    if k == "always":
        return True
    if k == "counter_gte":
        return getattr(t, rule["counter"]) >= rule["n"]
    if k == "field_gte":
        return d[rule["field"]] >= rule["n"]
    if k == "field_eq":
        return d[rule["field"]] == rule["value"]
    if k == "field_true":
        return bool(d.get(rule["field"], False))
    if k == "field_lte_floordiv":
        return d[rule["field"]] <= d[rule["of"]] // rule["div"]
    if k == "field_lt_frac":
        return d[rule["field"]] < rule["frac"] * d[rule["of"]]
    if k == "world_gte":
        n = getattr(C, rule["n_config"]) if "n_config" in rule else rule["n"]
        stat = t.world.viewers if rule["stat"] == "viewers" else len(t.world.inventory)
        return stat >= n
    if k == "equipped_all":
        return set(rule["slots"]) <= t.equipped
    if k == "all":
        return all(rule_test(r, t, d) for r in rule["rules"])
    raise ValueError(f"unknown rule kind {k}")


def probe_axes(rule):
    """Axes of values to try, as {('t'|'d'|'w', name): [values]}, around each threshold."""
    k = rule["kind"]
    def around(n):
        return sorted({0, n - 2, n - 1, n, n + 1, n + 2})
    if k == "always":
        return {}
    if k == "counter_gte":
        return {("t", rule["counter"]): around(rule["n"])}
    if k == "field_gte":
        return {("d", rule["field"]): around(rule["n"])}
    if k == "field_eq":
        v = rule["value"]
        vals = [v, "", "other", 0, None] if isinstance(v, str) else around(v)
        return {("d", rule["field"]): vals}
    if k == "field_true":
        return {("d", rule["field"]): ["missing", False, True]}
    if k == "field_lte_floordiv":
        return {("d", rule["of"]): [0, 1, 3, 4, 5, 7, 8, 9, 12, 30, 34, 41],
                ("d", rule["field"]): list(range(0, 44))}
    if k == "field_lt_frac":
        return {("d", rule["of"]): [0, 1, 10, 11, 19, 20, 100, 600, 720, 780],
                ("d", rule["field"]): [0, 1, 2, 9, 10, 11, 12, 19, 20, 21, 59, 60, 61, 71, 72, 73, 78, 79, 80, 600, 720]}
    if k == "world_gte":
        n = getattr(C, rule["n_config"]) if "n_config" in rule else rule["n"]
        return {("w", rule["stat"]): around(n)}
    if k == "equipped_all":
        return {("t", "equipped"): [set(), {"weapon"}, {"armour"}, {"weapon", "armour"},
                                    {"weapon", "armour", "x"}, {"x"}]}
    if k == "all":
        axes = {}
        for r in rule["rules"]:
            axes.update(probe_axes(r))
        return axes
    raise ValueError(k)


def build_case(point):
    t = A.Tracker(types.SimpleNamespace(viewers=0, inventory=[]))
    d = {}
    for (where, name), v in point.items():
        if where == "t":
            setattr(t, name, v)
        elif where == "d":
            if v != "missing" or name != "early":
                d[name] = v
        elif name == "viewers":
            t.world.viewers = v
        else:
            t.world.inventory = ["x"] * v
    return t, d


def check_achievements(ach_json):
    cases = 0
    assert set(ach_json) == set(A.ACHIEVEMENTS), "achievement keys differ"
    for key, a in A.ACHIEVEMENTS.items():
        j = ach_json[key]
        assert "rule" in j, f"achievement {key} has no rule"
        axes = probe_axes(j["rule"])
        names = list(axes)
        for combo in itertools.product(*(axes[n] for n in names)):
            point = dict(zip(names, combo))
            t, d = build_case(point)
            want = bool(a["test"](t, d))
            got = rule_test(j["rule"], t, d)
            assert got == want, f"{key}: lambda {want} vs rule {got} at {point}"
            cases += 1
    return cases


# --- Tables ---------------------------------------------------------------------------

def achievements_table():
    out = {}
    for key, a in A.ACHIEVEMENTS.items():
        out[key] = dict(name=a["name"], desc=a["desc"], tier=a["tier"], on=a["on"],
                        rule=ACHIEVEMENT_RULES[key])
    return out


def named(d, fields):
    return [dict(zip(fields, row)) for row in d]


def ui_config():
    from crawler.ui import firstperson as fp, hud, menus, report as ui_report, screens
    from crawler import game
    layout = ("TILE", "VIEW_W", "VIEW_H", "PANEL_W", "LOG_H", "SCREEN_W", "SCREEN_H", "FPS", "LOG_LINES")
    colours = ("BG", "PANEL_BG", "TEXT", "TEXT_DIM", "ACCENT", "DANGER", "WARN", "GOOD", "INFO",
               "WALL_LIT", "WALL_DIM", "FLOOR_LIT", "FLOOR_DIM", "SAFE_LIT", "SAFE_DIM", "PLAYER_COLOUR")
    return {
        "layout": {k: getattr(C, k) for k in layout},
        "colours": {k: getattr(C, k) for k in colours},
        "firstperson": {
            "TEX": fp.TEX, "LIGHT": fp.LIGHT, "PLANE": fp.PLANE, "DIRS": fp.DIRS, "COMPASS": fp.COMPASS,
            "SETTLE": fp.SETTLE, "WALK_SPEED": fp.WALK_SPEED, "MM_WINDOW": fp.MM_WINDOW,
            "MM_SCALE": fp.MM_SCALE, "DEPTH_TINT": fp.DEPTH_TINT, "TIER_SCALE": fp.TIER_SCALE,
            "TIER_OUTLINE": fp.TIER_OUTLINE, "MM_BACK": fp.MM_BACK, "MM_FLOOR": fp.MM_FLOOR,
            "MM_SAFE": fp.MM_SAFE, "MM_IN_VIEW": fp.MM_IN_VIEW, "MM_SAFE_IN_VIEW": fp.MM_SAFE_IN_VIEW,
            # TURN_SPEED (2 pi radians a second) is not exported: it has 16 digits; use TAU in code.
        },
        "input": {"TURN_RATE": game.TURN_RATE, "HOLD_DELAY": game.HOLD_DELAY,
                  "NEXT_STEP": game.NEXT_STEP, "STEP_GAP": game.STEP_GAP, "MAX_DT": game.MAX_DT},
        "hud": {
            "TIER_COLOURS": hud.TIER_COLOURS,
            "FURNITURE_GLYPHS": {k: {"glyph": g, "colour": c} for k, (g, c) in hud.FURNITURE_GLYPHS.items()},
            "TRACKER_W": hud.TRACKER_W, "TRACKER_ROWS": hud.TRACKER_ROWS,
            "COMBAT_TOAST_TURNS": hud.COMBAT_TOAST_TURNS,
        },
        "menus": {"SHOP_COLS": [{"title": t, "x": x} for t, x in menus.SHOP_COLS],
                  "ATTR_SOURCE_X": menus.ATTR_SOURCE_X, "INV_STATS_X": menus.INV_STATS_X,
                  "PRACTICE_TEXT_X": menus.PRACTICE_TEXT_X},
        "report": {"GRID": ui_report.GRID, "EXPECTED": ui_report.EXPECTED},
        "screens": {
            "TOP_CONTROLS": screens.TOP_CONTROLS, "FP_CONTROLS": screens.FP_CONTROLS,
            "SHARED_CONTROLS": screens.SHARED_CONTROLS, "COMBAT_CONTROLS": screens.COMBAT_CONTROLS,
            "VIEW_NAMES": screens.VIEW_NAMES, "PREMISE": screens.PREMISE, "HELP_STEP": screens.HELP_STEP,
        },
    }


def tables():
    """name -> (python value, sources). Order is the manifest order."""
    cfg = {
        "config": upper_names(C),
        "ai": upper_names(ai),
        "attributes": {k: getattr(attributes, k) for k in
                       ("BASE_SCORE", "START_POINTS", "POINTS_PER_LEVEL", "MAX_SCORE")},
        "bosses": {"MAP_RADIUS": bosses.MAP_RADIUS, "PHASE_TWO": bosses.PHASE_TWO},
        "classes": {"CHOICE_FLOOR": classes.CHOICE_FLOOR, "FLAT_BONUSES": classes.FLAT_BONUSES},
        "contracts": {"OFFER_FROM_FLOOR": contracts.OFFER_FROM_FLOOR, "OFFER_CHANCE": contracts.OFFER_CHANCE},
        "crafting": {"CRAFT_TURNS": crafting.CRAFT_TURNS},
        "dungeon": {"NEIGHBOURS_8": dungeon.NEIGHBOURS_8},
        "encounter": {"PARTS": encounter.PARTS, "PART_NAMES": encounter.PART_NAMES},
        "funfacts": upper_names(funfacts),
        "items": {"GLYPHS": items.GLYPHS, "EQUIP_SLOTS": items.EQUIP_SLOTS},
        "lines": {"JACKPOT_VALUE": lines.JACKPOT_VALUE},
        "loot": {"TIERS": loot.TIERS, "TRADE_UP_COST": loot.TRADE_UP_COST,
                 "REROLL_FEE_FRAC": loot.REROLL_FEE_FRAC},
        "practice": {k: getattr(practice, k) for k in ("MAX_LEVEL", "SMALL_MONSTER_HP", "CARDIO_STEPS")},
        "shop": {k: getattr(shop, k) for k in ("DEMAND_GROWTH", "ALPHA", "LEAD_TIME", "SAFETY_Z",
                                               "SCARCITY_MARKUP", "SELL_RATE")},
        "showrunner": {k: getattr(showrunner, k) for k in
                       ("START_VIEWERS", "MIN_VIEWERS", "SAMPLE_EVERY", "IDLE_TURNS", "DECAY",
                        "MULTI_WINDOW", "CLUTCH_FRAC", "SPEAK_CHANCE", "QUIP_CHANCE", "FLEE_QUIP_GAP",
                        "PET_EVENTS")},
        "telemetry": {"SKIP": sorted(telemetry.SKIP), "VALUE_KEYS": telemetry.VALUE_KEYS,
                      "DETAIL_KEYS": telemetry.DETAIL_KEYS},
        "world": {"PET_MODES": W.World.PET_MODES},
    }
    return {
        "config.json": (cfg, ["crawler/config.py", "crawler/ai.py", "crawler/attributes.py",
                              "crawler/bosses.py", "crawler/classes.py", "crawler/contracts.py",
                              "crawler/crafting.py", "crawler/dungeon.py", "crawler/encounter.py",
                              "crawler/funfacts.py", "crawler/items.py", "crawler/lines.py",
                              "crawler/loot.py", "crawler/practice.py", "crawler/shop.py",
                              "crawler/showrunner.py", "crawler/telemetry.py", "crawler/world.py"]),
        "attributes.json": (attributes.ATTRS, ["crawler/attributes.py"]),
        "monsters.json": (entities.MONSTERS, ["crawler/entities.py"]),
        "bosses.json": (bosses.BOSSES, ["crawler/bosses.py"]),
        "acts.json": ({"acts": bosses.ACTS, "names": bosses.ACT_NAMES}, ["crawler/bosses.py"]),
        "pets.json": (entities.PETS, ["crawler/entities.py"]),
        "pet_quips.json": (entities.PET_QUIPS, ["crawler/entities.py"]),
        "items.json": ({"fists": items.FISTS, "items": items.ITEMS}, ["crawler/items.py"]),
        "floor_loot.json": (named(items.FLOOR_LOOT, ("item", "weight", "min_floor")), ["crawler/items.py"]),
        "loot_boxes.json": ({t: dict(name=b["name"], colour=b["colour"],
                                     table=named(b["table"], ("item", "weight")))
                             for t, b in loot.BOX_TIERS.items()}, ["crawler/loot.py", "crawler/config.py"]),
        "races.json": (classes.RACES, ["crawler/classes.py"]),
        "classes.json": (classes.CLASSES, ["crawler/classes.py"]),
        "skills.json": (classes.SKILLS, ["crawler/classes.py"]),
        "backstories.json": (character.BACKSTORIES, ["crawler/character.py"]),
        "genders.json": (character.GENDERS, ["crawler/character.py"]),
        "achievements.json": (achievements_table(), ["crawler/achievements.py", "crawler/bosses.py"]),
        "lines.json": (lines.LINES, ["crawler/lines.py"]),
        "practice_skills.json": (practice.SKILLS, ["crawler/practice.py"]),
        "shop.json": ({"base_demand": shop.BASE_DEMAND}, ["crawler/shop.py"]),
        "contracts.json": (contracts.CONTRACTS, ["crawler/contracts.py"]),
        "recipes.json": (crafting.RECIPES, ["crawler/crafting.py"]),
        "sponsor_gifts.json": (named(showrunner.SPONSOR_GIFTS, ("viewers", "tier", "sponsor")),
                               ["crawler/showrunner.py"]),
        "ui_config.json": (ui_config(), ["crawler/config.py", "crawler/game.py", "crawler/ui/firstperson.py",
                                         "crawler/ui/hud.py", "crawler/ui/menus.py", "crawler/ui/report.py",
                                         "crawler/ui/screens.py"]),
    }


# --- Self-checks ----------------------------------------------------------------------

def check_lines(lines_json):
    fmt = string.Formatter()
    n = 0
    for ev, pools in lines_json.items():
        assert set(pools) <= {"mild", "spicy"}, f"lines.{ev}: unexpected pool names {set(pools)}"
        for pool, texts in pools.items():
            for text in texts:
                assert "{{" not in text and "}}" not in text, f"lines.{ev}.{pool}: escaped brace in {text!r}"
                for _lit, field, spec, conv_ in fmt.parse(text):
                    if field is None:
                        continue
                    assert field.isidentifier() and not spec and conv_ is None, \
                        f"lines.{ev}.{pool}: placeholder {{{field}}} is not a plain identifier in {text!r}"
                    n += 1
    return n


def check_refs(t):
    """Every key referenced across tables exists."""
    j = {name: data for name, (data, _) in t.items()}
    item_keys = set(j["items.json"]["items"])
    boxes = set(j["loot_boxes.json"])
    monsters, pets = set(j["monsters.json"]), set(j["pets.json"])
    backstories, skills = set(j["backstories.json"]), set(j["skills.json"])
    cfg = j["config.json"]
    n = 0

    def need(key, pool, where):
        nonlocal n
        assert key in pool, f"{where}: unknown key {key!r}"
        n += 1

    for k, m in j["monsters.json"].items():
        for d in m["drops"]:
            need(d, item_keys, f"monsters.{k}.drops")
    for k, b in j["bosses.json"].items():
        need(b["box"], boxes, f"bosses.{k}.box")
    for k in j["acts.json"]["names"]:
        need(k, monsters, "acts.names")
    for k in j["pet_quips.json"]:
        need(k, pets, "pet_quips")
    for ev in cfg["showrunner"]["PET_EVENTS"].values():
        for sp, q in j["pet_quips.json"].items():
            if ev != "flee" or sp == "mouse":
                need(ev, set(q), f"pet_quips.{sp}")
    for k, v in j["items.json"]["items"].items():
        need(v["kind"], set(cfg["items"]["GLYPHS"]), f"items.{k}.kind")
    for row in j["floor_loot.json"]:
        need(row["item"], item_keys, "floor_loot")
    for t_, b in j["loot_boxes.json"].items():
        need(t_, set(cfg["loot"]["TIERS"]), "loot.TIERS")
        for row in b["table"]:
            need(row["item"], item_keys, f"loot_boxes.{t_}")
    for tier in cfg["loot"]["TIERS"]:
        need(tier, boxes, "loot.TIERS")
    for k, c in j["classes.json"].items():
        need(c["skill"], skills, f"classes.{k}.skill")
        for p in c.get("pairs", []):
            need(p, backstories, f"classes.{k}.pairs")
    for item in cfg["config"]["HEADLINER_DROPS"]:
        need(item, item_keys, "config.HEADLINER_DROPS")
    for k in j["shop.json"]["base_demand"]:
        need(k, item_keys, "shop.base_demand")
    for k, c in j["contracts.json"].items():
        if "bonus_box" in c:
            need(c["bonus_box"], boxes, f"contracts.{k}.bonus_box")
    for r in j["recipes.json"]:
        for k in r["needs"] + [r["makes"]]:
            need(k, item_keys, f"recipes.{r['key']}")
    for g in j["sponsor_gifts.json"]:
        need(g["tier"], boxes, "sponsor_gifts")
    for k, a in j["achievements.json"].items():
        need(a["tier"], boxes, f"achievements.{k}.tier")
    for a in cfg["bosses"]["PHASE_TWO"]["adds"]:
        need(a, monsters, "bosses.PHASE_TWO.adds")
    for k in j["monsters.json"]:
        need(k, set(j["acts.json"]["names"]), "monsters have act names")
    for k, s in j["practice_skills.json"].items():
        assert {"name", "group", "trains", "effect"} <= set(s), f"practice_skills.{k} incomplete"
    for ev in j["lines.json"]:
        assert isinstance(ev, str)
    return n


# --- Output ---------------------------------------------------------------------------

def dumps(obj):
    return json.dumps(obj, indent=1, ensure_ascii=False, sort_keys=False) + "\n"


def git_commit():
    try:
        return subprocess.run(["git", "rev-parse", "HEAD"], cwd=ROOT, capture_output=True, text=True,
                              check=True).stdout.strip()
    except Exception:
        return "unknown"


def build():
    raw = tables()
    exported = {name: (conv(data), src) for name, (data, src) in raw.items()}
    # Checks run on exported (JSON-shaped) data so what is checked is what is written.
    n_cases = check_achievements(exported["achievements.json"][0])
    n_ph = check_lines(exported["lines.json"][0])
    n_refs = check_refs(exported)
    assert len(exported["achievements.json"][0]) == 33
    files, manifest_files = {}, {}
    for name, (data, src) in exported.items():
        text = dumps(data)
        files[name] = text
        manifest_files[name] = {"sha256": hashlib.sha256(text.encode("utf-8")).hexdigest(),
                                "sources": src, "float_paths": float_paths(data)}
    manifest = {"generator": GENERATOR_VERSION, "python": sys.version.split()[0],
                "source_commit": git_commit(), "files": manifest_files}
    files["manifest.json"] = dumps(manifest)
    return files, (n_cases, n_ph, n_refs)


# Fields of manifest.json that legitimately change without the content changing.
VOLATILE = ("python", "source_commit")


def check(files):
    bad = []
    for name, text in files.items():
        p = OUT / name
        if not p.exists():
            bad.append(f"{name}: missing")
            continue
        old = p.read_text(encoding="utf-8")
        if name == "manifest.json":
            a, b = json.loads(old), json.loads(text)
            for k in VOLATILE:
                a.pop(k, None)
                b.pop(k, None)
            if a != b:
                bad.append(f"{name}: differs")
        elif old != text:
            bad.append(f"{name}: differs")
    extra = sorted(p.name for p in OUT.glob("*.json") if p.name not in files) if OUT.exists() else []
    bad += [f"{n}: not generated by this script" for n in extra]
    return bad


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--check", action="store_true", help="exit 1 if regenerating would change any file")
    args = ap.parse_args()
    files, (n_cases, n_ph, n_refs) = build()
    print(f"self-checks ok: {n_cases} achievement cases, {n_ph} placeholders, {n_refs} key references")
    if args.check:
        bad = check(files)
        if bad:
            print("DRIFT:\n  " + "\n  ".join(bad))
            sys.exit(1)
        print(f"godot/data is up to date ({len(files)} files)")
        return
    OUT.mkdir(parents=True, exist_ok=True)
    for name, text in files.items():
        (OUT / name).write_text(text, encoding="utf-8", newline="\n")
    total = sum(len(t.encode("utf-8")) for t in files.values())
    print(f"wrote {len(files)} files, {total} bytes to {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

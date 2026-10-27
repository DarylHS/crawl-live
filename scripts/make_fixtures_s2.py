#!/usr/bin/env python3
"""Fixtures from real Python for the Godot S2 tests (dice, attributes, entities, combat).

Usage: make_fixtures_s2.py out.json

Sibling of make_fixtures.py (same encoding, see its docstring). Produces:

  tables  exact tables that need no RNG: dice_distribution, chance_to_hit, needed_roll, average, fmt,
          attribute modifiers and proficiency, monster_table, and per-key stat blocks, spawned
          monsters, pets and players as to_dict, init_mod.
  seeds   for seeds 0-199 a scripted sequence of STEPS_PER_SEED steps run on one
          CountingRandom(seed): d20 (with/without advantage), roll, attack (player vs every monster
          kind at depths 1-6, monsters vs player, pet vs monster; mult, sure, bonus, crit_bonus,
          advantage), saving_throw, hit_chance / crit_chance / expected_damage, gain_xp for Player and
          Pet, and entity helpers (to_dict, damage_text, take_damage, heal, the/The/a).

Every step stores its arguments, its result fields, and the words consumed so far plus the first 16
hex characters of the state digest (sha256 of "index,w0,...,w623", as PyRandom.state_digest). The step
script is drawn from a separate random.Random(seed * 1009 + 17) so the fixture is reproducible; the
Godot side replays only the recorded arguments. Imports crawler read-only.
"""
import hashlib
from dataclasses import asdict
import json
import random
import struct
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from crawler import attributes as A  # noqa: E402
from crawler import config as C  # noqa: E402
from crawler.combat import attack, crit_chance, expected_damage, hit_chance, saving_throw  # noqa: E402
from crawler.dice import average, chance_to_hit, d20, dice_distribution, fmt, needed_roll, roll  # noqa: E402
from crawler.entities import (MONSTERS, PETS, init_mod, monster_table, new_pet, new_player,  # noqa: E402
                              spawn_monster, stat_block)

SEEDS = range(200)
STEPS_PER_SEED = 48
MULTS = [1, 1, 1, 1.5, 2, 3, 1.03, 0.5, 1.25, 2.5, 1.1, 0.7]


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


class CountingRandom(random.Random):
    """Counts 32-bit words, as scripts/py_trace.py does (random() = 2, getrandbits(k) = ceil(k/32))."""

    def __init__(self, x=None):
        self.words = 0
        super().__init__(x)

    def random(self):
        self.words += 2
        return super().random()

    def getrandbits(self, k):
        if k > 0:
            self.words += (k + 31) // 32
        return super().getrandbits(k)


def digest16(rng):
    st = rng.getstate()[1]
    text = str(st[624]) + "," + ",".join(str(v) for v in st[:624])
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


# --- entity specs --------------------------------------------------------------------------------
# A spec is [kind, key, [[field, value], ...]]: build with new_player / spawn_monster / new_pet,
# then set each field in order.

def build(spec):
    kind, key, sets = spec
    if kind == "player":
        e = new_player(0, 0)
    elif kind == "monster":
        e = spawn_monster(key, 0, 0)
    else:
        e = new_pet(key, "", 0, 0)
    for k, v in sets:
        setattr(e, k, v)
    return e


def player_spec(sr, depth):
    n = sr.choice([1, 1, 2])
    sets = [["level", depth * 2 - 1], ["attack", 2 + depth + sr.randint(0, 2)], ["ac", 10 + sr.randint(0, depth)],
            ["dmg_n", n], ["dmg_die", sr.choice([4, 6, 8, 10])], ["dmg_bonus", sr.randint(-1, 3 + depth // 2)],
            ["crit_range", sr.choice([1, 1, 1, 3, 4])]]
    mx = 20 + 8 * depth
    sets += [["max_hp", mx], ["hp", sr.randint(1, mx)]]
    if sr.random() < 0.15:
        sets.append(["dr", sr.randint(1, 3)])
    r = sr.random()
    if r < 0.03:
        sets.append(["attack", 100])
    elif r < 0.06:
        sets.append(["attack", -100])
    return ["player", "", sets]


def monster_spec(sr, key, depth):
    row = MONSTERS[key]
    sets = [["hp", sr.randint(1, row["hp"] + depth)]]
    if sr.random() < 0.3:
        sets.append(["dr", sr.randint(0, 3)])
    if sr.random() < 0.08:
        sets.append(["dr", 999])
    if sr.random() < 0.25:
        sets.append(["dmg_bonus", row["dmg"][2] + sr.randint(0, depth)])
    if sr.random() < 0.1:
        sets.append(["crit_range", sr.choice([2, 3, 5])])
    return ["monster", key, sets]


def pet_spec(sr, species, depth):
    sets = [["level", sr.randint(1, 4)], ["hp", sr.randint(1, PETS[species]["hp"])]]
    if sr.random() < 0.3:
        sets.append(["enraged", 3])
    return ["pet", species, sets]


def pick_pair(sr, i):
    """Attacker and defender specs. Monster kinds cycle so every kind appears at depths 1-6."""
    depth = sr.randint(1, 6)
    keys = list(MONSTERS)
    key = keys[(i + sr.randint(0, 7)) % len(keys)]
    r = sr.random()
    if r < 0.5:
        return player_spec(sr, depth), monster_spec(sr, key, depth)
    if r < 0.85:
        return monster_spec(sr, key, depth), player_spec(sr, depth)
    species = sr.choice(list(PETS))
    if sr.random() < 0.5:
        return pet_spec(sr, species, depth), monster_spec(sr, key, depth)
    return monster_spec(sr, key, depth), pet_spec(sr, species, depth)


# --- steps ---------------------------------------------------------------------------------------

def gen_step(sr, i):
    r = sr.random()
    if r < 0.40:
        a, d = pick_pair(sr, i)
        return ["attack", a, d, sr.choice(MULTS), sr.random() < 0.15, sr.choice([0, 0, 0, 1, 2, 3]),
                sr.choice([0, 0, 0, 1, 2, 4]), sr.choice([0, 0, 0, 1, -1, 2, -2])]
    if r < 0.50:
        return ["d20", sr.choice([0, 0, 1, -1, 2, -2])]
    if r < 0.60:
        return ["roll", sr.randint(0, 6), sr.choice([4, 6, 8, 10, 12, 20, 1])]
    if r < 0.68:
        return ["save", sr.randint(-3, 10), sr.randint(5, 22)]
    if r < 0.82:
        a, d = pick_pair(sr, i)
        return ["odds", a, d, sr.choice([0, 0, 1, -1]), sr.choice(MULTS), sr.choice([0, 0, 1, 2, 3])]
    if r < 0.90:
        if sr.random() < 0.5:
            spec = ["player", "", [["level", sr.randint(1, 9)], ["xp", sr.randint(0, 60)]]]
        else:
            spec = pet_spec(sr, sr.choice(list(PETS)), 1)
            spec[2] += [["xp", sr.randint(0, 60)], ["max_hp", PETS[spec[1]]["hp"]]]
        return ["xp", spec, sr.choice([0, 1, 29, 30, 70, 150, 400, 900, sr.randint(0, 700)])]
    if sr.random() < 0.5:
        spec = player_spec(sr, sr.randint(1, 6))
    elif sr.random() < 0.7:
        spec = monster_spec(sr, sr.choice(list(MONSTERS)), sr.randint(1, 6))
        if sr.random() < 0.3:
            tier = sr.choice(["headliner", "featured"])
            spec[2] += [["boss", True], ["tier", tier], ["base", spec[1]]]
            if tier == "headliner":
                spec[2].append(["key", "boss_%d" % sr.randint(1, 6)])
    else:
        spec = pet_spec(sr, sr.choice(list(PETS)), 1)
    return ["entity", spec, sr.randint(0, 40), sr.randint(0, 40)]


def run_step(rng, step):
    """Execute one step on `rng` and return the result list (before words / digest)."""
    kind = step[0]
    if kind == "d20":
        kept, rolls = d20(rng, step[1])
        return [kept, list(rolls)]
    if kind == "roll":
        return [roll(rng, step[1], step[2])]
    if kind == "save":
        saved, face = saving_throw(rng, step[1], step[2])
        return [saved, face]
    if kind == "attack":
        _, aspec, dspec, mult, sure, bonus, crit_bonus, adv = step
        a, d = build(aspec), build(dspec)
        res = attack(a, d, rng, mult=mult, sure=sure, bonus=bonus, crit_bonus=crit_bonus, advantage=adv)
        return [res.hit, res.crit, res.damage, res.killed, res.roll, res.total, res.target,
                res.natural or "", res.dice_text(), d.hp, d.alive]
    if kind == "odds":
        _, aspec, dspec, adv, mult, bonus = step
        a, d = build(aspec), build(dspec)
        return [hit_chance(a, d), hit_chance(a, d, adv), crit_chance(a), crit_chance(a, adv),
                expected_damage(a, d), expected_damage(a, d, mult, bonus)]
    if kind == "xp":
        e = build(step[1])
        gained = e.gain_xp(step[2])
        base = [list(gained), e.level, e.xp, e.xp_to_next()]
        if step[1][0] == "player":
            return base + [e.stat_points]
        return base + [e.max_hp, e.hp, e.attack, e.ac, e.dmg_bonus]
    if kind == "entity":
        e = build(step[1])
        out = [asdict(e), e.damage_text(), e.alive]
        if step[1][0] == "monster":
            out += [e.the, e.The, e.a, init_mod(e)]
        elif step[1][0] == "pet":
            out += [init_mod(e), e.xp_to_next()]
        else:
            out += [e.xp_to_next()]
        dealt = e.take_damage(step[2])
        out += [dealt, e.hp, e.alive]
        healed = e.heal(step[3])
        out += [healed, e.hp]
        return out
    raise ValueError(kind)


def seed_run(seed):
    sr = random.Random(seed * 1009 + 17)
    rng = CountingRandom(seed)
    steps = []
    for i in range(STEPS_PER_SEED):
        step = gen_step(sr, i)
        res = run_step(rng, step)
        steps.append(enc([step, res, rng.words, digest16(rng)]))
    return {"seed": seed, "steps": steps}


# --- tables --------------------------------------------------------------------------------------

def tables():
    out = {}
    out["dist"] = [[enc(n), enc(s), enc(dice_distribution(n, s))]
                   for n in range(0, 5) for s in (1, 4, 6, 8, 10, 12, 20)]
    cth = []
    for bonus in range(-6, 16):
        for target in range(6, 24):
            for cr in (1, 2, 3, 4, 5):
                for adv in (0, 1, -1):
                    cth.append([enc([bonus, target, cr, adv]), enc(chance_to_hit(bonus, target, cr, adv)),
                                enc(needed_roll(bonus, target))])
    out["chance_to_hit"] = cth
    out["average_fmt"] = [[enc([n, s, b]), enc(average(n, s, b)), enc(fmt(n, s, b))]
                         for n in range(0, 5) for s in (4, 6, 8, 10, 12, 20) for b in (-3, -1, 0, 1, 2, 5)]
    out["attrs"] = [[enc(s), enc(A.mod(s)), enc(A.fmt_mod(A.mod(s)))] for s in range(-5, 45)]
    out["proficiency"] = [[enc(lv), enc(A.proficiency(lv))] for lv in range(1, 40)]
    out["consts"] = enc([A.BASE_SCORE, A.START_POINTS, A.POINTS_PER_LEVEL, A.MAX_SCORE, list(A.ATTRS)])
    out["monster_table"] = [[enc(d), enc(monster_table(d))] for d in range(0, 9)]
    out["stat_blocks"] = [[enc(k), enc(stat_block(v))] for k, v in list(MONSTERS.items()) + list(PETS.items())]
    out["spawn"] = [[enc(["monster", k]), enc(spawn_monster(k, 3, 4).__dict__), enc(init_mod(spawn_monster(k, 3, 4)))]
                    for k in MONSTERS]
    out["pets"] = [[enc(k), enc(new_pet(k, "", 3, 4).__dict__), enc(new_pet(k, "Rex", 3, 4).__dict__),
                    enc(init_mod(new_pet(k, "", 0, 0)))] for k in PETS]
    out["player"] = enc(new_player(5, 6).__dict__)
    return out


def main():
    out = {"tables": tables(), "seeds": [seed_run(s) for s in SEEDS]}
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()

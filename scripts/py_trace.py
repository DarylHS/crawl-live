"""Python side of the parity traces (docs/port-plan.md section 6).

Runs the frozen Python game headless and writes a JSON Lines trace that the Godot
emitter (godot/tools/trace.gd) must reproduce.  Nothing in crawler/ is modified:
the tracer wraps crawler.world.EventBus / MessageLog / World.new_floor and swaps
random.Random for a word-counting subclass while the World is constructed, all
restored afterwards.

Usage:
  python scripts/py_trace.py --seed 5 --policy hunter --steps 3000 --out /tmp/py.jsonl
        [--pet cat|none] [--hero GENDER:BACKSTORY] [--no-msg]
  python scripts/py_trace.py --seeds 0-49 --policy walk --steps 500 --out-dir /tmp/py_walk
        (one file per seed: <policy>_<seed>.jsonl)
  python scripts/py_trace.py --seed 5 --floor-only --floors 6 --out f.jsonl
        (S3: generate_floor x6 from one rng(seed); per floor fp, words used, full dump)
  python scripts/py_trace.py --seed 5 --floor-only --spawns --floors 2 --out f.jsonl [--pet cat] [--hero GENDER:BACKSTORY]
        (World(seed, pet, hero) then new_floor(2..n); adds monsters, items, timers, player start)

Default output path when --out is omitted: ./trace_<seed>.jsonl.
Policies: walk, hunter, bot (see scripts/trace_policies.py).  --pet and --hero default
to none for walk/hunter (--pet none forces no pet) and to analysis.bot.run_config(seed) for bot.

Records (one JSON object per line, keys in this order; floats written with repr):
  header k impl trace_version seed policy steps pet hero content_sha mode
  ev     k i t d e p r            every EventBus.emit, pre-order; r = words used per stream
                                  [main, loot, shop, deal, show]
  turn   k t pos hp max_hp timer state gold viewers combat pet mon inv
  floor  k depth fp rs            (+ dump fields in --floor-only mode)
  act    k n a arg ok pr          pr = words used by the policy's own stream
  msg    k text c
  end    k state turn depth cause rs
Digest rules: see the functions state_digest, mon_string, floor_sections below.
"""
import argparse
import hashlib
import json
import random
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT))
sys.path.insert(0, str(ROOT / "scripts"))

import crawler.world as cw  # noqa: E402
from crawler import config as C  # noqa: E402
from crawler.dungeon import generate_floor  # noqa: E402
from crawler.events import EventBus  # noqa: E402

import trace_policies as TP  # noqa: E402

TRACE_VERSION = 1
_OrigRandom = random.Random


class CountingRandom(_OrigRandom):
    """random.Random that counts the 32-bit words it consumes.

    Overriding both random() (2 words) and getrandbits(k) (ceil(k / 32) words) keeps
    CPython's _randbelow_with_getrandbits in use, so every draw is unchanged."""
    registry = None                 # list that collects new instances while patched

    def __init__(self, x=None):
        self.words = 0
        super().__init__(x)
        if CountingRandom.registry is not None:
            CountingRandom.registry.append(self)

    def random(self):
        self.words += 2
        return super().random()

    def getrandbits(self, k):
        if k > 0:
            self.words += (k + 31) // 32
        return super().getrandbits(k)


def state_digest(rng):
    """sha256 hex of "index,w0,...,w623" (matches PyRandom.state_digest)."""
    st = rng.getstate()[1]
    text = str(st[624]) + "," + ",".join(str(v) for v in st[:624])
    return hashlib.sha256(text.encode("utf-8")).hexdigest()


def state_digest16(rng):
    return state_digest(rng)[:16]


def h16(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def _b(v):
    return "1" if v else "0"


def mon_string(monsters):
    """key:x:y:hp:max_hp:alerted:unseen_turns:stunned:phase:dmg_bonus per monster, joined by |."""
    return "|".join(f"{m.key}:{m.x}:{m.y}:{m.hp}:{m.max_hp}:{_b(m.alerted)}:{m.unseen_turns}:"
                    f"{m.stunned}:{m.phase}:{m.dmg_bonus}" for m in monsters)


def floor_sections(floor, items=None, monsters=None):
    """Sections joined by "#" for the fingerprint, in this order:
    tiles (all rows' digits concatenated), safe (0/1 likewise), rooms ("x,y,w,h" joined by ;
    in floor.rooms order), stairs ("x,y;..."), furniture ("x,y,kind;..." in insertion order),
    safe_door ("x,y" or "-"), then (world mode only) floor_items ("x,y:key,key;..." in insertion
    order) and monsters (mon_string)."""
    secs = [
        "".join(str(t) for row in floor.tiles for t in row),
        "".join(_b(s) for row in floor.safe for s in row),
        ";".join(f"{r.x},{r.y},{r.w},{r.h}" for r in floor.rooms),
        ";".join(f"{x},{y}" for x, y in floor.stairs),
        ";".join(f"{x},{y},{k}" for (x, y), k in floor.furniture.items()),
        "-" if floor.safe_door is None else f"{floor.safe_door[0]},{floor.safe_door[1]}",
    ]
    if items is not None:
        secs.append(";".join(f"{x},{y}:{','.join(v)}" for (x, y), v in items.items()))
        secs.append(mon_string(monsters))
    return secs


def floor_fp(floor, items=None, monsters=None):
    return h16("#".join(floor_sections(floor, items, monsters)))


def clean(v):
    if v is None or isinstance(v, (bool, int, float, str)):
        return v
    if isinstance(v, (list, tuple)):
        return [clean(x) for x in v]
    if isinstance(v, dict):
        return {str(k): clean(x) for k, x in v.items()}
    raise TypeError(f"cannot trace value {v!r} of type {type(v).__name__}")


class Tracer:
    def __init__(self, out, msgs=True, events=True, detail=False):
        self.out, self.msgs, self.events, self.detail = out, msgs, events, detail
        self.world = None
        self.rngs = []              # main, loot, shop, deal, show
        self.i = 0

    def write(self, rec):
        self.out.write(json.dumps(rec, ensure_ascii=False, separators=(",", ":")) + "\n")

    def words(self):
        return [r.words for r in self.rngs]

    def digests(self):
        return [state_digest16(r) for r in self.rngs]

    def on_event(self, name, data):
        w = self.world
        if self.events:
            self.i += 1
            self.write({"k": "ev", "i": self.i, "t": w.turn if w else 0, "d": w.depth if w else 0,
                        "e": name, "p": clean(data), "r": self.words()})
        if w is None:
            return
        if name == "turn" and self.events:
            p = w.player
            pet = w.pet
            self.write({"k": "turn", "t": w.turn, "pos": [p.x, p.y], "hp": p.hp, "max_hp": p.max_hp,
                        "timer": w.timer, "state": w.state, "gold": w.gold, "viewers": w.viewers,
                        "combat": w.combat.round if w.combat else None,
                        "pet": [pet.x, pet.y, pet.hp, pet.downed] if pet else None,
                        "mon": h16(mon_string(w.monsters)), "inv": list(w.inventory)})
        elif name == "floor_start":
            self.write_floor(w)

    def on_message(self, text, colour):
        if self.msgs:
            self.write({"k": "msg", "text": text, "c": clean(colour)})

    def write_floor(self, w):
        f = w.floor
        rec = {"k": "floor", "depth": w.depth,
               "fp": floor_fp(f, w.floor_items, w.monsters), "rs": self.digests()}
        if self.detail:
            rec.update(dump_floor(f))
            rec["player"] = [w.player.x, w.player.y]
            rec["timer"] = [w.timer, w.timer_max]
            rec["words"] = self.words()
            rec["monsters"] = [[m.key, m.x, m.y, m.hp, m.max_hp, m.alerted, m.unseen_turns,
                                m.stunned, m.phase, m.dmg_bonus, m.tier, m.boss] for m in w.monsters]
            rec["items"] = [[x, y, list(v)] for (x, y), v in w.floor_items.items()]
        self.write(rec)


def dump_floor(f):
    """Dungeon-only fields (tiles, rooms, stairs, safe room, furniture) as plain JSON."""
    return {"tiles": ["".join(str(t) for t in row) for row in f.tiles],
            "safe": ["".join(_b(s) for s in row) for row in f.safe],
            "rooms": [[r.x, r.y, r.w, r.h] for r in f.rooms],
            "start": list(f.start_room.centre),
            "safe_room": [f.safe_room.x, f.safe_room.y, f.safe_room.w, f.safe_room.h],
            "safe_door": list(f.safe_door) if f.safe_door else None,
            "stairs": [list(s) for s in f.stairs],
            "furniture": [[x, y, k] for (x, y), k in f.furniture.items()]}


class Patched:
    """Context manager: install the tracing hooks, restore everything on exit."""

    def __init__(self, tracer):
        self.t = tracer

    def __enter__(self):
        t = self.t
        self.saved = (cw.EventBus, cw.MessageLog, cw.World.new_floor, random.Random)

        class TracingEventBus(EventBus):
            def emit(self, name, **data):
                t.on_event(name, data)
                super().emit(name, **data)

        class TracingMessageLog(self.saved[1]):
            def add(self, text, colour=C.TEXT):
                t.on_message(text, colour)
                super().add(text, colour)

        orig_new_floor = self.saved[2]

        def new_floor(world, depth):
            if t.world is None:
                t.world = world
            return orig_new_floor(world, depth)

        cw.EventBus, cw.MessageLog, cw.World.new_floor = TracingEventBus, TracingMessageLog, new_floor
        CountingRandom.registry = t.rngs
        random.Random = CountingRandom
        return self

    def __exit__(self, *exc):
        cw.EventBus, cw.MessageLog, cw.World.new_floor, random.Random = self.saved
        CountingRandom.registry = None


def content_sha():
    return hashlib.sha256((ROOT / "godot" / "data" / "manifest.json").read_bytes()).hexdigest()


def header(seed, policy, steps, pet, hero, mode):
    return {"k": "header", "impl": "python", "trace_version": TRACE_VERSION, "seed": seed,
            "policy": policy, "steps": steps, "pet": pet, "hero": hero,
            "content_sha": content_sha(), "mode": mode}


MUTE = set()    # subsystems to silence (--mute): "achievements", "funfacts"; for runs against Godot stand-ins


def new_world(tracer, seed, pet, hero):
    with Patched(tracer):
        w = cw.World(seed, pet=(pet, "") if pet else None, hero=hero)
    if "achievements" in MUTE:
        w.achievements._unlock = lambda *a, **k: None
    if "funfacts" in MUTE:
        w.funfacts._say = lambda *a, **k: None
    assert len(tracer.rngs) == 5, f"expected 5 RNG streams, saw {len(tracer.rngs)}"
    return w


def run_trace(seed, policy, steps, out, pet=None, hero=None, msgs=True):
    """Play `steps` policy steps (fewer if the run ends) and write the trace to the open file `out`.
    Returns the World."""
    dpet, dhero = TP.default_setup(policy, seed)
    if pet == "none":
        pet = None
    elif pet is None:
        pet = dpet
    hero = hero if hero is not None else dhero
    tr = Tracer(out, msgs=msgs)
    tr.write(header(seed, policy, steps, pet, hero, "run"))
    w = new_world(tr, seed, pet, hero)
    prng = CountingRandom(TP.policy_seed(policy, seed))
    pol = TP.make_policy(policy, seed, prng)
    n = 0

    def do(action, arg):
        ok = TP.perform(w, action, arg)
        tr.write({"k": "act", "n": n, "a": action, "arg": clean(arg), "ok": ok, "pr": prng.words})
        return ok

    for n in range(steps):
        if w.state != "playing":
            break
        pol.step(w, do)
    tr.write({"k": "end", "state": w.state, "turn": w.turn, "depth": w.depth,
              "cause": w.death_cause, "rs": tr.digests()})
    return w


def run_floors(seed, floors, spawns, out, pet=None, hero=None):
    """Floor-only trace.  Without spawns: generate_floor(rng, d) for d in 1..floors from one rng(seed).
    With spawns: World(seed) then new_floor(2..floors); floor records carry monsters and items."""
    tr = Tracer(out, msgs=False, events=False, detail=True)
    if pet == "none":
        pet = None
    tr.write(header(seed, None, 0, pet if spawns else None, hero if spawns else None,
                    "floors_world" if spawns else "floors"))
    if spawns:
        w = new_world(tr, seed, pet, hero)
        for d in range(2, floors + 1):
            w.new_floor(d)
        return
    rng = CountingRandom(seed)
    for d in range(1, floors + 1):
        f = generate_floor(rng, d)
        rec = {"k": "floor", "depth": d, "fp": floor_fp(f), "words": rng.words,
               "rs": [state_digest16(rng)]}
        rec.update(dump_floor(f))
        tr.write(rec)


def parse_seeds(text):
    if "-" in text:
        a, b = text.split("-", 1)
        return list(range(int(a), int(b) + 1))
    return [int(text)]


def parse_hero(text):
    if text is None:
        return None
    gender, _, story = text.partition(":")
    return dict(name="Bot", gender=gender or None, backstory=story or None)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--seed", type=int)
    ap.add_argument("--seeds", help="range such as 0-49 (needs --out-dir)")
    ap.add_argument("--policy", choices=TP.POLICY_NAMES, default="hunter")
    ap.add_argument("--steps", type=int, default=500)
    ap.add_argument("--out")
    ap.add_argument("--out-dir")
    ap.add_argument("--pet")
    ap.add_argument("--hero", help="GENDER:BACKSTORY")
    ap.add_argument("--no-msg", action="store_true")
    ap.add_argument("--floor-only", action="store_true")
    ap.add_argument("--floors", type=int, default=6)
    ap.add_argument("--spawns", action="store_true")
    ap.add_argument("--mute", default="", help="comma list of achievements,funfacts: silence those real Python "
                    "subsystems (while the Godot side is still a stand-in); default none")
    a = ap.parse_args(argv)
    MUTE.update(x for x in a.mute.split(",") if x)
    seeds = parse_seeds(a.seeds) if a.seeds else [a.seed if a.seed is not None else 0]
    if a.seeds and not a.out_dir:
        ap.error("--seeds needs --out-dir")
    if a.out_dir:
        Path(a.out_dir).mkdir(parents=True, exist_ok=True)
    for seed in seeds:
        if a.out_dir:
            stem = "floors" if a.floor_only else a.policy
            path = Path(a.out_dir) / f"{stem}_{seed}.jsonl"
        else:
            path = Path(a.out or f"trace_{seed}.jsonl")
        with open(path, "w", encoding="utf-8", newline="\n") as fh:
            if a.floor_only:
                run_floors(seed, a.floors, a.spawns, fh, pet=a.pet, hero=parse_hero(a.hero))
            else:
                run_trace(seed, a.policy, a.steps, fh, pet=a.pet, hero=parse_hero(a.hero),
                          msgs=not a.no_msg)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()

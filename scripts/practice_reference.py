#!/usr/bin/env python3
"""Fixtures from real Python for the Godot Practice port (port plan 9.1, slice S5).

Usage: practice_reference.py out.json

Drives the real crawler.practice.Practice with a recording stand-in for the World (it needs only
events, messages, refresh_stats, add_toast and weapon_style) and writes the inputs and the exact
outputs: the XP curve for levels 0-40, every level-up of every skill (messages, toasts, events),
random gain sequences, random event scenarios (all 15 listeners, every payload shape) and load
round trips. godot/tests/test_practice.gd replays the same inputs and compares. Written into a temp
dir by scripts/gd_test.sh (PRACTICE_REF env var); not committed. Same encoding as make_fixtures.py.
"""
import json
import random
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))
sys.path.insert(0, str(Path(__file__).resolve().parent))

from crawler import config as C  # noqa: E402
from crawler.events import EventBus  # noqa: E402
from crawler.items import ITEMS  # noqa: E402
from crawler.practice import CARDIO_STEPS, MAX_LEVEL, SKILLS, Practice, xp_to_next  # noqa: E402
from make_fixtures import enc  # noqa: E402


class Messages:
    def __init__(self, log):
        self.log = log

    def add(self, text, colour=None):
        self.log.append(["msg", text, list(colour)])


class FakeWorld:
    def __init__(self):
        self.log = []
        self.style = "unarmed"
        self.events = EventBus()
        self.messages = Messages(self.log)
        self.events.subscribe("practice_level", lambda n, d: self.log.append(
            ["event", d["skill"], d["level"], d["title"], d["many_at_3"]]))

    def refresh_stats(self):
        self.log.append(["refresh"])

    def add_toast(self, text, tier):
        self.log.append(["toast", text, tier])

    def weapon_style(self):
        return self.style


def snapshot(p):
    return {"levels": dict(p.levels), "xp": dict(p.xp), "used": sorted(p.used), "steps": p.steps}


def curve():
    return [[enc(n), enc(xp_to_next(n))] for n in range(0, 41)]


def every_level_up():
    """Per skill: gain exactly the needed XP one level at a time, to the cap and past it."""
    out = []
    for key in SKILLS:
        w = FakeWorld()
        p = Practice(w)
        amounts = []
        steps = []
        for n in range(MAX_LEVEL + 2):
            a = xp_to_next(min(n, 40))
            amounts.append(a)
            p.gain(key, a)
            steps.append([p.level(key), p.xp[key], len(w.log)])
        out.append([enc(key), enc(amounts), enc(steps), enc(w.log), enc(snapshot(p))])
    return out


def gain_sequences(rng):
    """Random amounts (including 0 and negatives) across random skills, one world each."""
    out = []
    keys = list(SKILLS)
    for i in range(30):
        w = FakeWorld()
        p = Practice(w)
        seq = []
        steps = []
        for _ in range(rng.randint(1, 60)):
            key = rng.choice(keys)
            amount = rng.choice([-3, 0, 1, 1, 1, 2, 2, 3, 5, 8, 13, 40, 100, 500, 10_000])
            seq.append([key, amount])
            p.gain(key, amount)
            steps.append(len(w.log))
        out.append([enc(seq), enc(steps), enc(w.log), enc(snapshot(p))])
    return out


def rand_event(rng):
    name = rng.choice(["player_attack", "player_attack", "kill", "damage_taken", "dodged", "bomb", "item_use", "rest",
                       "step", "step", "step", "item_pickup", "shop_buy", "shop_sell", "box_opened", "craft",
                       "viewers_gained", "pet_hit", "unrelated"])
    style = rng.choice(["unarmed", "blade", "blunt"])
    d = {}
    if name == "player_attack":
        d["hit"] = rng.random() < 0.7
        d["crit"] = rng.random() < 0.2
        for k in ("boss", "small"):
            r = rng.random()
            if r < 0.3:
                d[k] = rng.random() < 0.5
            elif r < 0.4:
                d[k] = None
    elif name == "kill":
        r = rng.random()
        if r < 0.5:
            d["by"] = rng.choice(["melee", "bomb", "pet", "ranged"])
        elif r < 0.6:
            d["by"] = None
        if rng.random() < 0.6:
            d["small"] = rng.random() < 0.5
    elif name == "damage_taken":
        d["hp"] = rng.randint(-3, 20)
    elif name == "bomb":
        if rng.random() < 0.7:
            d["kills"] = rng.randint(0, 6)
    elif name == "item_use":
        d["item"] = rng.choice(list(ITEMS))
    elif name == "rest":
        d["turns"] = rng.choice([0, 1, 9, 10, 11, 19, 20, 60, 99, 100, 150, 400])
    elif name == "step":
        if rng.random() < 0.5:
            d["sneaky"] = rng.random() < 0.5
    elif name == "viewers_gained":
        d["amount"] = rng.choice([0, 1, 39, 40, 41, 79, 80, 120, 399, 400, 1000])
    return [name, d, style]


def event_scenarios(rng):
    out = []
    for i in range(8):
        w = FakeWorld()
        p = Practice(w)
        evs = []
        snaps = []
        n = [300, 800, 2000, 4000, 4000, 6000, 6000, 6000][i]
        for j in range(n):
            ev = rand_event(rng)
            evs.append(ev)
            w.style = ev[2]
            w.events.emit(ev[0], **ev[1])
            if j % 25 == 24 or j == n - 1:
                snaps.append([j, len(w.log), p.steps, sum(p.levels.values()), sum(p.xp.values())])
        out.append([enc(evs), enc(snaps), enc(w.log), enc(snapshot(p))])
    # Cardio: exactly 3 * CARDIO_STEPS steps, and the sneaking flag.
    w = FakeWorld()
    p = Practice(w)
    evs = [["step", {"sneaky": j % 3 == 0}, "unarmed"] for j in range(CARDIO_STEPS * 3 + 5)]
    for e in evs:
        w.events.emit(e[0], **e[1])
    out.append([enc(evs), enc([]), enc(w.log), enc(snapshot(p))])
    return out


def load_cases():
    out = []
    full = {k: 0 for k in SKILLS}
    cases = [
        dict(levels={}, xp={}, used=[], steps=0),
        dict(levels={"haggling": 3, "stomping": 15}, xp={"haggling": 5}, used=["stomping", "haggling", "cardio"], steps=77),
        dict(levels={**full, "retired_skill": 4}, xp={**full, "retired_skill": 9}, used=[], steps=5),
        dict(levels={k: i % 16 for i, k in enumerate(SKILLS)}, xp={k: i for i, k in enumerate(SKILLS)},
             used=list(reversed(list(SKILLS))), steps=12345),
    ]
    for d in cases:
        w = FakeWorld()
        p = Practice(w)
        p.load(d)
        out.append([enc(d), enc(p.to_dict()), enc(list(p.levels)), enc(list(p.xp))])
    w = FakeWorld()
    p = Practice(w)
    p.gain("scavenging", 30)
    p.gain("first_aid", 3)
    q = Practice(FakeWorld())
    q.load(json.loads(json.dumps(p.to_dict())))
    out.append([enc(p.to_dict()), enc(q.to_dict()), enc(list(q.levels)), enc(list(q.xp))])
    return out


def main():
    rng = random.Random(20260102)
    out = {
        "constants": [enc(MAX_LEVEL), enc(CARDIO_STEPS), enc(list(SKILLS))],
        "curve": curve(),
        "level_ups": every_level_up(),
        "gains": gain_sequences(rng),
        "events": event_scenarios(rng),
        "load": load_cases(),
        "accent": enc(list(C.ACCENT)),
    }
    with open(sys.argv[1], "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, separators=(",", ":"))


if __name__ == "__main__":
    main()

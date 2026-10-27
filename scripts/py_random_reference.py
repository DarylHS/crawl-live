#!/usr/bin/env python3
"""Emit reference output of CPython's random.Random for godot/tools/check_py_random.gd.

Usage: py_random_reference.py [out.json]   (default: stdout)

Encoding (JSON numbers are doubles in Godot, so nothing numeric is a JSON number):
  int   -> decimal string
  float -> "f:" + 16 hex digits of the IEEE-754 bits
  None  -> null
Each seed has {"seed": str, "calls": [{"op":..., "args":{...}, "res":...}]}.
"""
import json
import random
import struct
import sys

SEEDS = [0, 1, 2, 42, 123456789, 2**31 - 1, 2**32, 2**32 + 1, 2**40 + 5, 2**63 - 1, -7]
for s in range(21):
    SEEDS += [s ^ 0x100F, s ^ 0x5A0F, s ^ 0xC0DE, s ^ 0x5EED, s * 7919 + 13]


def F(x):
    if isinstance(x, float):
        return "f:%016x" % struct.unpack(">Q", struct.pack(">d", x))[0]
    return str(x)


def words(v, k):
    n = max(1, (k + 31) // 32)
    return [str((v >> (32 * i)) & 0xFFFFFFFF) for i in range(n)]


def gen(seed):
    r = random.Random(seed)
    calls = []

    def add(op, args, res):
        calls.append({"op": op, "args": args, "res": res})

    def rnd():
        add("random", {}, F(r.random()))

    def grb(k):
        add("getrandbits", {"k": str(k)}, words(r.getrandbits(k), k))

    def randint(a, b):
        add("randint", {"a": str(a), "b": str(b)}, str(r.randint(a, b)))

    def randrange(start, stop=None, step=1):
        if stop is None:
            res = r.randrange(start)
            add("randrange", {"start": str(start), "stop": None, "step": "1"}, str(res))
        else:
            res = r.randrange(start, stop, step)
            add("randrange", {"start": str(start), "stop": str(stop), "step": str(step)}, str(res))

    def choice(seq):
        add("choice", {"seq": [str(x) for x in seq]}, str(r.choice(seq)))

    def shuffle(n, mul=1):
        x = [i * mul + 1 for i in range(n)]
        r.shuffle(x)
        add("shuffle", {"n": str(n), "mul": str(mul)}, [str(v) for v in x])

    def sample(n, k):
        pop = [i * 3 + 1 for i in range(n)]
        add("sample", {"n": str(n), "k": str(k)}, [str(v) for v in r.sample(pop, k)])

    def choices(n, weights=None, cum=None, k=1):
        pop = [i * 5 + 2 for i in range(n)]
        res = r.choices(pop, weights, cum_weights=cum, k=k)
        add("choices", {"n": str(n), "k": str(k),
                        "weights": None if weights is None else [F(w) for w in weights],
                        "cum": None if cum is None else [F(w) for w in cum]},
            [str(v) for v in res])

    def uniform(a, b):
        add("uniform", {"a": F(a), "b": F(b)}, F(r.uniform(a, b)))

    for _ in range(3):
        rnd()
    for k in (1, 5, 31, 32, 33, 64, 100, 0, 63, 17, 96, 128):
        grb(k)
    for a, b in [(0, 1), (1, 6), (0, 99), (-5, 5), (1, 1000000), (0, 2**31), (0, 2**32 - 1), (-2**40, 2**40),
                 (0, 2**62 - 2), (5, 5), (0, 255), (0, 256), (10, 2**33 + 7)]:
        randint(a, b)
    randrange(10)
    randrange(1 << 30)
    randrange(1)
    randrange(3, 9)
    randrange(0, 100, 7)
    randrange(100, 0, -3)
    randrange(-10, 10, 4)
    randrange(0, 2**40, 2**20 + 1)
    choice([7])
    choice(list(range(10)))
    choice([i * 11 for i in range(100)])
    shuffle(10)
    shuffle(52, 7)
    shuffle(1)
    shuffle(2)
    shuffle(200)
    # sample: pool algorithm vs set algorithm. setsize=21 (k<=5) or 21+4**ceil(log(3k,4)).
    for n, k in [(10, 3), (10, 10), (10, 0), (21, 5), (22, 5), (22, 1), (30, 5), (50, 5), (22, 6), (27, 6),
                 (45, 6), (85, 6), (86, 6), (100, 6), (100, 10), (100, 50), (277, 21), (278, 22), (500, 20),
                 (1000, 20), (1000, 300), (2000, 5), (21, 21), (3, 2), (1, 1)]:
        sample(n, k)
    for _ in range(40):
        grb(1)
    rnd()
    # choices
    choices(5)
    choices(5, k=10)
    choices(1, k=3)
    choices(4, [1, 2, 3, 4])
    choices(4, [6, 3, 1, 0], k=8)
    choices(3, [6, 3, 1])
    choices(5, [0.5, 1.5, 2.25, 0.125, 7.0], k=12)
    choices(5, [1, 2.5, 3, 0.5, 4], k=12)
    choices(4, cum=[1, 3, 6, 10], k=6)
    choices(4, cum=[0.1, 0.4, 0.9, 1.0], k=6)
    choices(6, [100, 1, 1, 1, 1, 100], k=30)
    choices(10, [i + 1 for i in range(10)], k=50)
    uniform(0.0, 1.0)
    uniform(-3.5, 8.25)
    uniform(10.0, 10.0)
    uniform(1e6, 1e-3)
    # state snapshot mid-stream, continue, restore, replay
    snap = r.getstate()
    add("snapshot", {}, [str(v) for v in snap[1]])
    for _ in range(5):
        rnd()
    randint(0, 1000)
    shuffle(12)
    sample(60, 8)
    choices(5, [1, 2, 3, 4, 5], k=4)
    r.setstate(snap)
    add("restore", {}, None)
    for _ in range(5):
        rnd()
    randint(0, 1000)
    shuffle(12)
    sample(60, 8)
    choices(5, [1, 2, 3, 4, 5], k=4)
    # setstate from a foreign Python state (layout check, index != 624 / == 624)
    other = random.Random(seed ^ 0x1234567)
    for _ in range(seed % 7 + 1):
        other.random()
    st = other.getstate()
    r.setstate(st)
    add("setstate", {"state": [str(v) for v in st[1]]}, None)
    for _ in range(30):
        rnd()
    # long stream crossing several regenerations
    for _ in range(1300):
        add("random", {}, F(r.random()))
    add("getstate_end", {}, [str(v) for v in r.getstate()[1]])
    return {"seed": str(seed), "calls": calls}


def main():
    out = {"python": sys.version.split()[0], "seeds": [gen(s) for s in SEEDS]}
    txt = json.dumps(out, separators=(",", ":"))
    if len(sys.argv) > 1:
        with open(sys.argv[1], "w") as f:
            f.write(txt)
    else:
        sys.stdout.write(txt)


if __name__ == "__main__":
    main()

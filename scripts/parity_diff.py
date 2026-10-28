"""Compare two parity traces (docs/port-plan.md 6.3) and report the first divergence.

Usage:
  python scripts/parity_diff.py A.jsonl B.jsonl [--scope core|full] [--context 12]
  python scripts/parity_diff.py --dirs DIR_A DIR_B [--seeds 0-49] [--scope core|full]

Exit code 0 when identical ("PARITY OK: <n> records, <turns> turns"), 1 on the first
difference (or any file pair differing in --dirs mode, or a file missing on one side).

Comparison: records are read in order and compared field by field.  Ints compare
exactly, an int against a float or two floats by value, bools only against bools,
strings exactly, dict keys as a set (order ignored), lists elementwise.
The header's "impl" is never compared.

--scope core ignores: msg records, the "i" counter of ev records, the show counter
(index 4 of "r", "rs" and the floor records' "words"), "viewers" in turn
records, and events of systems that are still stubbed (achievement, box_gained,
viewers_gained, sponsor_gift, fun_fact).  Because the stubbed Showrunner never emits
viewers_gained, Python also trains Showmanship (it only affects viewer gains), so core also drops
practice_level events whose skill is "showmanship" and ignores the many_at_3 field of the other
practice_level events.  --scope full compares everything (strict).

On a difference it prints the record index, the turn and depth, the field path, both
values, the RNG word-counter delta when "r" is involved, and the last --context records
of both sides, side by side.

--dirs mode compares files of the same name in both directories; --seeds A-B restricts
to names ending in _<seed>.jsonl with seed in the range (e.g. hunter_17.jsonl).
"""
import argparse
import json
import re
import sys
from collections import deque
from pathlib import Path

CORE_SKIP_EVENTS = {"achievement", "box_gained", "viewers_gained", "sponsor_gift", "fun_fact"}


class Result:
    def __init__(self):
        self.ok = True
        self.records = 0
        self.turns = 0
        self.report = ""


class TraceFileError(Exception):
    pass


def read_records(path):
    try:
        with open(path, encoding="utf-8") as fh:
            for no, line in enumerate(fh, 1):
                line = line.strip()
                if line:
                    try:
                        yield json.loads(line)
                    except json.JSONDecodeError as e:
                        raise TraceFileError(f"file {path} line {no} malformed ({e.msg})")
    except OSError as e:
        raise TraceFileError(f"file {path} missing or unreadable ({e.strerror})")


def _num(x):
    return isinstance(x, (int, float)) and not isinstance(x, bool)


def values_equal(a, b):
    """Value equality with the trace rules; returns (equal, path suffix of first difference)."""
    if isinstance(a, bool) or isinstance(b, bool):
        return (isinstance(a, bool) and isinstance(b, bool) and a == b), ""
    if _num(a) and _num(b):
        if isinstance(a, int) and isinstance(b, int):
            return a == b, ""
        return float(a) == float(b), ""
    if isinstance(a, dict) and isinstance(b, dict):
        for k in a:
            if k not in b:
                return False, f".{k}(missing in B)"
        for k in b:
            if k not in a:
                return False, f".{k}(missing in A)"
        for k in a:
            eq, sub = values_equal(a[k], b[k])
            if not eq:
                return False, f".{k}{sub}"
        return True, ""
    if isinstance(a, list) and isinstance(b, list):
        if len(a) != len(b):
            return False, f"(length {len(a)} vs {len(b)})"
        for i, (x, y) in enumerate(zip(a, b)):
            eq, sub = values_equal(x, y)
            if not eq:
                return False, f"[{i}]{sub}"
        return True, ""
    return (type(a) is type(b) and a == b), ""


def normalise(rec, scope):
    """Copy of rec with the fields --scope core ignores removed; None to skip the record."""
    if scope == "full":
        return rec
    k = rec.get("k")
    if k == "msg":
        return None
    if k == "ev" and rec.get("e") in CORE_SKIP_EVENTS:
        return None
    if k == "ev" and rec.get("e") == "practice_level":
        p = rec.get("p")
        if isinstance(p, dict):
            if p.get("skill") == "showmanship":
                return None
            rec = dict(rec)
            rec["p"] = {a: b for a, b in p.items() if a != "many_at_3"}
    rec = dict(rec)
    if k == "ev":
        rec.pop("i", None)
    if k == "turn":
        rec.pop("viewers", None)
    for key in ("r", "rs", "words"):
        if isinstance(rec.get(key), list) and len(rec[key]) >= 5:
            rec[key] = rec[key][:4] + rec[key][5:]
    return rec


def short(rec, width=160):
    text = json.dumps(rec, ensure_ascii=False, separators=(",", ":")) if rec is not None else "<end of file>"
    return text if len(text) <= width else text[:width - 3] + "..."


def compare_files(path_a, path_b, scope="full", context=12):
    try:
        return _compare_files(path_a, path_b, scope, context)
    except TraceFileError as e:
        res = Result()
        res.ok = False
        res.report = f"PARITY FAIL: {e}"
        return res


def _compare_files(path_a, path_b, scope, context):
    res = Result()
    ra = (normalise(r, scope) for r in read_records(path_a))
    rb = (normalise(r, scope) for r in read_records(path_b))
    ra = (r for r in ra if r is not None)
    rb = (r for r in rb if r is not None)
    hist_a, hist_b = deque(maxlen=context), deque(maxlen=context)
    last_r = [None, None]
    turn = depth = None
    n = 0
    while True:
        a, b = next(ra, None), next(rb, None)
        if a is None and b is None:
            break
        if a is not None and a.get("k") == "header" and b is not None and b.get("k") == "header":
            a, b = dict(a), dict(b)
            a.pop("impl", None)
            b.pop("impl", None)
        eq, sub = (False, "(one trace ended early)") if a is None or b is None else values_equal(a, b)
        if not eq:
            res.ok = False
            res.report = _report(n, turn, depth, a, b, sub, hist_a, hist_b, path_a, path_b, last_r)
            break
        n += 1
        res.records = n
        if a["k"] == "turn":
            res.turns += 1
        if "t" in a:
            turn = a["t"]
        if a["k"] == "ev":
            depth = a.get("d")
        elif a["k"] == "floor":
            depth = a.get("depth")
        if a["k"] == "ev":
            last_r = [a.get("r"), b.get("r")]
        hist_a.append(a)
        hist_b.append(b)
    if res.ok:
        res.report = f"PARITY OK: {res.records} records, {res.turns} turns"
    return res


def _report(n, turn, depth, a, b, sub, hist_a, hist_b, path_a, path_b, last_r):
    out = [f"PARITY FAIL at record {n} (after turn {turn}, depth {depth})",
           f"  A = {path_a}", f"  B = {path_b}"]
    ka = a.get("k") if a else None
    kb = b.get("k") if b else None
    if a is not None and b is not None and ka == kb:
        field = sub
        out.append(f"  record kind: {ka}; differing field path: {field or '(value)'}")
        for rec_a, rec_b in ((a, b),):
            va, vb = _lookup(rec_a, field), _lookup(rec_b, field)
            out.append(f"  A value: {json.dumps(va, ensure_ascii=False)}")
            out.append(f"  B value: {json.dumps(vb, ensure_ascii=False)}")
        if field.startswith(".r[") and isinstance(a.get("r"), list) and isinstance(b.get("r"), list):
            delta = [y - x if _num(x) and _num(y) else None for x, y in zip(a["r"], b["r"])]
            out.append(f"  RNG word delta (B - A) per stream [main, loot, shop, deal, show]: {delta}"
                       " (an extra or missing draw just before this event)")
        elif "r" in a and "r" in b and field != "":
            ok_r, _ = values_equal(a["r"], b["r"])
            if not ok_r:
                out.append(f"  note: RNG counters also differ: A {a['r']} B {b['r']}")
    else:
        out.append(f"  record kind differs or a trace ended early: A {ka}, B {kb} {sub}")
    if not sub.startswith(".r[") and last_r[0] is not None:
        out.append(f"  last ev RNG counters before this point: A {last_r[0]} B {last_r[1]}")
    out.append("  context (last records, A | B), then the differing pair:")
    for ra, rb in zip(hist_a, hist_b):
        if values_equal(ra, rb)[0]:
            out.append(f"    = {short(ra, 110)}")
        else:
            out.append(f"    A {short(ra, 110)}")
            out.append(f"    B {short(rb, 110)}")
    out.append(f"    A> {short(a)}")
    out.append(f"    B> {short(b)}")
    return "\n".join(out)


def _lookup(rec, path):
    """Value at a path such as .p.damage or .r[2] (best effort, for display)."""
    cur = rec
    for key, idx in re.findall(r"\.([A-Za-z_0-9]+)|\[(\d+)\]", path):
        try:
            cur = cur[key] if key else cur[int(idx)]
        except (KeyError, IndexError, TypeError):
            return None
    return cur if path else rec


def in_range(name, lo, hi):
    m = re.search(r"_(\d+)\.jsonl$", name)
    return bool(m) and lo <= int(m.group(1)) <= hi


def compare_dirs(dir_a, dir_b, seeds=None, scope="full", context=12):
    names_a = sorted(p.name for p in Path(dir_a).glob("*.jsonl"))
    names_b = sorted(p.name for p in Path(dir_b).glob("*.jsonl"))
    names = sorted(set(names_a) | set(names_b))
    if seeds:
        lo, hi = seeds
        names = [n for n in names if in_range(n, lo, hi)]
    failures, lines = 0, []
    for name in names:
        pa, pb = Path(dir_a) / name, Path(dir_b) / name
        if not pa.exists() or not pb.exists():
            failures += 1
            lines.append(f"{name}: MISSING in {'A' if not pa.exists() else 'B'}")
            continue
        r = compare_files(pa, pb, scope, context)
        if r.ok:
            lines.append(f"{name}: {r.report}")
        else:
            failures += 1
            lines.append(f"{name}: FAIL\n{r.report}")
    lines.append(f"{len(names) - failures}/{len(names)} traces identical")
    return failures == 0 and bool(names), "\n".join(lines)


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("files", nargs="*")
    ap.add_argument("--dirs", nargs=2, metavar=("DIR_A", "DIR_B"))
    ap.add_argument("--seeds", help="range such as 0-49 (with --dirs)")
    ap.add_argument("--scope", choices=("core", "full"), default="full")
    ap.add_argument("--context", type=int, default=12)
    a = ap.parse_args(argv)
    if a.dirs:
        seeds = None
        if a.seeds:
            lo, _, hi = a.seeds.partition("-")
            seeds = (int(lo), int(hi or lo))
        ok, text = compare_dirs(a.dirs[0], a.dirs[1], seeds, a.scope, a.context)
        print(text)
        return 0 if ok else 1
    if len(a.files) != 2:
        ap.error("give two trace files, or --dirs DIR_A DIR_B")
    r = compare_files(a.files[0], a.files[1], a.scope, a.context)
    print(r.report)
    return 0 if r.ok else 1


if __name__ == "__main__":
    sys.exit(main())

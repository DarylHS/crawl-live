"""Compare save/load parity runs from scripts/save_trace.py (Python) and godot/tools/save_trace.gd (Godot).

    python scripts/save_diff.py PY_DIR GD_DIR --seeds 0-99

For each seed (a skip_<seed> marker on either side means no save point: both must agree) checks, as bytes:
  save     save_<seed>.json is identical in both directories (acceptance d: byte-identical saves)
  traces   direct_<seed>, loaded_<seed> and xload_<seed> (when present) of both sides are all identical to
           PY_DIR/direct_<seed>.jsonl, which covers (a) a save/load/continue round trip equals continuing without
           saving, in each language and across them, (b) a Python save loaded in Godot, and (c) a Godot save
           loaded in Python.
Prints one line per differing item, with the first differing line number of a trace, then a summary line
"SAVE PARITY OK ..." or "SAVE PARITY FAILED ...". Exit 0 only when everything matches; --save-bytes-optional
turns a byte difference between the save files into a note instead of a failure (the traces still must match).
"""
import argparse
import sys
from pathlib import Path


def seeds_arg(text):
    lo, _, hi = text.partition("-")
    return list(range(int(lo), int(hi or lo) + 1))


def first_diff(a, b):
    la, lb = a.splitlines(), b.splitlines()
    for i, (x, y) in enumerate(zip(la, lb)):
        if x != y:
            return i + 1, x[:200], y[:200]
    return min(len(la), len(lb)) + 1, "<%d lines>" % len(la), "<%d lines>" % len(lb)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("py_dir")
    ap.add_argument("gd_dir")
    ap.add_argument("--seeds", required=True)
    ap.add_argument("--save-bytes-optional", action="store_true")
    a = ap.parse_args()
    py, gd = Path(a.py_dir), Path(a.gd_dir)
    bad = 0
    notes = 0
    compared = 0
    saves = 0
    skipped = 0
    kinds = {"direct": 0, "loaded": 0, "xload": 0}
    for seed in seeds_arg(a.seeds):
        sk = ((py / f"skip_{seed}").exists(), (gd / f"skip_{seed}").exists())
        if sk[0] or sk[1]:
            if sk[0] != sk[1]:
                print(f"seed {seed}: save point on one side only (py skip={sk[0]}, gd skip={sk[1]})")
                bad += 1
            else:
                skipped += 1
            continue
        ref = (py / f"direct_{seed}.jsonl").read_text()
        sp, sg = (py / f"save_{seed}.json").read_bytes(), (gd / f"save_{seed}.json").read_bytes()
        if sp == sg:
            saves += 1
        else:
            i = next((k for k in range(min(len(sp), len(sg))) if sp[k] != sg[k]), min(len(sp), len(sg)))
            msg = f"seed {seed}: save files differ at byte {i}: py {sp[i - 20:i + 40]!r} gd {sg[i - 20:i + 40]!r}"
            if a.save_bytes_optional:
                notes += 1
            else:
                bad += 1
            print(msg)
        for d, label in ((py, "py"), (gd, "gd")):
            for kind in ("direct", "loaded", "xload"):
                f = d / f"{kind}_{seed}.jsonl"
                if not f.exists():
                    if kind != "xload":
                        print(f"seed {seed}: missing {label} {kind}")
                        bad += 1
                    continue
                text = f.read_text()
                compared += 1
                kinds[kind] += 1
                if text != ref:
                    n, x, y = first_diff(ref, text)
                    print(f"seed {seed}: {label} {kind} differs from py direct at line {n}\n  py direct: {x}\n  {label} {kind}: {y}")
                    bad += 1
    word = "OK" if bad == 0 else "FAILED"
    print(f"SAVE PARITY {word}: {compared} traces compared (direct {kinds['direct']}, loaded {kinds['loaded']}, "
          f"cross-loaded {kinds['xload']}), {saves} save files byte-identical, {notes} byte differences noted, "
          f"{skipped} seeds without a save point, {bad} problems")
    sys.exit(1 if bad else 0)


if __name__ == "__main__":
    main()

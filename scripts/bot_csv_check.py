#!/usr/bin/env python3
"""Byte-compare Godot bot CSVs with the committed Python ones, run by run (slice T6).

  python scripts/bot_csv_check.py GD_DIR [--ref runs] [--seeds 0-99]

For each of bot_{runs,floors,boxes,shop,practice}.csv the header line and every row whose run_id is
bot<seed:05d> for a seed in the range must be identical, byte for byte (CRLF included), in both files.
The reference may hold more runs than the range (the committed files hold 0-1999); the Godot directory
must hold exactly the range.  Exit 0 prints "BOT CSV OK: ...".
"""
import argparse
import sys
from pathlib import Path

TABLES = ("runs", "floors", "boxes", "shop", "practice")


def rows_for(path, lo, hi):
    """(header, rows) of the lines whose run id is in [lo, hi]; rows keep file order."""
    data = path.read_bytes()
    lines = data.split(b"\r\n")
    if lines and lines[-1] == b"":
        lines.pop()
    header, rows = lines[0], []
    for line in lines[1:]:
        run_id = line.split(b",", 1)[0]
        if run_id.startswith(b"bot") and lo <= int(run_id[3:]) <= hi:
            rows.append(line)
    return header, rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("gd_dir")
    ap.add_argument("--ref", default="runs")
    ap.add_argument("--seeds", default="0-99")
    a = ap.parse_args()
    lo, _, hi = a.seeds.partition("-")
    lo, hi = int(lo), int(hi or lo)
    ok = True
    total = 0
    for t in TABLES:
        ref, gd = Path(a.ref) / f"bot_{t}.csv", Path(a.gd_dir) / f"bot_{t}.csv"
        if not gd.exists():
            print(f"{t}: missing {gd}")
            ok = False
            continue
        rh, rr = rows_for(ref, lo, hi)
        gh, gr = rows_for(gd, lo, hi)
        n_gd = gd.read_bytes().count(b"\r\n") - 1
        if rh != gh:
            print(f"{t}: header differs\n  ref {rh!r}\n  gd  {gh!r}")
            ok = False
        elif len(rr) != len(gr) or n_gd != len(gr):
            print(f"{t}: row counts differ: ref {len(rr)}, gd {len(gr)} (gd file has {n_gd} rows)")
            ok = False
        else:
            bad = next((i for i, (x, y) in enumerate(zip(rr, gr)) if x != y), None)
            if bad is not None:
                print(f"{t}: first differing row {bad + 1}\n  ref {rr[bad]!r}\n  gd  {gr[bad]!r}")
                ok = False
            else:
                print(f"{t}: {len(gr)} rows identical")
                total += len(gr)
    if ok:
        print(f"BOT CSV OK: seeds {lo}-{hi}, {total} rows in {len(TABLES)} files")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())

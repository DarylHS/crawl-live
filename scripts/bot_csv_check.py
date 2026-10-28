#!/usr/bin/env python3
"""Byte-compare Godot bot CSVs with the committed Python ones, run by run (slice T6).

  python scripts/bot_csv_check.py GD_DIR [--ref runs] [--seeds 0-99]

For each of bot_{runs,floors,boxes,shop,practice}.csv the header line and every row whose run_id is
bot<seed:05d> for a seed in the range must be identical, byte for byte (CRLF included, quoted newlines handled), in both files.
The reference may hold more runs than the range (the committed files hold 0-1999); the Godot directory
must hold exactly the range.  Exit 0 prints "BOT CSV OK: ...".
"""
import argparse
import csv
import io
import sys
from pathlib import Path

TABLES = ("runs", "floors", "boxes", "shop", "practice")


def rows_for(path, lo, hi):
    """(header, rows, total) of a CSV file: the header row, the rows whose run_id is bot<seed> for a seed
    in [lo, hi] (as lists of cells, file order) and the number of data rows in the whole file.  A missing
    file is (None, [], 0): a table with no rows in the range legitimately has none."""
    if not path.exists():
        return None, [], 0
    with path.open(newline="", encoding="utf-8") as fh:
        table = list(csv.reader(fh))
    if not table:
        return None, [], 0
    header, rows = table[0], []
    for row in table[1:]:
        if row[0].startswith("bot") and lo <= int(row[0][3:]) <= hi:
            rows.append(row)
    return header, rows, len(table) - 1




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
        rh, rr, _ = rows_for(ref, lo, hi)
        gh, gr, n_gd = rows_for(gd, lo, hi)
        if not rr and not gr and n_gd == 0:
            print(f"{t}: no rows in the range on either side")
        elif rh != gh:
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
                # Equal cells; the files must also be byte-identical, so compare the raw bytes of the rows.
                raw_ok = _raw_rows(gd, lo, hi) == _raw_rows(ref, lo, hi)
                print(f"{t}: {len(gr)} rows identical" + ("" if raw_ok else " as cells, BYTES DIFFER"))
                ok = ok and raw_ok
                total += len(gr)
    if ok:
        print(f"BOT CSV OK: seeds {lo}-{hi}, {total} rows in {len(TABLES)} files")
    return 0 if ok else 1


def _raw_rows(path, lo, hi):
    """Raw bytes of the header and in-range rows (rows cut at the CRLF that ends a record)."""
    with path.open(newline="", encoding="utf-8") as fh:
        text = fh.read()
    records, cur, quoted = [], [], False
    start = 0
    for i, ch in enumerate(text):
        if ch == '"':
            quoted = not quoted
        elif ch == "\n" and not quoted:
            records.append(text[start:i + 1])
            start = i + 1
    out = [records[0]]
    for rec in records[1:]:
        rid = rec.split(",", 1)[0]
        if rid.startswith("bot") and lo <= int(rid[3:]) <= hi:
            out.append(rec)
    return out


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Run the Godot bot in parallel worker processes and merge the shards into runs/-style CSVs (plan 8.4).

  python scripts/gd_bot.py --runs 2000 --workers 4 --out runs_gd [--start 0] [--deals random]
                           [--pet cat] [--no-events] [--summary-only] [--chunk 10] [--keep-shards]

Seeds start .. start+runs-1 are cut into chunks of --chunk seeds; each chunk is one `godot --headless
-s res://tools/bot.gd` process writing its own shard directory (bot.gd with --start N appends, so a shard
directory starts empty).  Workers take chunks from a queue; when all are done the shards are merged in seed
order into --out: one header per file (the first non-empty shard supplies it, later shards' headers are
dropped, shards whose runs had an empty table have no such file), old bot_*.csv deleted only when --start is 0,
otherwise rows append.  The events table is written unless --no-events (the committed runs/bot_*.csv were made with it).
Prints the same summary as analysis/bot.py.  Environment: GODOT (binary, default godot).
"""
import argparse
import json
import os
import shutil
import subprocess
import sys
import tempfile
import time
from collections import Counter
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TABLES = ("runs", "floors", "boxes", "shop", "practice", "events")


def run_chunk(job):
    """Run one shard; returns (index, shard_dir, summaries)."""
    index, start, count, shard, args = job
    shard.mkdir(parents=True, exist_ok=True)
    cmd = [os.environ.get("GODOT", "godot"), "--headless", "--path", str(ROOT / "godot"),
           "-s", "res://tools/bot.gd", "--", "--runs", str(count), "--start", str(start),
           "--runs-dir", str(shard), "--deals", args.deals, "--summary-out", str(shard / "summary.jsonl")]
    if args.pet:
        cmd += ["--pet", args.pet]
    if args.no_events:
        cmd.append("--no-events")
    if args.summary_only:
        cmd.append("--summary-only")
    r = subprocess.run(cmd, capture_output=True, text=True)
    summaries = []
    sfile = shard / "summary.jsonl"
    if sfile.exists():
        summaries = [json.loads(line) for line in sfile.read_text().splitlines() if line]
    bad = r.returncode != 0 or len(summaries) != count or "SCRIPT ERROR" in r.stdout + r.stderr
    if bad:
        raise RuntimeError(f"shard {index} (seeds {start}-{start + count - 1}) failed (exit {r.returncode}, "
                           f"{len(summaries)} of {count} summaries):\n{r.stdout[-2000:]}{r.stderr[-2000:]}")
    return index, shard, summaries


def merge(shards, out, start, tables):
    """Append the shard CSVs to out in shard order with exactly one header per file."""
    out.mkdir(parents=True, exist_ok=True)
    if start == 0:
        for t in TABLES:                    # a fresh generation replaces the old data
            if (out / f"bot_{t}.csv").exists():
                (out / f"bot_{t}.csv").unlink()
    for t in tables:
        path = out / f"bot_{t}.csv"
        have_header = path.exists() and path.stat().st_size > 0
        with path.open("ab") as fh:
            for shard in shards:
                src = shard / f"bot_{t}.csv"
                if not src.exists():        # every run of the shard had an empty table
                    continue
                data = src.read_bytes()
                if not data:
                    continue
                if have_header:
                    data = data.split(b"\r\n", 1)[1]
                have_header = True
                fh.write(data)
        if path.exists() and path.stat().st_size == 0:
            path.unlink()


def report(summaries, secs, workers):
    n = len(summaries)
    print(f"{n} runs in {secs:.0f}s with {workers} workers")
    if not n:
        return
    for k, v in sorted(Counter(s["outcome"] for s in summaries).items()):
        print(f"  {k:22s} {v:5d} ({v / n:.0%})")
    for key in ("pet", "backstory", "race", "cls"):
        groups = Counter(s[key] for s in summaries if s[key])
        wins = Counter(s[key] for s in summaries if s[key] and s["won"])
        print(f"  win rate by {key}: " + ", ".join(f"{g} {wins[g] / c:.0%} of {c}"
                                                  for g, c in sorted(groups.items())))
    med = lambda xs: sorted(xs)[len(xs) // 2]
    print(f"  median viewers {med([s['viewers'] for s in summaries]):,}, gold "
          f"{med([s['gold'] for s in summaries])}, boxes {med([s['boxes'] for s in summaries])}")
    means = {k: sum(s["skills"][k] for s in summaries) / n for k in summaries[0]["skills"]}
    print("  mean practice level: " + ", ".join(f"{k} {v:.1f}" for k, v in
                                                sorted(means.items(), key=lambda kv: -kv[1])))


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawTextHelpFormatter)
    ap.add_argument("--runs", type=int, default=200)
    ap.add_argument("--start", type=int, default=0, help="first seed")
    ap.add_argument("--workers", type=int, default=4)
    ap.add_argument("--pet", help="force one companion (cat, dog, budgie, mouse, none)")
    ap.add_argument("--deals", choices=("random", "accept", "decline"), default="random")
    ap.add_argument("--out", default="runs_gd")
    ap.add_argument("--chunk", type=int, default=10, help="seeds per worker process")
    ap.add_argument("--summary-only", action="store_true", help="don't write CSVs")
    ap.add_argument("--no-events", action="store_true", help="skip the large events table")
    ap.add_argument("--keep-shards", action="store_true")
    args = ap.parse_args()

    godot = os.environ.get("GODOT", "godot")
    subprocess.run([godot, "--headless", "--path", str(ROOT / "godot"), "--import"],
                   capture_output=True, check=False)
    work = Path(tempfile.mkdtemp(prefix="gd_bot."))
    jobs = []
    for i, s in enumerate(range(args.start, args.start + args.runs, args.chunk)):
        count = min(args.chunk, args.start + args.runs - s)
        jobs.append((i, s, count, work / f"shard_{i:05d}", args))
    t0 = time.time()
    done = {}
    try:
        with ThreadPoolExecutor(max_workers=args.workers) as pool:
            for index, shard, summaries in pool.map(run_chunk, jobs):
                done[index] = (shard, summaries)
                print(f"  shard {index + 1}/{len(jobs)} done", file=sys.stderr, flush=True)
        ordered = [done[i] for i in sorted(done)]
        if not args.summary_only:
            tables = [t for t in TABLES if not (t == "events" and args.no_events)]
            merge([s for s, _ in ordered], Path(args.out), args.start, tables)
        summaries = [x for _, ss in ordered for x in ss]
        report(summaries, time.time() - t0, args.workers)
    finally:
        if args.keep_shards:
            print(f"shards kept in {work}")
        else:
            shutil.rmtree(work, ignore_errors=True)


if __name__ == "__main__":
    main()

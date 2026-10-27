#!/usr/bin/env python3
"""FOV and distance-map fixtures from real Python for godot/tests/test_dungeon_parity.gd (slice S3).

Usage: make_dungeon_fixtures.py out.json [--seeds 0-5] [--depths 3]

For each seed, floors 1..depths are generated from one random.Random(seed) (as py_trace.py --floor-only
does), then for a spread of origins (start, safe room centre and door, stairs, other room centres, random
walkable tiles, a wall tile, a corner) it records:
  fov:  [ox, oy, radius, count, sha16 of the visibility bitmap]  for several radii
  dist: [sx, sy, max_dist (-1 = None), avoid_safe (0/1), reachable count, max distance, sha16 of the
         comma-joined flat list]
The bitmap is height rows of width '0'/'1' characters concatenated. Plain JSON numbers (the Godot test
converts floats to ints). scripts/gd_test.sh writes the file into a temp dir (DUNGEON_FIXTURES); not committed.
"""
import argparse
import hashlib
import json
import random
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from crawler import config as C  # noqa: E402
from crawler.dungeon import compute_fov, generate_floor  # noqa: E402

RADII = (C.FOV_RADIUS, 1, 2, 3, 5, 12)
MAX_DISTS = (None, 0, 1, 5, 12, 40)


def h16(text):
    return hashlib.sha256(text.encode("utf-8")).hexdigest()[:16]


def origins(floor, rng):
    pts = [floor.start_room.centre, floor.safe_room.centre, floor.safe_door, *floor.stairs]
    pts += [r.centre for r in floor.rooms[:6]]
    walk = [(x, y) for y in range(floor.height) for x in range(floor.width) if floor.walkable(x, y)]
    pts += [rng.choice(walk) for _ in range(6)]
    wall = [(x, y) for y in range(1, floor.height - 1) for x in range(1, floor.width - 1)
            if not floor.walkable(x, y)]
    pts += [rng.choice(wall), (0, 0), (floor.width - 1, floor.height - 1)]
    return [tuple(p) for p in pts]


def fov_row(floor, ox, oy, radius):
    vis = compute_fov(floor, ox, oy, radius)
    bitmap = "".join("1" if (x, y) in vis else "0" for y in range(floor.height) for x in range(floor.width))
    return [ox, oy, radius, len(vis), h16(bitmap)]


def dist_row(floor, sx, sy, max_dist, avoid_safe):
    d = floor.distance_map(sx, sy, max_dist, avoid_safe)
    return [sx, sy, -1 if max_dist is None else max_dist, int(avoid_safe),
            sum(1 for v in d if v >= 0), max(d), h16(",".join(map(str, d)))]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("--seeds", default="0-5")
    ap.add_argument("--depths", type=int, default=3)
    a = ap.parse_args()
    lo, _, hi = a.seeds.partition("-")
    hi = hi or lo
    floors = []
    for seed in range(int(lo), int(hi) + 1):
        rng = random.Random(seed)
        pick = random.Random(seed * 31 + 7)
        for depth in range(1, a.depths + 1):
            f = generate_floor(rng, depth)
            pts = origins(f, pick)
            fov = [fov_row(f, ox, oy, r) for ox, oy in pts for r in RADII]
            dist = []
            for i, (sx, sy) in enumerate(pts):
                for avoid in (False, True):
                    for md in MAX_DISTS if i < 8 else (None, 12):
                        dist.append(dist_row(f, sx, sy, md, avoid))
            floors.append({"seed": seed, "depth": depth, "fov": fov, "dist": dist})
    Path(a.out).write_text(json.dumps({"floors": floors}), encoding="utf-8")


if __name__ == "__main__":
    main()

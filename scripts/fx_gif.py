#!/usr/bin/env python3
"""Turn the frame sequences of godot/tools/fx_shots.gd into animated GIFs (needs Pillow).

    python3 scripts/fx_gif.py DIR [--scale 0.5]

For every <effect>_NN.png sequence in DIR it writes <effect>.gif at 20 frames a second (the frames are 0.05 s
of game time apart), cropped to the 1024 x 640 game view and scaled down.
"""
import argparse
import re
from collections import defaultdict
from pathlib import Path

from PIL import Image


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("dir")
    ap.add_argument("--scale", type=float, default=0.5)
    args = ap.parse_args()
    groups = defaultdict(list)
    for p in sorted(Path(args.dir).glob("*_[0-9][0-9].png")):
        m = re.match(r"(.+)_(\d\d)\.png$", p.name)
        if m:
            groups[m.group(1)].append(p)
    for name, files in groups.items():
        frames = []
        for f in files:
            im = Image.open(f).convert("RGB").crop((0, 0, 1024, 640))
            im = im.resize((int(1024 * args.scale), int(640 * args.scale)), Image.NEAREST)
            frames.append(im)
        out = Path(args.dir) / f"{name}.gif"
        frames[0].save(out, save_all=True, append_images=frames[1:], duration=50, loop=0, optimize=False)
        print(f"{out} ({len(frames)} frames)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

#!/usr/bin/env python3
"""Build the committed P9 art (godot/assets/) from Dungeon Crawl Stone Soup tiles plus fill-in art.

    git clone --depth 1 https://github.com/crawl/tiles.git /tmp/crawl-p9/src/tiles   # NOT into the repo
    python3 scripts/art_build.py --src /tmp/crawl-p9/src/tiles --out godot/assets [--sheet /tmp/crawl-p9/sheets]

Reads DCSS tiles from <src>/releases/Nov-2015, cleans them to the art bible's sprite rules (binary
alpha, trimmed, feet on the bottom row, one pixel transparent border, shared palette), draws the fill-in
art in code (props, overlays, junk items, ceilings, stairs), and writes:

    godot/assets/manifest.json     key -> file, origin ("dcss", "dcss+fill-in", "fill-in"), source, licence
    godot/assets/CREDITS.md        generated from the manifest (do not edit by hand)
    godot/assets/sprites/...  textures/...  tiles/...  ui/boxes/...

It refuses to use any tile listed in the export's TILES_UNDER_UNKNOWN_LICENSE.md. The original download stays
outside the repo; only the edited PNGs are committed. Re-running overwrites the outputs deterministically
(no random numbers except seeded ones). Swapping art never touches game code: the game reads manifest.json
through SpriteArt (godot/ui/art/sprite_art.gd).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
from collections import OrderedDict

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import art_pipeline as ap  # noqa: E402
from art_pipeline import Canvas  # noqa: E402

LICENCE = "CC0 1.0 (https://creativecommons.org/publicdomain/zero/1.0/)"
SOURCE_URL = "https://github.com/crawl/tiles"
ROOT = "releases/Nov-2015"

MANIFEST: "OrderedDict[str, dict]" = OrderedDict()
EXCLUDED: set[str] = set()
USED_SOURCES: set[str] = set()
OUT = ""
SRC = ""


# --- Plumbing ----------------------------------------------------------------------------------

def load_excluded(src: str) -> set[str]:
    """Basenames and paths from the export's list of tiles with unclear licensing (never to be used)."""
    text = open(os.path.join(src, "TILES_UNDER_UNKNOWN_LICENSE.md"), encoding="utf-8").read()
    out = set()
    for m in re.finditer(r"^\s*[-\t ]*([\w./\-]+\.png)\s*$", text, re.M):
        out.add(m.group(1).split("/")[-1])
    return out


def dcss(rel: str) -> np.ndarray:
    base = os.path.basename(rel)
    if base in EXCLUDED:
        raise SystemExit("refusing to use %s: listed in TILES_UNDER_UNKNOWN_LICENSE.md" % rel)
    path = os.path.join(SRC, ROOT, rel)
    if not os.path.exists(path):
        raise SystemExit("missing DCSS tile %s" % path)
    USED_SOURCES.add(rel)
    return np.array(Image.open(path).convert("RGBA"))


def save(rel: str, arr: np.ndarray) -> None:
    path = os.path.join(OUT, rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(arr, "RGBA").save(path, optimize=True)


def register(key: str, rel: str, origin: str, sources: list[str], note: str = "") -> None:
    MANIFEST[key] = {
        "file": rel,
        "origin": origin,
        "source": ["%s/%s/%s" % (SOURCE_URL, ROOT, s) for s in sources],
        "licence": LICENCE if sources else "original fill-in art for Crawl Live!, CC0 1.0",
    }
    if note:
        MANIFEST[key]["note"] = note


def sprite(key: str, rel: str, arr: np.ndarray, origin: str, sources: list[str], note: str = "") -> None:
    arr = ap.snap(ap.binary_alpha(arr))
    save(rel, arr)
    register(key, rel, origin, sources, note)


def prep(rel: str, hue: tuple[int, int, int] | None = None, light: float = 1.0, speck: bool = False,
         item: bool = False, desat: float = 1.0) -> np.ndarray:
    """A DCSS sprite cleaned and anchored: binary alpha, optional hue match, trimmed and fitted to 32.
    Creatures lose DCSS's black outline and shadow (the game draws its own); items lose the soft
    shadow (partial alpha) but keep their black outline, which snaps to the palette's near-black."""
    a = ap.binary_alpha(dcss(rel), 250 if item else 128)
    a = ap.strip_exterior_black(a)
    if item:                                               # our own outline, hugging the object (no shadow blob)
        a = ap.keep_largest_blob(a)
        a = Canvas(34, 34, base=np.pad(a, ((1, 1), (1, 1), (0, 0)))).a
        a = ap.outline_rect(a)
    if speck:
        a = ap.keep_largest_blob(a)
    if hue is not None:
        a = ap.hue_match(a, hue)
    if desat != 1.0:
        a = ap.desaturate(a, desat)
    if light != 1.0:
        a = ap.lighten(a, light)
    return ap.fit(a, 32)


def over(base: np.ndarray, painter, clip: bool = False) -> np.ndarray:
    """Draw fill-in props over a sprite. `painter(canvas, box)` gets the sprite's bbox (x0,y0,x1,y1)."""
    c = Canvas(base=base)
    painter(c, ap.bbox(base))
    return c.a


def head_cx(a: np.ndarray, b: tuple[int, int, int, int]) -> int:
    ys, xs = np.where(a[b[1]:b[1] + 4, :, 3] > 0)
    return int(round(xs.mean())) if len(xs) else (b[0] + b[2]) // 2


# --- Prop painters (palette colours; positions follow the sprite's bounding box) -----------------

GOLD = (255, 196, 64)
GOLD_D = (190, 130, 40)
YELLOW_HAT = (255, 232, 150)
DARK = (14, 12, 18)
WHITE = (240, 240, 240)
HIVIS = (255, 140, 40)
PAPER = (225, 222, 235)
WOOD = (150, 100, 60)


def p_hard_hat(c: Canvas, b) -> None:
    cx = head_cx(c.a, b)
    top = b[1]
    c.ellipse(cx - 5, top - 1, 11, 6, (255, 196, 64))
    c.rect(cx - 6, top + 3, 13, 2, (255, 196, 64))
    c.rect(cx - 6, top + 4, 13, 1, GOLD_D)
    c.px(cx - 2, top, (255, 232, 150))
    c.px(cx - 1, top, (255, 232, 150))


def p_crown(c: Canvas, b) -> None:
    cx = head_cx(c.a, b)
    top = b[1]
    c.rect(cx - 4, top, 9, 3, GOLD)
    for dx in (-4, 0, 4):
        c.px(cx + dx, top - 1, GOLD)
        c.px(cx + dx, top - 2, (255, 232, 150))
    c.rect(cx - 4, top + 2, 9, 1, GOLD_D)
    c.px(cx, top + 1, (235, 80, 80))


def p_glasses(c: Canvas, b) -> None:
    cx = head_cx(c.a, b)
    y = b[1] + 4
    for dx in (-3, 1):
        c.rect(cx + dx, y, 3, 3, DARK)
        c.px(cx + dx + 1, y + 1, (170, 210, 255))
    c.px(cx, y + 1, DARK)


def p_books(c: Canvas, b) -> None:
    x = min(b[2] - 1, 28) - 8
    y = b[3]
    for i, col in enumerate([(148, 40, 48), (66, 104, 186), (88, 150, 64)]):
        c.rect(x + (i % 2), y - 2 - i * 2, 9, 2, col)
        c.rect(x + (i % 2), y - 2 - i * 2, 9, 1, tuple(min(255, int(v * 1.25)) for v in col))
        c.px(x + 1 + (i % 2), y - 2 - i * 2, PAPER)


def p_hivis(c: Canvas, b) -> None:
    """A hi-vis vest: the torso's colours replaced by orange, with two reflective stripes."""
    h = b[3] - b[1]
    y0, y1 = b[1] + int(h * 0.38), b[1] + int(h * 0.72)
    for y in range(y0, y1 + 1):
        for x in range(b[0], b[2] + 1):
            if c.a[y, x, 3] and abs(x - (b[0] + b[2]) / 2.0) < (b[2] - b[0]) * 0.28:
                c.px(x, y, HIVIS if (y - y0) % 4 else (255, 232, 150))
    for y in (y0 + 2, y1 - 1):
        for x in range(b[0], b[2] + 1):
            if c.a[y, x, 3] and c.a[y, x, 0] == HIVIS[0] and c.a[y, x, 1] == HIVIS[1]:
                c.px(x, y, (240, 240, 240))


def p_horns(c: Canvas, b) -> None:
    cx = head_cx(c.a, b)
    top = b[1]
    for s in (-1, 1):
        c.px(cx + s * 3, top, (244, 214, 172))
        c.px(cx + s * 4, top - 1, (244, 214, 172))
        c.px(cx + s * 4, top - 2, (224, 178, 128))
        c.px(cx + s * 5, top - 3, (244, 214, 172))


def p_staff(c: Canvas, b) -> None:
    x = min(b[2] + 2, 30)
    c.line(x, b[1] + 1, x, b[3], (150, 100, 60))
    c.ellipse(x - 2, b[1] - 2, 5, 5, (190, 90, 210))
    c.px(x - 1, b[1] - 1, (240, 240, 240))


def p_wrap(c: Canvas, b) -> None:
    """Cling film: pale diagonal streaks, only over the body."""
    body = c.a.copy()
    h = b[3] - b[1]
    for k in range(-h, 40, 6):
        for i in range(h + 2):
            x, y = b[0] + k + i, b[3] - i
            if 0 <= x < 32 and 0 <= y < 32 and body[y, x, 3]:
                c.px(x, y, (200, 214, 236) if i % 5 else (240, 240, 240))
    for y in range(b[1] + 1, b[1] + 4):
        for x in range(b[0] + 2, b[0] + 6):
            if body[y, x, 3]:
                c.px(x, y, (255, 255, 255))


def p_tie_headset(c: Canvas, b) -> None:
    cx = head_cx(c.a, b)
    h = b[3] - b[1]
    y0 = b[1] + max(5, int(h * 0.3))
    for i in range(5):                                       # a gold tie shows on Glorm's red
        c.px(cx, y0 + i, (255, 196, 64))
    c.px(cx - 1, y0, (255, 232, 150))
    c.px(cx + 1, y0, (255, 232, 150))
    c.px(cx, y0 + 5, (190, 130, 40))
    c.px(cx - 1, y0 + 4, (190, 130, 40))
    c.px(cx + 1, y0 + 4, (190, 130, 40))
    top = b[1]
    for dx in range(-5, 6):                                  # headset band over the head
        c.px(cx + dx, top + (1 if abs(dx) < 4 else 3), DARK)
    c.line(cx + 5, top + 3, cx + 6, top + 7, DARK)
    c.px(cx + 6, top + 8, (110, 210, 120))                   # mic


def p_clipboard(c: Canvas, b) -> None:
    x = min(b[2], 28) - 3
    y = b[1] + int((b[3] - b[1]) * 0.45)
    c.rect(x, y, 5, 7, (150, 100, 60))
    c.rect(x + 1, y + 1, 3, 5, PAPER)
    c.px(x + 2, y, GOLD)
    c.px(x + 2, y + 2, DARK)
    c.px(x + 3, y + 4, DARK)


def p_logo_tee(c: Canvas, b) -> None:
    cx = (b[0] + b[2]) // 2
    y = b[1] + int((b[3] - b[1]) * 0.48)
    c.rect(cx - 1, y, 3, 3, GOLD)
    c.px(cx, y + 1, (235, 80, 80))


def p_googly(c: Canvas, b) -> None:
    for x in (11, 18):
        c.rect(x, 13, 4, 4, WHITE)
        c.px(x + 2, 15, DARK)


def p_rim(a: np.ndarray, colour) -> np.ndarray:
    return ap.rim_light(a, colour)


# --- Creature specs ----------------------------------------------------------------------------

def build_creatures() -> None:
    G = (120, 190, 80)
    specs = [
        # key, file, source, kwargs, painters, origin, note
        ("mon:gnawer", "sprites/monsters/gnawer.png", "mon/animals/quokka.png", {}, []),
        ("mon:goblin", "sprites/monsters/goblin.png", "mon/goblin.png", {"hue": G}, [p_logo_tee]),
        ("mon:skeleton", "sprites/monsters/skeleton.png", "mon/undead/skeletons/skeleton_humanoid_small.png", {}, [p_clipboard]),
        ("mon:brute", "sprites/monsters/brute.png", "mon/ogre.png", {}, [p_hard_hat]),
        ("mon:cultist", "sprites/monsters/cultist.png", "mon/necromancer.png", {"hue": (190, 90, 210)}, []),
        ("mon:golem", "sprites/monsters/golem.png", "mon/nonliving/flesh_golem.png", {}, []),
        ("mon:stalker", "sprites/monsters/stalker.png", "mon/undead/shadow_wraith.png", {"light": 1.35}, "rim"),
        ("pet:cat", "sprites/pets/cat.png", "player/felids/cat9.png", {}, []),
        ("pet:dog", "sprites/pets/dog.png", "mon/animals/jackal.png", {}, []),
                ("pet:mouse", "sprites/pets/mouse.png", "UNUSED/monsters/labrat_unseen.png", {"hue": (190, 180, 200), "desat": 0.45}, []),
        ("boss:boss_1", "sprites/headliners/boss_1.png", "mon/unique/royal_jelly.png", {}, [p_crown]),
        ("boss:boss_2", "sprites/headliners/boss_2.png", "mon/unique/jessica.png", {}, [p_glasses, p_books]),
        ("boss:boss_3", "sprites/headliners/boss_3.png", "mon/unique/iron_giant.png", {"light": 1.15}, [p_hard_hat, p_hivis]),
        ("boss:boss_4", "sprites/headliners/boss_4.png", "mon/unique/erica.png", {}, [p_horns, p_staff]),
        ("boss:boss_5", "sprites/headliners/boss_5.png", "mon/nonliving/guardian_golem.png", {}, [p_wrap]),
        ("boss:boss_6", "sprites/headliners/boss_6.png", "mon/demons/balrug.png", {}, [p_tie_headset]),
    ]
    for key, rel, src, kw, painters in specs:
        a = prep(src, **kw)
        origin = "dcss"
        note = ""
        if painters == "rim":
            a = p_rim(a, (170, 210, 255))        # lighter rim: the stalker must read on floor 5's blue
            origin, note = "dcss+fill-in", "lighter rim for contrast on floor 5"
        elif painters == "budgie":
            a = over(a, lambda c, b: (c.px(b[0] + 6, b[1] + 4, (255, 232, 150)),
                                      c.px(b[0] + 7, b[1] + 4, (255, 232, 150))))
            origin, note = "dcss+fill-in", "recoloured raven"
        elif painters:
            for p in painters:
                a = over(a, p)
            a = ap.fit(a, 32)                          # props may stick out: shift and trim back inside the border
            origin, note = "dcss+fill-in", "comedy props drawn over the DCSS body"
        sprite(key, rel, a, origin, [src], note)
    sprite("pet:budgie", "sprites/pets/budgie.png", ap.fit(draw_budgie(), 32), "fill-in", [],
           "no DCSS match; drawn in code")
    # the vacuum bot has no DCSS match at all: full fill-in
    sprite("mon:vacbot", "sprites/monsters/vacbot.png", ap.fit(draw_vacbot(), 32), "fill-in", [],
           "no DCSS match; drawn in code")
    # Act overlays (composited over the base monster by SpriteArt, clipped to the body)
    sprite("fx:badge_opening", "sprites/acts/badge_opening.png", draw_badge(), "fill-in", [])
    sprite("fx:sash_featured", "sprites/acts/sash_featured.png", draw_sash(), "fill-in", [])


def draw_vacbot() -> np.ndarray:
    c = Canvas()
    shell, dark, light = (150, 166, 194), (60, 70, 92), (200, 214, 236)
    c.ellipse(3, 19, 26, 11, dark)
    c.ellipse(3, 14, 26, 14, shell)
    c.ellipse(6, 14, 20, 5, light)
    c.rect(4, 26, 24, 2, dark)
    c.rect(7, 28, 4, 2, (24, 22, 30))
    c.rect(21, 28, 4, 2, (24, 22, 30))
    c.rect(14, 8, 4, 6, dark)                        # sensor stalk
    c.rect(13, 6, 6, 3, shell)
    c.ellipse(9, 16, 6, 6, WHITE)                    # googly eyes: the comedy prop
    c.ellipse(18, 16, 6, 6, WHITE)
    c.rect(11, 19, 2, 2, DARK)
    c.rect(20, 18, 2, 2, DARK)
    c.rect(15, 24, 3, 2, (235, 80, 80))              # angry status light
    c.line(3, 24, 1, 27, (150, 100, 60))             # side brush
    return c.a


def draw_budgie() -> np.ndarray:
    c = Canvas()
    green, dk, lt = (110, 210, 120), (52, 100, 60), (176, 226, 140)
    c.ellipse(9, 10, 14, 15, dk)                           # body
    c.ellipse(10, 10, 12, 14, green)
    c.ellipse(11, 12, 6, 8, lt)
    c.polygon([(10, 11), (6, 20), (12, 24)], dk)           # wing
    c.polygon([(21, 11), (26, 20), (20, 24)], dk)
    c.ellipse(11, 3, 10, 9, (255, 232, 150))                # yellow head
    c.px(13, 6, DARK); c.px(18, 6, DARK)                    # eyes
    c.rect(15, 7, 3, 2, (255, 140, 40))                    # beak
    c.rect(12, 8, 1, 1, (66, 104, 186)); c.rect(19, 8, 1, 1, (66, 104, 186))   # cheek spots
    c.polygon([(13, 24), (19, 24), (17, 31), (15, 31)], (66, 104, 186))        # tail
    c.line(13, 24, 13, 27, (255, 140, 40)); c.line(18, 24, 18, 27, (255, 140, 40))
    return c.a


def draw_badge() -> np.ndarray:
    """A lanyard and ID badge (blue), 12 x 16; SpriteArt places it on the chest."""
    c = Canvas(12, 16)
    c.line(2, 0, 6, 6, DARK)
    c.line(10, 0, 6, 6, DARK)
    c.line(3, 0, 6, 5, (110, 170, 240))
    c.line(9, 0, 6, 5, (110, 170, 240))
    c.rect(2, 6, 8, 9, DARK)
    c.rect(3, 7, 6, 7, (240, 240, 240))
    c.rect(3, 7, 6, 2, (110, 170, 240))
    c.rect(4, 10, 4, 1, DARK)
    c.rect(4, 12, 3, 1, DARK)
    return c.a


def draw_sash() -> np.ndarray:
    """A diagonal gold sash with a star, 20 x 20; SpriteArt clips it to the body."""
    c = Canvas(20, 20)
    for k in range(4):
        c.line(2 + k, 0, 19, 17 - k, GOLD if k < 3 else GOLD_D)
    c.px(9, 8, (240, 240, 240))
    c.px(8, 9, (240, 240, 240))
    c.px(10, 9, (240, 240, 240))
    c.px(9, 10, (240, 240, 240))
    c.px(9, 9, (235, 80, 80))
    return c.a


# --- Player (one per race) ---------------------------------------------------------------------

def build_players() -> None:
    def layered(base: str, layers: list[str], hue=None, light=1.0) -> tuple[np.ndarray, list[str]]:
        a = ap.binary_alpha(dcss(base))
        a = ap.strip_exterior_black(a)
        used = [base]
        c = Canvas(base=a)
        for l in layers:
            layer = ap.binary_alpha(dcss(l))
            if "shirt_blue" in l:                             # the contestant's blue, not the palette's nearest purple
                layer = ap.hue_match(layer, (66, 104, 186), min_sat=0.05)
            c.paste(layer)
            used.append(l)
        a = ap.desaturate(c.a, 0.7)
        if hue:
            a = ap.hue_match(a, hue)
        if light != 1.0:
            a = ap.lighten(a, light)
        return ap.fit(a, 32), used

    outfit = ["player/legs/pants_brown.png", "player/body/shirt_blue.png", "player/boots/middle_brown.png"]
    specs = {
        "human": ("player/base/human_m.png", outfit + ["player/hair/brown1.png"], None),
        "elf": ("player/base/elf_m.png", ["player/legs/pants_black.png", "player/body/robe_green.png",
                                          "player/boots/middle_gray.png", "player/hair/elf_black.png"], None),
        "dwarf": ("player/base/dwarf_m.png", ["player/legs/pants_short_brown.png", "player/body/leather_short.png",
                                              "player/boots/middle_brown.png", "player/head/helm_red.png"], None),
        "hobgoblin": ("mon/hobgoblin.png", [], None),
        "bog_troll": ("mon/deep_troll.png", [], (88, 150, 64)),
        "houseplant": ("mon/fungi_plants/thorn_hunter.png", [], None),
    }
    for race, (base, layers, hue) in specs.items():
        a, used = layered(base, layers, hue)
        origin = "dcss"
        sprite("player:" + race, "sprites/player/%s.png" % race, a, origin, used,
               "paper doll: base plus outfit layers" if layers else "")
    a, used = layered("player/base/human_f.png", outfit + ["player/hair/fem_red.png"])
    sprite("player:crawler", "sprites/player/crawler.png", a, "dcss", used, "before a race is chosen")


# --- Items -------------------------------------------------------------------------------------

def p_pan() -> np.ndarray:
    c = Canvas()
    c.ellipse(4, 4, 18, 18, DARK)
    c.ellipse(5, 5, 16, 16, (100, 114, 140))
    c.ellipse(7, 7, 12, 12, (60, 70, 92))
    c.rect(8, 8, 3, 2, (150, 166, 194))
    c.line(20, 20, 29, 28, DARK, 3)
    c.line(20, 20, 28, 27, (150, 100, 60), 1)
    c.px(28, 28, (150, 100, 60))
    return c.a


def p_extinguisher() -> np.ndarray:
    c = Canvas()
    c.rect(10, 9, 12, 20, DARK)
    c.rect(11, 10, 10, 18, (235, 80, 80))
    c.rect(11, 10, 3, 18, (255, 140, 120))
    c.rect(11, 22, 10, 3, (240, 240, 240))
    c.rect(14, 5, 5, 5, DARK)
    c.rect(15, 6, 3, 3, (150, 166, 194))
    c.rect(18, 5, 8, 2, DARK)
    c.line(21, 7, 25, 12, DARK, 1)
    c.rect(10, 27, 12, 2, (84, 24, 34))
    return c.a


def p_popper() -> np.ndarray:
    c = Canvas()
    c.polygon([(8, 28), (22, 22), (13, 10)], (255, 140, 40))
    c.polygon([(9, 27), (20, 22), (14, 12)], (255, 196, 64))
    c.line(8, 28, 22, 22, DARK)
    c.line(8, 28, 13, 10, DARK)
    c.line(22, 22, 13, 10, DARK)
    for (x, y, col) in [(18, 6, (235, 80, 80)), (23, 10, (110, 170, 240)), (14, 5, (110, 210, 120)),
                        (26, 15, (225, 110, 235)), (21, 4, (255, 196, 64)), (9, 8, (110, 170, 240))]:
        c.rect(x, y, 2, 2, col)
    return c.a


def p_fireworks() -> np.ndarray:
    c = Canvas()
    c.line(16, 29, 16, 15, (150, 100, 60), 2)
    c.rect(12, 6, 9, 11, DARK)
    c.rect(13, 7, 7, 9, (255, 140, 40))
    c.rect(13, 10, 7, 2, (240, 240, 240))
    c.polygon([(12, 6), (21, 6), (16, 0)], (235, 80, 80))
    c.px(16, 1, (255, 232, 150))
    c.px(5, 5, (255, 232, 150)); c.px(27, 8, (110, 170, 240)); c.px(6, 14, (235, 80, 80)); c.px(26, 16, (110, 210, 120))
    return c.a


def p_sock() -> np.ndarray:
    c = Canvas()
    c.rect(11, 4, 9, 14, DARK)
    c.rect(12, 5, 7, 12, (240, 240, 240))
    c.polygon([(11, 16), (20, 16), (26, 24), (26, 28), (14, 28), (11, 22)], DARK)
    c.polygon([(12, 17), (19, 17), (25, 24), (25, 27), (15, 27), (12, 22)], (240, 240, 240))
    for y in (7, 11, 15):
        c.rect(12, y, 7, 2, (235, 80, 80))
    c.rect(18, 24, 8, 3, (110, 170, 240))
    return c.a


def p_trophy() -> np.ndarray:
    c = Canvas()
    c.ellipse(8, 5, 16, 14, DARK)
    c.ellipse(9, 6, 14, 12, GOLD)
    c.rect(8, 6, 16, 5, GOLD)
    c.rect(10, 7, 3, 8, (255, 232, 150))
    for s, x in ((-1, 3), (1, 22)):
        c.rect(x, 8, 4, 2, GOLD_D)
        c.rect(x + (0 if s < 0 else 2), 10, 2, 4, GOLD_D)
    c.rect(14, 18, 4, 6, GOLD_D)
    c.rect(9, 24, 14, 5, DARK)
    c.rect(10, 25, 12, 3, (150, 100, 60))
    c.rect(13, 26, 6, 1, GOLD)
    return c.a


def p_remote() -> np.ndarray:
    c = Canvas()
    c.rect(11, 3, 10, 26, DARK)
    c.rect(12, 4, 8, 24, (60, 70, 92))
    c.rect(12, 4, 2, 24, (100, 114, 140))
    c.rect(14, 6, 4, 3, (235, 80, 80))
    for i, col in enumerate([(110, 210, 120), (110, 170, 240), (255, 196, 64)]):
        for j in range(3):
            c.rect(13 + j * 2 + (j > 0), 12 + i * 4, 2, 3, col if j == 1 else (150, 166, 194))
    c.rect(13, 25, 6, 2, (150, 166, 194))
    return c.a


def p_mug() -> np.ndarray:
    c = Canvas()
    c.rect(7, 9, 15, 19, DARK)
    c.rect(8, 10, 13, 17, (240, 240, 240))
    c.rect(8, 10, 3, 17, (225, 222, 235))
    c.rect(8, 12, 13, 3, (110, 170, 240))
    c.rect(9, 10, 11, 2, (84, 72, 62))                      # tea
    c.rect(22, 12, 5, 12, DARK)
    c.rect(23, 13, 3, 10, (240, 240, 240))
    c.rect(23, 15, 1, 6, (0, 0, 0, 0))
    c.px(12, 5, (186, 182, 198)); c.px(14, 3, (186, 182, 198)); c.px(16, 6, (186, 182, 198))  # steam
    return c.a


def _label(col, mark):
    def paint(c: Canvas, b) -> None:
        cx = (b[0] + b[2]) // 2
        y = b[1] + int((b[3] - b[1]) * 0.62)
        c.rect(cx - 3, y, 7, 4, DARK)
        c.rect(cx - 2, y + 1, 5, 2, col)
        c.px(cx, y + 1, mark)
    return paint


LABELS = {"tonic": _label((240, 240, 240), (235, 80, 80)),
          "brew": _label((190, 130, 40), DARK),
          "elixir": _label((255, 196, 64), (235, 80, 80))}


def build_items() -> None:
    G = ap
    # (key, file, dcss source or None, hue, light, painter)
    dc = {
        "cleaver": ("item/weapon/hand_axe1.png", None, 1.0),
        "katana": ("item/weapon/scimitar1.png", (150, 220, 255), 1.15),
        "sledge": ("item/weapon/mace_large1.png", None, 1.0),
        "jersey": ("item/armour/robe2.png", (140, 170, 220), 1.0),
        "vest": ("item/armour/leather_armour1.png", (120, 150, 200), 1.0),
        "plate": ("item/armour/plate1.png", (170, 190, 230), 1.55),
        "tonic": ("item/potion/ruby.png", (240, 120, 150), 1.35),
        "brew": ("item/potion/murky.png", (240, 90, 130), 1.0),
        "elixir": ("item/potion/orange.png", (255, 70, 120), 1.1),
    }
    fill = {"pan": p_pan, "extinguisher": p_extinguisher, "popper": p_popper, "fireworks": p_fireworks,
            "sock": p_sock, "trophy": p_trophy, "remote": p_remote, "mug": p_mug}
    for key, (src, hue, light) in dc.items():
        a = prep(src, hue=hue, light=light, item=True)
        if key in LABELS:                                  # a sponsor label on the bottle
            a = over(a, LABELS[key])
        sprite("item:" + key, "sprites/items/%s.png" % key, a, "dcss+fill-in" if key in LABELS else "dcss", [src],
               ("recoloured to the item's colour" if hue else "") + ("; sponsor label drawn on" if key in LABELS else ""))
    for key, fn in fill.items():
        sprite("item:" + key, "sprites/items/%s.png" % key, ap.fit(fn(), 32), "fill-in", [], "no DCSS match; drawn in code")
    # loot boxes (menus and the reveal): the DCSS box recoloured per tier, with a ribbon
    boxes = {"bronze": (205, 140, 80), "silver": (200, 205, 215), "gold": (255, 196, 64),
             "platinum": (150, 225, 235), "legendary": (235, 110, 255)}
    for tier, col in boxes.items():
        save_box(tier, col)


def save_box(tier: str, col: tuple[int, int, int]) -> None:
    c = Canvas()
    dark = tuple(int(v * 0.55) for v in col)
    lite = tuple(min(255, int(v * 1.3)) for v in col)
    c.rect(4, 12, 24, 17, DARK)
    c.rect(5, 13, 22, 15, col)
    c.rect(5, 24, 22, 4, dark)
    c.rect(3, 8, 26, 6, DARK)
    c.rect(4, 9, 24, 4, lite)
    c.rect(14, 8, 4, 21, (240, 240, 240))                  # ribbon
    c.rect(14, 9, 4, 20, (235, 80, 80))
    c.rect(11, 5, 4, 4, (235, 80, 80)); c.rect(17, 5, 4, 4, (235, 80, 80))
    c.px(12, 6, (255, 140, 120)); c.px(18, 6, (255, 140, 120))
    a = ap.snap(ap.fit(c.a, 32))
    save("ui/boxes/%s.png" % tier, a)
    register("box:" + tier, "ui/boxes/%s.png" % tier, "fill-in", [], "recoloured per tier")
    big = np.repeat(np.repeat(a, 2, axis=0), 2, axis=1)
    save("ui/boxes/%s_big.png" % tier, big)
    register("box_big:" + tier, "ui/boxes/%s_big.png" % tier, "fill-in", [], "2x nearest of the 32 px box")


# --- Furniture, stairs, torches ----------------------------------------------------------------

def draw_bed() -> np.ndarray:
    c = Canvas()
    c.rect(2, 16, 28, 12, DARK)
    c.rect(3, 17, 26, 10, (110, 70, 42))
    c.rect(3, 12, 26, 9, DARK)
    c.rect(4, 13, 24, 7, (110, 170, 240))                  # sponsor blanket
    c.rect(4, 17, 24, 2, (255, 196, 64))
    c.rect(8, 14, 3, 4, (255, 196, 64)); c.rect(14, 14, 3, 4, (255, 196, 64))   # sponsor logo marks
    c.rect(4, 9, 9, 6, DARK)
    c.rect(5, 10, 7, 4, (240, 240, 240))
    for x in (3, 26):
        c.rect(x, 27, 3, 3, DARK)
    return c.a


def draw_bench() -> np.ndarray:
    c = Canvas()
    c.rect(1, 14, 30, 7, DARK)
    c.rect(2, 15, 28, 5, (190, 136, 86))
    c.rect(2, 15, 28, 1, (224, 178, 128))
    for x in (3, 25):
        c.rect(x, 21, 4, 9, DARK)
        c.rect(x + 1, 21, 2, 8, (110, 70, 42))
    c.rect(5, 8, 8, 7, DARK)                                # vice
    c.rect(6, 9, 6, 5, (150, 166, 194))
    c.rect(8, 6, 2, 3, (100, 114, 140))
    c.line(18, 13, 26, 5, DARK, 3)
    c.line(18, 13, 26, 5, (200, 214, 236), 1)
    return c.a


def draw_counter() -> np.ndarray:
    c = Canvas()
    c.rect(0, 14, 32, 16, DARK)
    c.rect(1, 15, 30, 14, (120, 60, 150))
    c.rect(1, 13, 30, 3, DARK)
    c.rect(1, 13, 30, 2, (255, 196, 64))
    c.rect(18, 4, 11, 9, DARK)                              # price board
    c.rect(19, 5, 9, 7, (240, 240, 240))
    c.rect(20, 6, 4, 1, DARK); c.rect(20, 8, 6, 1, DARK); c.rect(20, 10, 3, 1, (235, 80, 80))
    c.rect(4, 6, 9, 7, DARK)                                # till
    c.rect(5, 7, 7, 3, (110, 210, 120))
    c.rect(5, 11, 7, 2, (150, 166, 194))
    c.rect(4, 22, 24, 2, (255, 196, 64))
    return c.a


def draw_stairs_arrow(locked: bool) -> np.ndarray:
    col, dk = ((235, 80, 80), (84, 24, 34)) if locked else ((255, 196, 64), (150, 84, 28))
    c = Canvas()
    c.polygon([(5, 6), (27, 6), (16, 28)], dk)
    c.polygon([(7, 8), (25, 8), (16, 25)], col)
    c.polygon([(10, 9), (16, 9), (14, 14)], tuple(min(255, v + 40) for v in col))
    if locked:
        c.rect(12, 13, 8, 7, DARK)
        c.rect(13, 14, 6, 5, (150, 166, 194))
        c.rect(13, 10, 2, 4, DARK); c.rect(17, 10, 2, 4, DARK); c.rect(13, 9, 6, 2, DARK)
        c.px(16, 16, DARK)
    return c.a


def draw_torch(frame: int) -> np.ndarray:
    c = Canvas()
    c.rect(13, 20, 6, 10, DARK)
    c.rect(14, 21, 4, 8, (100, 114, 140))
    c.rect(11, 18, 10, 4, DARK)
    c.rect(12, 19, 8, 2, (150, 166, 194))
    lean = 1 if frame else 0
    c.polygon([(10 + lean, 18), (16, 4 + lean), (22 - lean, 18)], (235, 80, 80))
    c.polygon([(12, 18), (16 + lean, 8), (20, 18)], (255, 140, 40))
    c.polygon([(14, 18), (16, 12 + lean), (18, 18)], (255, 232, 150))
    return c.a


def build_furniture() -> None:
    for kind, fn in (("bed", draw_bed), ("bench", draw_bench), ("counter", draw_counter)):
        sprite("furn:" + kind, "sprites/furniture/%s.png" % kind, ap.fit(fn(), 32), "fill-in", [],
               "no DCSS match; drawn in code")
    sprite("fx:stairs_open", "sprites/fx/stairs_open.png", ap.fit(draw_stairs_arrow(False), 32), "fill-in", [])
    sprite("fx:stairs_locked", "sprites/fx/stairs_locked.png", ap.fit(draw_stairs_arrow(True), 32), "fill-in", [],
           "red arrow with a padlock")
    for f in (0, 1):
        sprite("fx:torch_%d" % f, "sprites/fx/torch_%d.png" % f, draw_torch(f), "fill-in", [])


# --- Terrain: 64 x 64 textures, 32 x 32 top-down tiles -----------------------------------------

def stone_texture(rels: list[str], mean: float, keep: float = 0.25, flip: bool = False) -> tuple[np.ndarray, list[str]]:
    """One 32 x 32 DCSS tile (or a 2 x 2 patchwork of several) made near-neutral and mid-value."""
    tiles = [ap.desaturate(dcss(r)[..., :4], keep) for r in rels]
    t = tiles[0]
    t[..., 3] = 255
    t = ap.set_mean_luminance(t, mean)
    return t, rels


def tile2(t32: np.ndarray) -> np.ndarray:
    return np.tile(t32, (2, 2, 1))


def finish_tex(a: np.ndarray) -> np.ndarray:
    a = a.copy()
    a[..., 3] = 255
    return ap.snap(a, ap.TEXTURE_PALETTE)


def hazard_band(t: np.ndarray, y0: int, h: int) -> np.ndarray:
    """Yellow and black hazard tape across a 64 x 64 wall (floor 3's set dressing)."""
    t = t.copy()
    for y in range(y0, y0 + h):
        for x in range(64):
            t[y, x, :3] = (190, 160, 90) if ((x + y) // 4) % 2 == 0 else (46, 44, 54)
    t[y0, :, :3] = (24, 22, 30)
    t[y0 + h - 1, :, :3] = (24, 22, 30)
    return t


def ceiling_texture(depth: int) -> np.ndarray:
    rng = np.random.default_rng(1000 + depth)
    a = np.zeros((64, 64, 4), dtype=np.uint8)
    base = np.array([44, 41, 50]) + rng.integers(-4, 5, size=(64, 64, 1))
    a[..., :3] = base
    a[..., 3] = 255
    c = Canvas(base=a)
    seam = (24, 22, 30)
    hi = (74, 70, 82)
    if depth == 1:                                         # service tunnel: pipes along the ceiling
        for y, w in ((8, 5), (30, 4), (48, 6)):
            c.rect(0, y, 64, w, seam)
            c.rect(0, y + 1, 64, max(1, w - 3), (74, 70, 82))
            c.rect(0, y + 1, 64, 1, (96, 92, 108))
        for x in (14, 40):
            for y in (8, 30, 48):
                c.rect(x, y - 1, 3, 7, (58, 54, 70))
    elif depth == 2:                                       # archive: wooden beams
        for y in (0, 21, 42):
            c.rect(0, y, 64, 8, (84, 72, 62))
            c.rect(0, y, 64, 1, (118, 102, 86))
            c.rect(0, y + 7, 64, 1, seam)
    elif depth == 3:                                       # building site: raw boards and bolts
        for x in range(0, 64, 16):
            c.rect(x, 0, 1, 64, seam)
        for x in range(8, 64, 16):
            for y in (6, 30, 54):
                c.px(x, y, hi); c.px(x + 1, y, hi)
    elif depth == 4:                                       # chapel: vaulted ribs
        c.line(0, 0, 63, 63, (84, 72, 62), 2); c.line(63, 0, 0, 63, (84, 72, 62), 2)
        c.rect(0, 0, 64, 2, seam); c.rect(0, 62, 64, 2, seam)
        c.ellipse(26, 26, 12, 12, (96, 92, 108))
    elif depth == 5:                                       # warehouse: corrugated roof sheets
        for x in range(0, 64, 4):
            c.rect(x, 0, 1, 64, (96, 92, 108)); c.rect(x + 2, 0, 1, 64, seam)
    else:                                                  # studio: lighting grid and rigging
        for x in (0, 31):
            c.rect(x, 0, 2, 64, hi)
        for y in (0, 31):
            c.rect(0, y, 64, 2, hi)
        for (x, y) in ((8, 8), (40, 8), (8, 40), (40, 40)):
            c.rect(x, y, 14, 14, seam)
            c.rect(x + 2, y + 2, 10, 10, (186, 182, 198))
    return finish_tex(c.a)


def stairs_texture(locked: bool) -> np.ndarray:
    a = np.zeros((64, 64, 4), dtype=np.uint8)
    for y in range(64):
        for x in range(64):
            d = max(abs(x - 31.5), abs(y - 31.5))
            glow = max(0.0, min(1.0, 1.0 - d / 34.0))
            if int(d) % 8 < 2:
                g = 0.5 + 0.5 * glow
                rgb = (255 * g, 190 * g, 60 * g)
            else:
                rgb = (30 + 60 * glow, 24 + 60 * glow, 14 + 60 * glow)
            if locked:
                rgb = (rgb[0] * 0.8, rgb[1] * 0.22, rgb[2] * 0.22) if int(d) % 8 < 2 else (rgb[0] * 0.8, rgb[1] * 0.4, rgb[2] * 0.4)
            a[y, x] = (*[int(v) for v in rgb], 255)
    return ap.snap(a)


def safe_textures() -> tuple[np.ndarray, np.ndarray, list[str]]:
    """Pale green tiled studio hospitality: clean 16 px square tiles, bright grout."""
    wall_src = "dngn/wall/marble_wall1.png"
    floor_src = "dngn/floor/white_marble0.png"
    w = ap.hue_match(dcss(wall_src), (150, 220, 170), min_sat=0.0)
    w = ap.set_mean_luminance(w[..., :4], 188, 236)
    wall = tile2(w)
    f = ap.hue_match(dcss(floor_src), (150, 220, 170), min_sat=0.0)
    f = ap.desaturate(f, 0.35)
    f = ap.set_mean_luminance(f[..., :4], 168, 236)
    floor = tile2(f)
    for t, grout in ((wall, (96, 130, 108)), (floor, (84, 120, 100))):
        for i in range(0, 64, 16):
            t[i, :, :3] = grout
            t[:, i, :3] = grout
    # the clean tile pattern alternates by a few steps so it reads as squares, not noise
    for yy in range(4):
        for xx in range(4):
            if (xx + yy) % 2:
                floor[yy * 16 + 1:yy * 16 + 16, xx * 16 + 1:xx * 16 + 16, :3] = np.clip(
                    floor[yy * 16 + 1:yy * 16 + 16, xx * 16 + 1:xx * 16 + 16, :3].astype(int) - 14, 0, 255)
    for t in (wall, floor):
        t[..., 3] = 255
    return ap.snap(wall), ap.snap(floor), [wall_src, floor_src]


THEMES = {
    # depth: (wall_a, wall_b, floor, set dressing note)
    1: ("dngn/wall/brick_gray0.png", "dngn/wall/brick_gray1.png", "dngn/floor/rect_gray0.png", "service tunnels and drains"),
    2: ("dngn/wall/brick_brown1.png", "dngn/wall/relief_brown0.png", "dngn/floor/limestone0.png", "archive stacks"),
    3: ("dngn/wall/stone2_gray0.png", "dngn/wall/lab-stone3.png", "dngn/floor/dirt0.png", "half-built site, hazard tape"),
    4: ("dngn/wall/church0.png", "dngn/wall/undead_brown0.png", "dngn/floor/tomb0.png", "cult chapel"),
    5: ("dngn/wall/lab-metal0.png", "dngn/wall/metal_wall_white0.png", "dngn/floor/mesh0.png", "warehouse"),
    6: ("dngn/wall/relief0.png", "dngn/wall/silver_wall.png", "dngn/floor/white_marble3.png", "studio floor and executive suite"),
}
WALL_MEAN = 108.0
FLOOR_MEAN = 78.0


def build_terrain() -> None:
    for depth, (wa, wb, fl, note) in THEMES.items():
        used: dict[str, list[str]] = {}
        outs = {}
        for slot, rel, mean in (("wall_0", wa, WALL_MEAN), ("wall_1", wb, WALL_MEAN - 6), ("floor", fl, FLOOR_MEAN)):
            t32, srcs = stone_texture([rel], mean)
            t32 = finish_tex(t32)
            t64 = tile2(t32)
            if depth == 3 and slot == "wall_1":
                t64 = hazard_band(t64, 40, 8)
            outs[slot] = (t32, t64, srcs)
        ceil = ceiling_texture(depth)
        for slot, (t32, t64, srcs) in outs.items():
            origin = "dcss+fill-in" if depth == 3 and slot == "wall_1" else "dcss"
            note_s = "desaturated and levelled so the floor tint has something neutral to multiply"
            save("textures/floor%d/%s.png" % (depth, slot), t64)
            register("tex:%d:%s" % (depth, slot), "textures/floor%d/%s.png" % (depth, slot), origin, srcs, note_s)
            # the top-down tile is the same texture reduced (every second pixel), so both views match
            top = t64[::2, ::2].copy()
            save("tiles/floor%d/%s.png" % (depth, slot), top)
            register("tile:%d:%s" % (depth, slot), "tiles/floor%d/%s.png" % (depth, slot), origin, srcs, "")
        save("textures/floor%d/ceiling.png" % depth, ceil)
        register("tex:%d:ceiling" % depth, "textures/floor%d/ceiling.png" % depth, "fill-in", [], note)
    sw, sf, srcs = safe_textures()
    for name, t, s in (("safe_wall", sw, [srcs[0]]), ("safe_floor", sf, [srcs[1]])):
        save("textures/common/%s.png" % name, t)
        register("tex:" + name, "textures/common/%s.png" % name, "dcss+fill-in", s, "recoloured pale green, clean 16 px tile grid")
        save("tiles/common/%s.png" % name, t[::2, ::2].copy())
        register("tile:" + name, "tiles/common/%s.png" % name, "dcss+fill-in", s, "")
    for locked in (False, True):
        name = "stairs_locked" if locked else "stairs_open"
        t = stairs_texture(locked)
        save("textures/common/%s.png" % name, t)
        register("tex:" + name, "textures/common/%s.png" % name, "fill-in", [], "gold grate" if not locked else "dimmed red grate")
        top = Canvas(base=t[::2, ::2].copy())
        if locked:                                          # padlock on the top-down tile
            top.rect(11, 12, 10, 9, DARK)
            top.rect(12, 13, 8, 7, (150, 166, 194))
            top.rect(13, 7, 2, 7, DARK); top.rect(17, 7, 2, 7, DARK); top.rect(13, 6, 6, 2, DARK)
            top.px(16, 16, DARK); top.px(16, 17, DARK)
        save("tiles/common/%s.png" % name, top.a)
        register("tile:" + name, "tiles/common/%s.png" % name, "fill-in", [], "padlock on the locked tile" if locked else "")


# --- CREDITS -----------------------------------------------------------------------------------

def write_credits(path: str, artists: str, commit: str = "unknown") -> None:
    lines = [
        "# Art credits",
        "",
        "Generated by `scripts/art_build.py` from `manifest.json`; do not edit by hand.",
        "",
        "## Dungeon Crawl Stone Soup tiles",
        "",
        "Most of the pictures are tiles from **Dungeon Crawl Stone Soup** (DCSS), made by its many artists and",
        "packaged by the `crawl/tiles` project: <%s>, snapshot `releases/Nov-2015` (repository commit %s)." % (SOURCE_URL, commit),
        "The project's README states that the artists in its ARTISTS.md signed their tiles over to **CC0 1.0** (public",
        "domain), and that tiles of unclear ownership are excluded from the export and listed in",
        "TILES_UNDER_UNKNOWN_LICENSE.md. `scripts/art_build.py` refuses to use any tile on that list. Credit is given",
        "even though CC0 does not require it: thank you to the Crawl Stone Soup artists and developers",
        "(<http://crawl.develz.org>) and to the RLTiles project they started from (<http://rltiles.sourceforge.net>).",
        "",
        "Licence: " + LICENCE + ". Per-tile artists are not recorded in the export, so the list below gives each",
        "source path; the artists who gave approval are listed in the project's ARTISTS.md:",
        "",
    ]
    for ln in artists.splitlines():
        if ln.strip().startswith("- ") or ln.strip().startswith("The following"):
            lines.append(re.sub(r"\s*\S+@\S+", "", ln).rstrip())            # names and handles only, no email addresses
    lines += [
        "",
        "Every DCSS tile was edited for Crawl Live!: trimmed, shrunk by whole lines where it was wider than the",
        "frame, snapped to the shared palette (`scripts/art_pipeline.py`), given binary alpha, and in places recoloured",
        "or given props. The edited PNGs are what is in this folder; the original download is not in the repository.",
        "",
        "## Fill-in art",
        "",
        "Entries marked `fill-in` (vacuum bot, frying pan, fire extinguisher, party popper, fireworks, sock, trophy,",
        "remote, mug, furniture, stairwell arrows and grates, loot boxes, ceilings, torch frames, Act badge and sash,",
        "and the props drawn over DCSS bodies) are original, drawn in code by `scripts/art_build.py`, and released as CC0 1.0.",
        "",
        "## Other art sets",
        "",
        "Folders under `sets/` are alternative art sets (see `scripts/artgen.py`); each has its own `manifest.json` recording the",
        "source file and licence of every picture. `sets/ai_trial` is a plumbing test built from the pictures above, made messy on",
        "purpose; it holds no AI-generated art yet. Record the source and licence of anything added before it ships.",
        "",
        "## Per file",
        "",
        "| Key | File | Origin | Source tiles (all under `%s/%s/`) | Licence |" % (SOURCE_URL, ROOT),
        "|---|---|---|---|---|",
    ]
    for key, e in MANIFEST.items():
        srcs = ", ".join("`%s`" % s.split(ROOT + "/")[-1] for s in e["source"]) or "(original)"
        lines.append("| `%s` | `%s` | %s | %s | CC0 1.0 |" % (key, e["file"], e["origin"], srcs))
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


# --- Contact sheets ----------------------------------------------------------------------------

def contact_sheet(path: str, files: list[str], scale: int = 3, cols: int = 12) -> None:
    from PIL import ImageDraw
    tiles = []
    for rel in files:
        im = Image.open(os.path.join(OUT, rel)).convert("RGBA")
        tiles.append((rel, im))
    cw = 32 * scale + 6
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGBA", (cols * cw, rows * (32 * scale + 20)), (70, 66, 80, 255))
    d = ImageDraw.Draw(sheet)
    for i, (rel, im) in enumerate(tiles):
        x, y = (i % cols) * cw + 3, (i // cols) * (32 * scale + 20) + 3
        im2 = im.resize((32 * scale, 32 * scale), Image.NEAREST) if im.width <= 32 else im.resize((32 * scale, 32 * scale), Image.NEAREST)
        sheet.alpha_composite(im2, (x, y))
        d.text((x, y + 32 * scale + 2), os.path.basename(rel)[:-4][:14], fill=(255, 255, 255, 255))
    sheet.save(path)


# --- Main --------------------------------------------------------------------------------------

def main() -> None:
    global OUT, SRC, EXCLUDED
    ap_ = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap_.add_argument("--src", required=True, help="the cloned crawl/tiles repository")
    ap_.add_argument("--out", default="godot/assets", help="the assets folder to write (default godot/assets)")
    ap_.add_argument("--sheet", default="", help="also write contact sheets of the results here (not in the repo)")
    args = ap_.parse_args()
    SRC, OUT = args.src, args.out
    EXCLUDED = load_excluded(SRC)
    build_creatures()
    build_players()
    build_items()
    build_furniture()
    build_terrain()
    with open(os.path.join(OUT, "manifest.json"), "w", encoding="utf-8") as f:
        json.dump({"art_set": "default", "generator": "scripts/art_build.py", **{k: v for k, v in MANIFEST.items()}},
                  f, indent=1, sort_keys=False)
        f.write("\n")
    artists = open(os.path.join(SRC, "ARTISTS.md"), encoding="utf-8").read()
    head = os.path.join(SRC, ".git", "HEAD")                  # the commit of the tiles repository the art came from
    commit = "unknown"
    try:
        ref = open(head).read().strip()
        if ref.startswith("ref: "):
            ref = open(os.path.join(SRC, ".git", ref[5:])).read().strip()
        commit = ref or "unknown"
    except OSError:
        pass
    write_credits(os.path.join(OUT, "CREDITS.md"), artists, commit)
    n = {}
    for e in MANIFEST.values():
        n[e["origin"]] = n.get(e["origin"], 0) + 1
    print("wrote %d entries: %s; %d DCSS source tiles" % (len(MANIFEST), n, len(USED_SOURCES)))
    if args.sheet:
        os.makedirs(args.sheet, exist_ok=True)
        for group in ("monsters", "headliners", "pets", "items", "furniture", "player", "fx", "acts"):
            d = os.path.join(OUT, "sprites", group)
            files = sorted("sprites/%s/%s" % (group, f) for f in os.listdir(d) if f.endswith(".png"))
            contact_sheet(os.path.join(args.sheet, "sprites_%s.png" % group), files)
        contact_sheet(os.path.join(args.sheet, "boxes.png"), sorted("ui/boxes/" + f for f in os.listdir(os.path.join(OUT, "ui/boxes")) if f.endswith(".png")), 2)


if __name__ == "__main__":
    main()

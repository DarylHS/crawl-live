"""Shared pixel-art helpers for the P9 art tools (scripts/art_build.py, scripts/artgen.py).

Everything here works on numpy RGBA arrays (height, width, 4, uint8) and follows the art bible
(docs/art-bible.md sections 3 and 4): binary alpha, feet on the bottom row, a one pixel transparent
border, hard pixels only (no anti-aliasing), colours snapped to the shared palette.

Run any script that imports this with the repo's scripts/ directory first on sys.path (they do).
"""
from __future__ import annotations

import colorsys
import math

import numpy as np

# --- The shared palette (art bible section 4) --------------------------------------------------
# Anchors are the config.py constants (BG, TEXT, ACCENT, DANGER, WARN, GOOD, INFO and the monster and
# item colours); each family is a 3 to 6 step ramp. 56 colours: a little over the bible's "about 32"
# because the DCSS tiles come from many artists and a smaller set turned skin and stone to mush.
PALETTE: list[tuple[int, int, int]] = [
    # darks and outlines
    (14, 12, 18), (24, 22, 30), (40, 37, 52), (58, 54, 70),
    # stone greys (the dungeon)
    (74, 70, 82), (96, 92, 108), (122, 116, 134), (152, 148, 166), (186, 182, 198), (225, 222, 235),
    # grey-browns (floors, bone, wood)
    (52, 44, 40), (84, 72, 62), (118, 102, 86), (156, 138, 114), (196, 176, 148),
    # skin, fur and wood browns
    (70, 42, 28), (110, 70, 42), (150, 100, 60), (190, 136, 86), (224, 178, 128), (244, 214, 172),
    # greens (goblins, plants, GOOD)
    (30, 62, 40), (52, 100, 60), (88, 150, 64), (120, 190, 80), (110, 210, 120), (176, 226, 140),
    # steel
    (60, 70, 92), (100, 114, 140), (150, 166, 194), (200, 214, 236),
    # reds (DANGER)
    (84, 24, 34), (148, 40, 48), (235, 80, 80), (255, 140, 120),
    # oranges and golds (WARN, ACCENT)
    (150, 84, 28), (255, 140, 40), (190, 130, 40), (255, 196, 64), (255, 232, 150),
    # blues (INFO)
    (36, 52, 110), (66, 104, 186), (110, 170, 240), (170, 210, 255),
    # purples (cultists, Volka)
    (66, 36, 92), (120, 60, 150), (190, 90, 210), (225, 110, 235),
    # the potion pink-red ramp and flesh
    (150, 40, 80), (210, 100, 130), (240, 120, 150), (255, 70, 120), (255, 176, 196),
    # whites
    (240, 240, 240), (255, 255, 255),
]

# Textures use only the stone greys, grey-browns and darks, so the per-floor tint has something neutral
# to multiply (art bible section 3).
TEXTURE_PALETTE: list[tuple[int, int, int]] = (
    PALETTE[0:10] + PALETTE[10:15] + [(100, 98, 104), (134, 130, 138), (170, 166, 172), (204, 200, 206)])

OUTLINE = (14, 12, 18)


def _lab(rgb: np.ndarray) -> np.ndarray:
    """sRGB (..., 3) 0-255 to CIE Lab (D65)."""
    c = rgb.astype(np.float64) / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124564, 0.3575761, 0.1804375],
                  [0.2126729, 0.7151522, 0.0721750],
                  [0.0193339, 0.1191920, 0.9503041]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16.0 / 116.0)
    return np.stack([116.0 * f[..., 1] - 16.0, 500.0 * (f[..., 0] - f[..., 1]), 200.0 * (f[..., 1] - f[..., 2])], axis=-1)


_PAL_CACHE: dict[int, tuple[np.ndarray, np.ndarray]] = {}


def snap(arr: np.ndarray, palette: list[tuple[int, int, int]] | None = None) -> np.ndarray:
    """Snap every opaque pixel's colour to the nearest palette colour (Lab distance); alpha untouched."""
    pal = PALETTE if palette is None else palette
    key = id(pal)
    if key not in _PAL_CACHE:
        p = np.array(pal, dtype=np.uint8)
        _PAL_CACHE[key] = (p, _lab(p))
    p, plab = _PAL_CACHE[key]
    out = arr.copy()
    flat = arr.reshape(-1, 4)
    rgb = flat[:, :3]
    uniq, inv = np.unique(rgb, axis=0, return_inverse=True)
    d = ((_lab(uniq)[:, None, :] - plab[None, :, :]) ** 2).sum(axis=2)
    best = d.argmin(axis=1)
    out.reshape(-1, 4)[:, :3] = p[best][inv.reshape(-1)]
    return out


# --- Cleaning ----------------------------------------------------------------------------------

def binary_alpha(arr: np.ndarray, threshold: int = 128) -> np.ndarray:
    """Alpha to 0 or 255 (transparent pixels get black RGB so nothing leaks in a resample)."""
    out = arr.copy()
    solid = out[..., 3] >= threshold
    out[..., 3] = np.where(solid, 255, 0)
    out[~solid, :3] = 0
    return out


def strip_exterior_black(arr: np.ndarray) -> np.ndarray:
    """DCSS creature tiles carry a pure black outline and a black ground shadow. The game draws its own
    outline (and shadows), so remove every pure black pixel connected to the outside through black."""
    out = arr.copy()
    h, w = out.shape[:2]
    black = (out[..., 3] > 0) & (out[..., :3].max(axis=2) <= 6)
    clear = out[..., 3] == 0
    seen = np.zeros((h, w), dtype=bool)
    stack = [(x, y) for y in range(h) for x in range(w) if clear[y, x]]
    while stack:
        x, y = stack.pop()
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, -1), (1, -1), (-1, 1)):
            nx, ny = x + dx, y + dy
            if 0 <= nx < w and 0 <= ny < h and not seen[ny, nx] and black[ny, nx]:
                seen[ny, nx] = True
                stack.append((nx, ny))
    # black touching the tile edge is also exterior
    out[seen, 3] = 0
    out[seen, :3] = 0
    return out


def bbox(arr: np.ndarray) -> tuple[int, int, int, int] | None:
    """(x0, y0, x1, y1) inclusive bounds of the opaque pixels, or None."""
    ys, xs = np.where(arr[..., 3] > 0)
    if len(xs) == 0:
        return None
    return int(xs.min()), int(ys.min()), int(xs.max()), int(ys.max())


def trim(arr: np.ndarray) -> np.ndarray:
    b = bbox(arr)
    if b is None:
        return arr
    return arr[b[1]:b[3] + 1, b[0]:b[2] + 1].copy()


def _drop_quietest(arr: np.ndarray, axis: int) -> np.ndarray:
    """Remove the one row (axis 0) or column (axis 1) that differs least from its neighbour, so a
    sprite shrinks by a line without the jagged look of a nearest-neighbour resample."""
    a = arr if axis == 0 else arr.transpose(1, 0, 2)
    diffs = [int(np.abs(a[i].astype(int) - a[i - 1].astype(int)).sum()) for i in range(1, a.shape[0])]
    i = int(np.argmin(diffs)) + 1
    a = np.delete(a, i, axis=0)
    return a if axis == 0 else a.transpose(1, 0, 2)


def fit(arr: np.ndarray, size: int, border: int = 1) -> np.ndarray:
    """Trim, shrink (whole lines only) to fit size - 2 x border, centre horizontally, put the
    bottom on the last row inside the border. Returns a size x size RGBA array."""
    a = trim(arr)
    room = size - 2 * border
    while a.shape[0] > room:
        a = _drop_quietest(a, 0)
    while a.shape[1] > room:
        a = _drop_quietest(a, 1)
    out = np.zeros((size, size, 4), dtype=np.uint8)
    h, w = a.shape[:2]
    x0 = (size - w) // 2
    y0 = size - border - h
    out[y0:y0 + h, x0:x0 + w] = a
    return out


def remove_background(arr: np.ndarray, tolerance: int = 40) -> np.ndarray:
    """Clear a flat background: if the image has no transparency, flood fill from the borders over
    pixels within `tolerance` of the corner colour (or magenta 255,0,255, the art bible's colour key)."""
    out = arr.copy()
    if (out[..., 3] < 250).any():
        return out
    h, w = out.shape[:2]
    corners = [out[0, 0, :3], out[0, w - 1, :3], out[h - 1, 0, :3], out[h - 1, w - 1, :3]]
    keys = [np.array((255, 0, 255))] + [c for c in corners]
    seen = np.zeros((h, w), dtype=bool)
    stack = [(x, y) for x in range(w) for y in (0, h - 1)] + [(x, y) for y in range(h) for x in (0, w - 1)]
    rgb = out[..., :3].astype(int)
    # the background colour is the commonest border colour among the keys
    border_px = np.concatenate([rgb[0], rgb[-1], rgb[:, 0], rgb[:, -1]])
    best, best_n = keys[0], -1
    for k in keys:
        n = int((np.abs(border_px - k).sum(axis=1) <= tolerance).sum())
        if n > best_n:
            best, best_n = k, n
    if best_n < len(border_px) * 0.3:
        return out                       # no flat background to speak of
    while stack:
        x, y = stack.pop()
        if x < 0 or y < 0 or x >= w or y >= h or seen[y, x]:
            continue
        if np.abs(rgb[y, x] - best).sum() > tolerance:
            continue
        seen[y, x] = True
        stack.extend(((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)))
    out[seen, 3] = 0
    return out


def keep_largest_blob(arr: np.ndarray) -> np.ndarray:
    """Drop stray specks: keep only the biggest 8-connected opaque region (and anything touching it
    within 2 pixels, so a floating hat or sparkle next to the body stays)."""
    solid = arr[..., 3] > 0
    h, w = solid.shape
    label = np.zeros((h, w), dtype=int)
    sizes = {}
    n = 0
    for sy in range(h):
        for sx in range(w):
            if solid[sy, sx] and label[sy, sx] == 0:
                n += 1
                stack = [(sx, sy)]
                label[sy, sx] = n
                cnt = 0
                while stack:
                    x, y = stack.pop()
                    cnt += 1
                    for dy in (-1, 0, 1):
                        for dx in (-1, 0, 1):
                            nx, ny = x + dx, y + dy
                            if 0 <= nx < w and 0 <= ny < h and solid[ny, nx] and label[ny, nx] == 0:
                                label[ny, nx] = n
                                stack.append((nx, ny))
                sizes[n] = cnt
    if n <= 1:
        return arr
    big = max(sizes, key=lambda k: sizes[k])
    keep = np.zeros((h, w), dtype=bool)
    for k, c in sizes.items():
        if k == big or c >= sizes[big] * 0.15:
            keep |= label == k
    out = arr.copy()
    out[~keep] = 0
    return out


# --- Colour work -------------------------------------------------------------------------------

def hue_match(arr: np.ndarray, target: tuple[int, int, int], min_sat: float = 0.18, amount: float = 1.0) -> np.ndarray:
    """Rotate the hue of the saturated pixels to the target colour's hue (sprite colours then match the
    monster's colour in the log and HUD). Saturation and value are kept; `amount` blends the hue."""
    th = colorsys.rgb_to_hsv(*(c / 255.0 for c in target))[0]
    out = arr.copy()
    cache: dict[tuple[int, int, int], tuple[int, int, int]] = {}
    for y in range(out.shape[0]):
        for x in range(out.shape[1]):
            if out[y, x, 3] == 0:
                continue
            rgb = (int(out[y, x, 0]), int(out[y, x, 1]), int(out[y, x, 2]))
            if rgb not in cache:
                h, s, v = colorsys.rgb_to_hsv(*(c / 255.0 for c in rgb))
                if s >= min_sat and v > 0.12:
                    d = (th - h + 0.5) % 1.0 - 0.5
                    h = (h + d * amount) % 1.0
                r, g, b = colorsys.hsv_to_rgb(h, s, v)
                cache[rgb] = (round(r * 255), round(g * 255), round(b * 255))
            out[y, x, :3] = cache[rgb]
    return out


def desaturate(arr: np.ndarray, keep: float) -> np.ndarray:
    """Pull colours towards grey, keeping `keep` (0-1) of the chroma."""
    out = arr.astype(np.float64)
    lum = out[..., :3] @ np.array([0.299, 0.587, 0.114])
    out[..., :3] = lum[..., None] + (out[..., :3] - lum[..., None]) * keep
    return np.clip(out, 0, 255).astype(np.uint8)


def set_mean_luminance(arr: np.ndarray, target: float, ceiling: float = 215.0) -> np.ndarray:
    """Scale brightness so the mean luminance is `target`, never past `ceiling` in any channel."""
    out = arr.astype(np.float64)
    lum = out[..., :3] @ np.array([0.299, 0.587, 0.114])
    k = target / max(lum.mean(), 1.0)
    out[..., :3] = np.clip(out[..., :3] * k, 0, ceiling)
    return out.astype(np.uint8)


def lighten(arr: np.ndarray, k: float) -> np.ndarray:
    out = arr.astype(np.float64)
    out[..., :3] = np.clip(out[..., :3] * k, 0, 255)
    return out.astype(np.uint8)


def rim_light(arr: np.ndarray, colour: tuple[int, int, int]) -> np.ndarray:
    """Recolour the opaque pixels that touch transparency (a lighter rim for dark creatures)."""
    solid = arr[..., 3] > 0
    h, w = solid.shape
    out = arr.copy()
    for y in range(h):
        for x in range(w):
            if not solid[y, x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if nx < 0 or ny < 0 or nx >= w or ny >= h or not solid[ny, nx]:
                    out[y, x, :3] = colour
                    break
    return out


# --- Drawing -----------------------------------------------------------------------------------

class Canvas:
    """A tiny hard-pixel drawing surface over an RGBA array (no anti-aliasing anywhere)."""

    def __init__(self, w: int = 32, h: int = 32, base: np.ndarray | None = None) -> None:
        self.a = np.zeros((h, w, 4), dtype=np.uint8) if base is None else base.copy()
        self.h, self.w = self.a.shape[:2]

    def px(self, x: int, y: int, c: tuple[int, ...]) -> None:
        if 0 <= x < self.w and 0 <= y < self.h:
            self.a[y, x] = (c[0], c[1], c[2], 255) if len(c) == 3 else c

    def rect(self, x: int, y: int, w: int, h: int, c: tuple[int, ...]) -> None:
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                self.px(xx, yy, c)

    def line(self, x0: int, y0: int, x1: int, y1: int, c: tuple[int, ...], width: int = 1) -> None:
        n = max(abs(x1 - x0), abs(y1 - y0), 1)
        for i in range(n + 1):
            x = round(x0 + (x1 - x0) * i / n)
            y = round(y0 + (y1 - y0) * i / n)
            for ox in range(width):
                for oy in range(width):
                    self.px(x + ox - (width - 1) // 2, y + oy - (width - 1) // 2, c)

    def ellipse(self, x: int, y: int, w: int, h: int, c: tuple[int, ...]) -> None:
        cx, cy = x + (w - 1) / 2.0, y + (h - 1) / 2.0
        rx, ry = w / 2.0, h / 2.0
        for yy in range(y, y + h):
            for xx in range(x, x + w):
                if ((xx - cx) / rx) ** 2 + ((yy - cy) / ry) ** 2 <= 1.0:
                    self.px(xx, yy, c)

    def polygon(self, pts: list[tuple[float, float]], c: tuple[int, ...]) -> None:
        ys = [p[1] for p in pts]
        for yy in range(int(math.floor(min(ys))), int(math.ceil(max(ys))) + 1):
            for xx in range(int(math.floor(min(p[0] for p in pts))), int(math.ceil(max(p[0] for p in pts))) + 1):
                if _inside(xx + 0.5, yy + 0.5, pts):
                    self.px(xx, yy, c)

    def paste(self, other: np.ndarray, x: int = 0, y: int = 0, clip_to: np.ndarray | None = None) -> None:
        """Alpha-composite (binary) `other` at (x, y); with `clip_to` only where that array is opaque."""
        oh, ow = other.shape[:2]
        for yy in range(oh):
            for xx in range(ow):
                if other[yy, xx, 3] == 0:
                    continue
                tx, ty = x + xx, y + yy
                if not (0 <= tx < self.w and 0 <= ty < self.h):
                    continue
                if clip_to is not None and clip_to[ty, tx, 3] == 0:
                    continue
                self.a[ty, tx] = other[yy, xx]


def _inside(x: float, y: float, pts: list[tuple[float, float]]) -> bool:
    inside = False
    j = len(pts) - 1
    for i in range(len(pts)):
        xi, yi = pts[i]
        xj, yj = pts[j]
        if (yi > y) != (yj > y) and x < (xj - xi) * (y - yi) / (yj - yi + 1e-12) + xi:
            inside = not inside
        j = i
    return inside


def outline_rect(arr: np.ndarray) -> np.ndarray:
    """A copy with a one pixel near-black outline round the opaque pixels (contact sheets only; the
    game draws its own outline from the alpha)."""
    solid = arr[..., 3] > 0
    out = arr.copy()
    h, w = solid.shape
    for y in range(h):
        for x in range(w):
            if solid[y, x]:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                nx, ny = x + dx, y + dy
                if 0 <= nx < w and 0 <= ny < h and solid[ny, nx]:
                    out[y, x] = (*OUTLINE, 255)
                    break
    return out

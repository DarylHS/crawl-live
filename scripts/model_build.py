"""Build the 3D loot box models (one .glb per tier) from code.

Experiment: every vertex is generated here, with no modelling tool and no downloaded
assets. The trim colour of each tier comes from godot/data/loot_boxes.json, so the models
follow the game data.

    python scripts/model_build.py            # writes docs/models/loot_box_<tier>.glb

Each file holds two nodes, Body and Lid. The Lid node pivots on the back hinge and the
file carries an "open" animation (closed -> overshoot -> settled), so the reveal can be
played in Godot with an AnimationPlayer. Units are metres, Y is up, the front faces +Z.
"""

from __future__ import annotations

import json
import math
import struct
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "docs" / "models"
LOOT_BOXES = ROOT / "godot" / "data" / "loot_boxes.json"

LID_OPEN_DEG = 38.0
HINGE = (0.0, 0.502, -0.30)

# Body panel colour per tier (sRGB 0-1); the trim colour is read from the game data.
PANEL = {
    "bronze": (0.36, 0.21, 0.12),
    "silver": (0.27, 0.24, 0.24),
    "gold": (0.42, 0.08, 0.09),
    "platinum": (0.08, 0.14, 0.32),
    "legendary": (0.13, 0.07, 0.24),
}

# name -> (metallic, roughness, emissive strength). Hue comes from vertex colours.
MATERIALS = {
    "lacquer": (0.0, 0.55, 0.0),
    "metal": (1.0, 0.30, 0.0),
    "gloss": (0.0, 0.08, 0.0),
    "glow": (0.0, 0.40, 1.0),
}


def srgb_to_linear(c) -> np.ndarray:
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


# ---------------------------------------------------------------- primitives
# A part is (points Nx3, triangles Mx3). Every primitive is a closed solid, so its
# winding can be checked with the signed volume (see _outward).

def _outward(p: np.ndarray, f: np.ndarray):
    a, b, c = p[f[:, 0]], p[f[:, 1]], p[f[:, 2]]
    keep = np.linalg.norm(np.cross(b - a, c - a), axis=1) > 1e-12  # drop pole slivers
    f = f[keep]
    a, b, c = p[f[:, 0]], p[f[:, 1]], p[f[:, 2]]
    if np.einsum("ij,ij->", a, np.cross(b, c)) < 0:
        f = f[:, ::-1]
    return p, f


def _quads(q) -> np.ndarray:
    q = np.asarray(q)
    return np.concatenate([q[:, [0, 1, 2]], q[:, [0, 2, 3]]])


def bevel_box(size, bevel=0.008):
    """Box with chamfered edges and corners, centred on the origin."""
    h = np.asarray(size, dtype=np.float64) / 2
    b = min(bevel, h.min() * 0.9)
    pts, idx = [], {}
    for sx in (-1, 1):
        for sy in (-1, 1):
            for sz in (-1, 1):
                s = np.array([sx, sy, sz])
                for axis in range(3):
                    v = s * (h - b)
                    v[axis] = s[axis] * h[axis]
                    idx[(sx, sy, sz, axis)] = len(pts)
                    pts.append(v)
    p = np.array(pts)
    tris = []

    def add(poly):
        # Convex solid: orient each face away from the centre.
        a, bb, c = p[poly[0]], p[poly[1]], p[poly[2]]
        if np.dot(np.cross(bb - a, c - a), p[poly].mean(axis=0)) < 0:
            poly = poly[::-1]
        tris.extend([poly[0], poly[i], poly[i + 1]] for i in range(1, len(poly) - 1))

    def corner(axis_vals):
        return tuple(axis_vals)

    for axis in range(3):
        o1, o2 = [a for a in range(3) if a != axis]
        for s in (-1, 1):  # the six big faces
            ring = []
            for s1, s2 in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
                sg = [0, 0, 0]
                sg[axis], sg[o1], sg[o2] = s, s1, s2
                ring.append(idx[(*sg, axis)])
            add(ring)
        for s1 in (-1, 1):  # the twelve edge chamfers (edge runs along `axis`)
            for s2 in (-1, 1):
                lo, hi = [0, 0, 0], [0, 0, 0]
                lo[axis], hi[axis] = -1, 1
                lo[o1] = hi[o1] = s1
                lo[o2] = hi[o2] = s2
                add([idx[(*lo, o1)], idx[(*hi, o1)], idx[(*hi, o2)], idx[(*lo, o2)]])
    for sx in (-1, 1):  # the eight corner triangles
        for sy in (-1, 1):
            for sz in (-1, 1):
                add([idx[(sx, sy, sz, a)] for a in range(3)])
    return _outward(p, np.array(tris))


def lathe(profile, segments=20):
    """Revolve a (radius, y) profile around the Y axis. Start and end on the axis."""
    prof = np.asarray(profile, dtype=np.float64)
    ang = np.linspace(0, 2 * math.pi, segments, endpoint=False)
    p = np.stack([
        np.outer(prof[:, 0], np.cos(ang)),
        np.repeat(prof[:, 1][:, None], segments, axis=1),
        np.outer(prof[:, 0], np.sin(ang)),
    ], axis=-1).reshape(-1, 3)
    j, i = np.meshgrid(np.arange(len(prof) - 1), np.arange(segments), indexing="ij")
    i2 = (i + 1) % segments
    q = np.stack([j * segments + i, (j + 1) * segments + i,
                  (j + 1) * segments + i2, j * segments + i2], axis=-1).reshape(-1, 4)
    return _outward(p, _quads(q))


def sphere(radius, segments=16, rings=10):
    t = np.linspace(-math.pi / 2, math.pi / 2, rings + 1)
    return lathe(np.stack([radius * np.cos(t), radius * np.sin(t)], axis=1), segments)


def extrude(poly, depth):
    """Extrude a 2D polygon (star-shaped about its centroid) along Z, centred."""
    poly = np.asarray(poly, dtype=np.float64)
    n = len(poly)
    back = np.column_stack([poly, np.full(n, -depth / 2)])
    front = np.column_stack([poly, np.full(n, depth / 2)])
    cen = poly.mean(axis=0)
    p = np.vstack([back, front, [[*cen, -depth / 2]], [[*cen, depth / 2]]])
    i = np.arange(n)
    i2 = (i + 1) % n
    sides = _quads(np.stack([i, i2, i2 + n, i + n], axis=1))
    caps = np.concatenate([
        np.stack([np.full(n, 2 * n), i2, i], axis=1),
        np.stack([np.full(n, 2 * n + 1), i + n, i2 + n], axis=1),
    ])
    return _outward(p, np.concatenate([sides, caps]))


def torus(major, minor, segments=28, sides=10):
    """Ring in the XY plane."""
    u = np.linspace(0, 2 * math.pi, segments, endpoint=False)[:, None]
    v = np.linspace(0, 2 * math.pi, sides, endpoint=False)[None, :]
    r = np.broadcast_to(major + minor * np.cos(v), (segments, sides))
    p = np.stack([r * np.cos(u), r * np.sin(u),
                  np.broadcast_to(minor * np.sin(v), r.shape)], axis=-1).reshape(-1, 3)
    a, b = np.meshgrid(np.arange(segments), np.arange(sides), indexing="ij")
    a2, b2 = (a + 1) % segments, (b + 1) % sides
    q = np.stack([a * sides + b, a2 * sides + b, a2 * sides + b2, a * sides + b2],
                 axis=-1).reshape(-1, 4)
    return _outward(p, _quads(q))


def octahedron(rx, ry, rz):
    p = np.array([[rx, 0, 0], [-rx, 0, 0], [0, ry, 0], [0, -ry, 0], [0, 0, rz], [0, 0, -rz]],
                 dtype=np.float64)
    f = np.array([[0, 2, 4], [2, 1, 4], [1, 3, 4], [3, 0, 4],
                  [2, 0, 5], [1, 2, 5], [3, 1, 5], [0, 3, 5]])
    return _outward(p, f)


def star_poly(outer, inner, points=5):
    a = np.linspace(0, 2 * math.pi, points * 2, endpoint=False) + math.pi / 2
    r = np.where(np.arange(points * 2) % 2 == 0, outer, inner)
    return np.stack([r * np.cos(a), r * np.sin(a)], axis=1)


def rot(axis: str, deg: float) -> np.ndarray:
    c, s = math.cos(math.radians(deg)), math.sin(math.radians(deg))
    return {
        "x": np.array([[1, 0, 0], [0, c, -s], [0, s, c]]),
        "y": np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]]),
        "z": np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]]),
    }[axis]


def placed(part, at=(0, 0, 0), r: np.ndarray | None = None):
    p, f = part
    if r is not None:
        p = p @ r.T
    return p + np.asarray(at, dtype=np.float64), f


# ---------------------------------------------------------------- shading
def corner_normals(p: np.ndarray, f: np.ndarray, crease_deg: float) -> np.ndarray:
    """Per-corner normals: area-weighted average over the faces that meet at the vertex
    within the crease angle. Area weighting keeps big flat faces flat next to a bevel."""
    a, b, c = p[f[:, 0]], p[f[:, 1]], p[f[:, 2]]
    weighted = np.cross(b - a, c - a)  # length = 2 * area
    unit = weighted / np.linalg.norm(weighted, axis=1, keepdims=True)
    _, weld = np.unique(np.round(p, 5), axis=0, return_inverse=True)
    weld = weld.reshape(-1)[f]
    at_vertex: dict[int, list[int]] = {}
    for fi, tri in enumerate(weld):
        for v in tri:
            at_vertex.setdefault(int(v), []).append(fi)
    limit = math.cos(math.radians(crease_deg))
    out = np.empty((len(f), 3, 3))
    for fi, tri in enumerate(weld):
        for k, v in enumerate(tri):
            near = np.array(at_vertex[int(v)])
            near = near[unit[near] @ unit[fi] >= limit]
            n = weighted[near].sum(axis=0)
            out[fi, k] = n / np.linalg.norm(n)
    return out


class Model:
    """Collects parts per (node, material) and writes a binary glTF. Hue comes from vertex
    colours, except that glTF emission is per material, so each glow colour gets its own."""

    def __init__(self):
        self.buf: dict[tuple[str, str, tuple], list] = {}

    def add(self, node, material, colour, part, crease=50.0):
        p, f = part
        n = corner_normals(p, f, crease)
        col = np.broadcast_to(srgb_to_linear(colour), (len(f) * 3, 3))
        emissive = tuple(float(c) for c in colour) if MATERIALS[material][2] else ()
        self.buf.setdefault((node, material, emissive), []).append((p[f].reshape(-1, 3), n.reshape(-1, 3), col))

    def triangles(self) -> int:
        return sum(len(c[0]) // 3 for chunks in self.buf.values() for c in chunks)

    def write(self, path: Path) -> None:
        blob = bytearray()
        views, accessors, mats, mat_index = [], [], [], {}
        prims: dict[str, list] = {"Body": [], "Lid": []}

        def push(arr: np.ndarray, kind: str, minmax=False) -> int:
            raw = arr.astype("<f4").tobytes()
            views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw), "target": 34962})
            blob.extend(raw)
            acc = {"bufferView": len(views) - 1, "componentType": 5126, "count": len(arr), "type": kind}
            if minmax:
                acc["min"], acc["max"] = arr.min(axis=0).tolist(), arr.max(axis=0).tolist()
            accessors.append(acc)
            return len(accessors) - 1

        for (node, material, emissive), chunks in sorted(self.buf.items()):
            key = (material, emissive)
            if key not in mat_index:
                metallic, rough, strength = MATERIALS[material]
                mat_index[key] = len(mats)
                m = {"name": material, "pbrMetallicRoughness": {
                    "baseColorFactor": [1, 1, 1, 1], "metallicFactor": metallic, "roughnessFactor": rough}}
                if emissive:
                    m["name"] = "glow_%02x%02x%02x" % tuple(round(min(c, 1.0) * 255) for c in emissive)
                    m["emissiveFactor"] = np.minimum(srgb_to_linear(emissive) * strength, 1.0).tolist()
                mats.append(m)
            rows = np.concatenate([np.hstack(c) for c in chunks]).astype("<f4")
            rows, index = np.unique(rows, axis=0, return_inverse=True)  # share identical vertices
            pos, nrm, col = rows[:, 0:3], rows[:, 3:6], rows[:, 6:9]
            raw = index.reshape(-1).astype("<u4").tobytes()
            views.append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(raw), "target": 34963})
            blob.extend(raw)
            accessors.append({"bufferView": len(views) - 1, "componentType": 5125, "count": index.size, "type": "SCALAR"})
            prims[node].append({
                "indices": len(accessors) - 1,
                "attributes": {"POSITION": push(pos, "VEC3", True), "NORMAL": push(nrm, "VEC3"),
                               "COLOR_0": push(col, "VEC3")},
                "material": mat_index[key]})

        # Lid animation: closed -> overshoot -> settled open (rotation about -X at the hinge).
        def quat(deg):
            h = math.radians(-deg) / 2
            return [math.sin(h), 0.0, 0.0, math.cos(h)]

        keys = [(0.0, 0.0), (0.12, -3.0), (0.42, LID_OPEN_DEG + 9), (0.60, LID_OPEN_DEG - 3), (0.75, LID_OPEN_DEG)]
        times = np.array([[k[0]] for k in keys])
        t_acc = push(times, "SCALAR", True)
        q_acc = push(np.array([quat(k[1]) for k in keys]), "VEC4")
        for i in (t_acc, q_acc):
            views[accessors[i]["bufferView"]].pop("target")

        gltf = {
            "asset": {"version": "2.0", "generator": "crawl-live scripts/model_build.py"},
            "scene": 0,
            "scenes": [{"name": path.stem, "nodes": [0]}],
            "nodes": [
                {"name": "LootBox", "children": [1, 2]},
                {"name": "Body", "mesh": 0},
                {"name": "Lid", "mesh": 1, "translation": list(HINGE), "rotation": quat(LID_OPEN_DEG)},
            ],
            "meshes": [{"name": "Body", "primitives": prims["Body"]}, {"name": "Lid", "primitives": prims["Lid"]}],
            "materials": mats,
            "animations": [{"name": "open",
                            "samplers": [{"input": t_acc, "output": q_acc, "interpolation": "LINEAR"}],
                            "channels": [{"sampler": 0, "target": {"node": 2, "path": "rotation"}}]}],
            "accessors": accessors,
            "bufferViews": views,
            "buffers": [{"byteLength": len(blob)}],
        }
        js = json.dumps(gltf, separators=(",", ":")).encode()
        js += b" " * (-len(js) % 4)
        blob.extend(b"\0" * (-len(blob) % 4))
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("wb") as fh:
            fh.write(struct.pack("<4sII", b"glTF", 2, 12 + 8 + len(js) + 8 + len(blob)))
            fh.write(struct.pack("<I4s", len(js), b"JSON") + js)
            fh.write(struct.pack("<I4s", len(blob), b"BIN\0") + bytes(blob))


# ---------------------------------------------------------------- the loot box
def build_loot_box(tier: str, trim) -> Model:
    m = Model()
    rng = np.random.default_rng(7)
    panel = np.array(PANEL[tier])
    trim = np.asarray(trim, dtype=np.float64) / 255.0
    dark = panel * 0.35
    gold = (1.0, 0.77, 0.25)
    warm = (1.0, 0.86, 0.55)

    w, d, base, top = 0.90, 0.60, 0.05, 0.50  # outer width, depth, underside, rim height
    wall = 0.04

    # --- Body: plank walls, floor, feet -------------------------------------------
    plank_h = (top - base) / 3
    for row in range(3):
        y = base + plank_h * (row + 0.5)
        shade = panel * (0.86 + 0.14 * rng.random())
        for sz in (-1, 1):
            m.add("Body", "lacquer", shade, placed(bevel_box((w, plank_h, wall), 0.007), (0, y, sz * (d - wall) / 2)))
        shade = panel * (0.86 + 0.14 * rng.random())
        for sx in (-1, 1):
            m.add("Body", "lacquer", shade,
                  placed(bevel_box((wall, plank_h, d - 2 * wall), 0.007), (sx * (w - wall) / 2, y, 0)))
    m.add("Body", "lacquer", dark, placed(bevel_box((w - wall, wall, d - wall), 0.004), (0, base + wall / 2, 0)))
    foot = [(0, 0), (0.034, 0), (0.05, 0.018), (0.046, 0.034), (0.03, base + 0.004), (0, base + 0.004)]
    for sx in (-1, 1):
        for sz in (-1, 1):
            m.add("Body", "metal", trim * 0.8, placed(lathe(foot, 16), (sx * 0.38, 0, sz * 0.23)))
            # corner posts
            m.add("Body", "metal", trim,
                  placed(bevel_box((0.07, top - base + 0.012, 0.07), 0.012), (sx * (w / 2 - 0.02), (top + base) / 2, sz * (d / 2 - 0.02))))

    # --- Body: rim frame, straps, rivets ------------------------------------------
    for sz in (-1, 1):
        m.add("Body", "metal", trim, placed(bevel_box((w + 0.03, 0.04, 0.058), 0.008), (0, top - 0.02, sz * (d / 2 - 0.016))))
    for sx in (-1, 1):
        m.add("Body", "metal", trim, placed(bevel_box((0.058, 0.04, d + 0.03), 0.008), (sx * (w / 2 - 0.016), top - 0.02, 0)))
    band_x, band_w, proud = 0.30, 0.07, 0.012
    for sx in (-1, 1):
        x = sx * band_x
        for sz in (-1, 1):
            m.add("Body", "metal", trim,
                  placed(bevel_box((band_w, top - base - 0.03, proud * 2), 0.005), (x, (top + base) / 2 - 0.015, sz * d / 2)))
            for y in (0.13, 0.25, 0.37):
                m.add("Body", "metal", trim * 1.0, placed(sphere(0.013, 10, 6), (x, y, sz * (d / 2 + proud))))
        m.add("Body", "metal", trim, placed(bevel_box((band_w, proud * 2, d), 0.005), (x, base, 0)))

    # --- Body: marquee bulbs along the front (every second one lit) ---------------
    bulb_x = [k * 0.075 for k in range(-3, 4)] + [-0.375, 0.375]
    for n, x in enumerate(sorted(bulb_x)):
        lit = n % 2 == 0
        m.add("Body", "glow" if lit else "gloss", warm if lit else (0.45, 0.30, 0.12),
              placed(sphere(0.017, 12, 8), (x, 0.425, d / 2 + 0.008)), crease=80)
        m.add("Body", "metal", trim * 0.7, placed(lathe([(0, 0), (0.021, 0), (0.021, 0.008), (0, 0.008)], 12),
                                                  (x, 0.425, d / 2 - 0.003), rot("x", 90)))

    # --- Body: lock plate with the show's star -------------------------------------
    m.add("Body", "metal", trim, placed(bevel_box((0.19, 0.20, 0.03), 0.012), (0, 0.27, d / 2 + 0.012)))
    m.add("Body", "metal", trim * 0.55, placed(bevel_box((0.15, 0.16, 0.03), 0.01), (0, 0.27, d / 2 + 0.016)))
    m.add("Body", "glow", trim, placed(extrude(star_poly(0.062, 0.026), 0.02), (0, 0.268, d / 2 + 0.032)), crease=30)

    # --- Body: ring handles on the sides -------------------------------------------
    for sx in (-1, 1):
        x = sx * (w / 2 + 0.012)
        m.add("Body", "metal", trim, placed(bevel_box((0.03, 0.05, 0.11), 0.008), (x, 0.33, 0)))
        ring = placed(torus(0.062, 0.011), r=rot("x", sx * 14) @ rot("y", 90))
        m.add("Body", "metal", trim * 0.9, placed(ring, (x + sx * 0.03, 0.275, 0)), crease=80)

    # --- Body: the haul (glow, coins, gems) ----------------------------------------
    m.add("Body", "glow", trim, placed(bevel_box((w - 2 * wall, 0.02, d - 2 * wall), 0.002), (0, 0.39, 0)))
    coin = lathe([(0, 0), (0.031, 0), (0.035, 0.004), (0.035, 0.008), (0.031, 0.012), (0, 0.012)], 14)
    for _ in range(60):
        x, z = rng.uniform(-0.35, 0.35), rng.uniform(-0.20, 0.20)
        y = 0.40 + 0.085 * math.exp(-(x / 0.24) ** 2 - (z / 0.15) ** 2) + rng.uniform(0, 0.025)
        r = rot("y", rng.uniform(0, 360)) @ rot("x", rng.uniform(-32, 32))
        m.add("Body", "metal", np.array(gold) * rng.uniform(0.85, 1.0), placed(coin, (x, y, z), r), crease=40)
    gems = [((0.35, 0.95, 1.0), (-0.16, 0.50, 0.05)), ((1.0, 0.35, 0.75), (0.13, 0.505, -0.04)),
            ((0.45, 1.0, 0.5), (0.02, 0.52, 0.09)), ((1.0, 0.9, 0.35), (0.25, 0.47, 0.08))]
    for colour, at in gems:
        r = rot("z", rng.uniform(-35, 35)) @ rot("y", rng.uniform(0, 360))
        m.add("Body", "gloss", colour, placed(octahedron(0.028, 0.042, 0.028), at, r), crease=10)

    # --- Lid (local space: hinge line on the X axis, lid runs towards +Z) ----------
    arch_r, arch_h = d / 2, 0.23
    to_lid = np.array([[0, 0, 1], [0, 1, 0], [1, 0, 0]], dtype=np.float64)  # (u, v, w) -> (w, v, u)

    def arch(width, grow, x=0.0, start=0.0):
        t = np.linspace(start, math.pi - start, 25)
        poly = np.stack([(arch_r + grow) * np.cos(t), (arch_h + grow) * np.sin(t)], axis=1)
        return placed(extrude(poly, width), (x, 0.03, arch_r), to_lid)

    m.add("Lid", "lacquer", panel * 0.95, arch(w - 0.01, 0.0), crease=40)
    m.add("Lid", "metal", trim, placed(bevel_box((w + 0.03, 0.036, d + 0.03), 0.008), (0, 0.018, arch_r)))
    m.add("Lid", "lacquer", dark, placed(bevel_box((w - 0.08, 0.01, d - 0.08), 0.003), (0, 0.0, arch_r)))
    for x in (-band_x, band_x):
        m.add("Lid", "metal", trim, arch(band_w, proud, x), crease=40)
        for deg in (22, 56, 90, 124, 158):
            a = math.radians(deg)
            at = (x, 0.03 + (arch_h + proud) * math.sin(a), arch_r + (arch_r + proud) * math.cos(a))
            m.add("Lid", "metal", trim, placed(sphere(0.013, 10, 6), at))
    for sx in (-1, 1):
        m.add("Lid", "metal", trim, arch(0.045, 0.01, sx * (w / 2 - 0.012)), crease=40)
    # latch
    m.add("Lid", "metal", trim, placed(bevel_box((0.11, 0.085, 0.024), 0.008), (0, 0.0, d + 0.022)))
    m.add("Lid", "metal", trim * 0.55, placed(sphere(0.016, 12, 8), (0, -0.012, d + 0.034)))
    # broadcast aerial with an on-air light, leaning forward so it stands up when the lid is open
    lean = rot("x", LID_OPEN_DEG * 0.8)
    foot_at = np.array([0.36, 0.03 + arch_h * math.sin(math.radians(100)), arch_r + arch_r * math.cos(math.radians(100))])
    mast = [(0, 0), (0.032, 0), (0.032, 0.012), (0.011, 0.035), (0.006, 0.05), (0.0045, 0.26), (0, 0.26)]
    m.add("Lid", "metal", (0.75, 0.77, 0.8), placed(lathe(mast, 12), foot_at, lean))
    m.add("Lid", "glow", (1.0, 0.16, 0.12), placed(sphere(0.024, 14, 10), foot_at + lean @ np.array([0, 0.275, 0])), crease=80)
    return m


def main() -> None:
    tiers = json.loads(LOOT_BOXES.read_text())
    for tier, spec in tiers.items():
        model = build_loot_box(tier, spec["colour"])
        path = OUT_DIR / f"loot_box_{tier}.glb"
        model.write(path)
        print(f"✅ {path.relative_to(ROOT)}  {model.triangles():,} triangles  {path.stat().st_size / 1024:.0f} KB")


if __name__ == "__main__":
    main()

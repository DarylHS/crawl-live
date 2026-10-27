"""First-person view (proof of concept): a grid raycaster in the style of Wolfenstein 3D.

The rules don't change. The player still moves one tile per turn; this module only
draws the dungeon from their eyes. Walls, floors and ceilings are textured with
pixel art generated in code (no asset files), and monsters, items and the pet are
billboard sprites that always face the camera. The scene renders at 320 x 200 and
is scaled up with hard pixel edges for the retro look.

Facing is one of four directions (0 north, 1 east, 2 south, 3 west); the camera
glides between tiles and turns so each step reads as movement, not a jump cut.
"""
import math

import numpy as np
import pygame

from .. import config as C
from ..dungeon import STAIRS, WALL
from ..items import ITEMS, glyph

VIEW_W, VIEW_H = 320, 200
TEX = 64
LIGHT = C.FOV_RADIUS + 0.5          # distance at which everything fades to black
PLANE = 0.70                        # camera plane length: about a 70 degree field of view
DIRS = ((0, -1), (1, 0), (0, 1), (-1, 0))
COMPASS = "NESW"

# Tint per floor so each one has its own mood (grey stone down to infernal red).
DEPTH_TINT = [(1.0, 1.0, 1.0), (1.0, 0.95, 0.82), (0.86, 1.0, 0.88),
              (1.0, 0.84, 0.84), (0.84, 0.86, 1.05), (1.05, 0.72, 0.66)]

# Texture slots in the stacked texture array.
T_BRICK, T_SAFE_WALL, T_FLOOR, T_SAFE_FLOOR, T_STAIRS, T_CEIL = range(6)
TIER_SCALE = {"opening": 0.85, "featured": 0.95, "headliner": 1.0}   # boss tiers loom larger
TIER_OUTLINE = {"opening": (110, 170, 240), "featured": (255, 196, 64), "headliner": (235, 80, 80)}


# --- Procedural textures ----------------------------------------------------

def _clip(a):
    return np.clip(a, 0, 255).astype(np.uint8)


def _bricks(rng, base, mortar=(30, 28, 34), bh=16, bw=32):
    t = np.empty((TEX, TEX, 3), float)
    for row in range(TEX // bh):
        y0, offset = row * bh, (bw // 2) * (row % 2)
        for bx in range(-1, TEX // bw + 1):
            x0 = bx * bw + offset
            lo, hi = max(x0, 0), min(x0 + bw, TEX)
            if lo < hi:
                t[y0:y0 + bh, lo:hi] = np.array(base) * rng.uniform(0.78, 1.08)
        t[y0:y0 + bh] += np.linspace(14, -18, bh)[:, None, None]   # bevel: lit top, shaded bottom
        t[y0] = mortar
        for x0 in range(offset, TEX, bw):
            t[y0:y0 + bh, x0] = mortar
    t += rng.integers(-10, 11, (TEX, TEX, 1))
    return t


def _tiles(rng, a, b, size, grout):
    y, x = np.mgrid[0:TEX, 0:TEX]
    checker = ((x // size + y // size) % 2)[..., None]
    t = np.where(checker, np.array(a, float), np.array(b, float))
    t += rng.integers(-6, 7, (TEX, TEX, 1))
    t[(x % size == 0) | (y % size == 0)] = grout
    return t


def _flagstones(rng, base, grout=(22, 20, 26)):
    t = np.empty((TEX, TEX, 3), float)
    t[:] = np.array(base) * rng.uniform(0.9, 1.05)
    y, x = np.mgrid[0:TEX, 0:TEX]
    t += (8 * np.sin(x / 7.0) * np.cos(y / 9.0))[..., None]   # gentle unevenness, no seam down the middle
    t += rng.integers(-12, 13, (TEX, TEX, 1))
    t[[0, 63]] = grout
    t[:, [0, 63]] = grout
    return t


def _stairs():
    y, x = np.mgrid[0:TEX, 0:TEX]
    d = np.maximum(abs(x - 31.5), abs(y - 31.5))
    glow = np.clip(1 - d / 34, 0, 1)[..., None]
    ring = ((d.astype(int) % 8) < 2)[..., None]
    gold = np.array([255, 190, 60], float)
    return np.where(ring, gold * (0.5 + 0.5 * glow), np.array([30, 24, 14], float) + 60 * glow)


def _ceiling(rng):
    t = np.full((TEX, TEX, 3), (34, 31, 40), float) + rng.integers(-5, 6, (TEX, TEX, 1))
    t[:, :2] *= 0.75
    t[:2] *= 0.75
    return t


def make_textures(depth):
    """All six textures for a floor as one (6, 64, 64, 3) uint8 array."""
    rng = np.random.default_rng(1000 + depth)
    tint = np.array(DEPTH_TINT[(depth - 1) % len(DEPTH_TINT)])
    texs = [_bricks(rng, (112, 104, 120)) * tint,
            _tiles(rng, (178, 214, 188), (160, 200, 174), 16, (90, 120, 100)),
            _flagstones(rng, (74, 70, 82)) * tint,
            _tiles(rng, (58, 110, 80), (42, 84, 62), 16, (28, 52, 40)),
            _stairs(),
            _ceiling(rng) * tint]
    return np.stack([_clip(t) for t in texs])


# --- Sprites ------------------------------------------------------------------

def _shade(c, k):
    return tuple(max(0, min(255, int(v * k))) for v in c)


def _biped(s, c, robe=False, big=False, hood=False, horns=False, crown=False, hat=False,
           ribs=False, tie=False, staff=False, glasses=False):
    dark, light = _shade(c, 0.6), _shade(c, 1.2)
    w = 4 if big else 0                                  # extra width for big bodies
    if robe:
        pygame.draw.polygon(s, dark, [(10 - w, 30), (22 + w, 30), (19 + w // 2, 13), (13 - w // 2, 13)])
    else:
        pygame.draw.rect(s, dark, (11 - w // 2, 23, 4, 8))
        pygame.draw.rect(s, dark, (17 + w // 2, 23, 4, 8))
    pygame.draw.ellipse(s, c, (9 - w, 12, 14 + 2 * w, 14))
    pygame.draw.rect(s, c, (6 - w, 14, 4, 10))
    pygame.draw.rect(s, c, (22 + w, 14, 4, 10))
    pygame.draw.circle(s, light, (16, 8), 5)
    if hood:
        pygame.draw.polygon(s, dark, [(10, 12), (22, 12), (19, 1), (13, 1)])
        pygame.draw.rect(s, (20, 14, 24), (13, 6, 6, 5))
    if ribs:
        for y in (15, 18, 21):
            pygame.draw.line(s, dark, (12, y), (20, y))
    if tie:
        pygame.draw.polygon(s, (240, 240, 240), [(14, 13), (18, 13), (16, 22)])
        pygame.draw.polygon(s, (40, 40, 160), [(15, 14), (17, 14), (16, 21)])
    if horns:
        pygame.draw.polygon(s, (230, 220, 200), [(11, 5), (13, 2), (9, -2)])
        pygame.draw.polygon(s, (230, 220, 200), [(21, 5), (19, 2), (23, -2)])
    if crown:
        pygame.draw.polygon(s, (255, 205, 60), [(11, 4), (21, 4), (21, 0), (19, 2), (16, -1), (13, 2), (11, 0)])
    if hat:
        pygame.draw.ellipse(s, (250, 200, 40), (9, 1, 14, 7))
        pygame.draw.rect(s, (250, 200, 40), (8, 5, 16, 2))
    if staff:
        pygame.draw.line(s, (150, 110, 70), (27, 4), (27, 30), 2)
        pygame.draw.circle(s, (180, 255, 200), (27, 4), 3)
    eye_y = 9 if hood else 8
    eye = (255, 230, 120) if hood else (255, 255, 255)
    for ex in (14, 18):
        s.set_at((ex, eye_y), eye)
    if glasses:
        pygame.draw.circle(s, (30, 30, 30), (14, 8), 2, 1)
        pygame.draw.circle(s, (30, 30, 30), (18, 8), 2, 1)


def _beast(s, c, ears="pointy", tail=False, small=False):
    dark, light = _shade(c, 0.6), _shade(c, 1.2)
    off = 6 if small else 0
    pygame.draw.ellipse(s, c, (7 + off // 2, 14 + off, 18 - off, 13 - off // 2))
    for lx in (10, 19):
        pygame.draw.rect(s, dark, (lx + off // 3, 25, 3, 6))
    hx, hy = 16, 13 + off
    if ears == "pointy":
        pygame.draw.polygon(s, c, [(hx - 6, hy - 2), (hx - 3, hy - 4), (hx - 6, hy - 10)])
        pygame.draw.polygon(s, c, [(hx + 6, hy - 2), (hx + 3, hy - 4), (hx + 6, hy - 10)])
    elif ears == "floppy":
        pygame.draw.ellipse(s, dark, (hx - 10, hy - 5, 5, 10))
        pygame.draw.ellipse(s, dark, (hx + 5, hy - 5, 5, 10))
    elif ears == "round":
        pygame.draw.circle(s, light, (hx - 6, hy - 5), 4)
        pygame.draw.circle(s, light, (hx + 6, hy - 5), 4)
    pygame.draw.circle(s, light, (hx, hy), 6 - off // 3)
    pygame.draw.circle(s, (30, 20, 20), (hx, hy + 3), 1)
    for ex in (hx - 3, hx + 2):
        s.set_at((ex, hy - 1), (255, 255, 255))
        s.set_at((ex, hy), (20, 10, 10))
    if tail:
        pygame.draw.lines(s, (220, 160, 170), False, [(24, 26), (29, 22), (30, 16), (27, 12)], 1)


def _bird(s, c):
    dark, light = _shade(c, 0.6), _shade(c, 1.25)
    pygame.draw.ellipse(s, dark, (6, 14, 8, 12))
    pygame.draw.ellipse(s, dark, (18, 14, 8, 12))
    pygame.draw.ellipse(s, c, (10, 12, 12, 16))
    pygame.draw.circle(s, light, (16, 10), 5)
    pygame.draw.polygon(s, (250, 170, 60), [(15, 11), (17, 11), (16, 14)])
    for ex in (14, 18):
        s.set_at((ex, 9), (20, 10, 10))
    pygame.draw.line(s, (250, 170, 60), (13, 28), (13, 31))
    pygame.draw.line(s, (250, 170, 60), (19, 28), (19, 31))


def _robot(s, c):
    dark, light = _shade(c, 0.55), _shade(c, 1.25)
    pygame.draw.ellipse(s, dark, (3, 20, 26, 11))
    pygame.draw.ellipse(s, c, (3, 17, 26, 11))
    pygame.draw.ellipse(s, light, (8, 18, 16, 5))
    pygame.draw.circle(s, (255, 60, 60), (16, 24), 2)
    for x in range(6, 27, 3):
        pygame.draw.line(s, (60, 60, 60), (x, 29), (x - 1, 31))


def _ghost(s, c):
    light = _shade(c, 1.3)
    pygame.draw.circle(s, c, (16, 11), 9)
    pygame.draw.polygon(s, c, [(7, 11), (25, 11), (27, 30), (22, 26), (18, 31), (14, 26), (10, 31), (5, 26)])
    pygame.draw.ellipse(s, (240, 240, 255), (11, 8, 4, 6))
    pygame.draw.ellipse(s, (240, 240, 255), (17, 8, 4, 6))
    pygame.draw.circle(s, light, (16, 11), 9, 1)


def _blob(s, c, crown=False, wrap=False, stitches=False):
    dark, light = _shade(c, 0.6), _shade(c, 1.2)
    pygame.draw.ellipse(s, c, (2, 12, 28, 20))
    pygame.draw.ellipse(s, light, (7, 4, 18, 16))
    for ex in (12, 19):
        pygame.draw.circle(s, (255, 255, 255), (ex, 11), 2)
        s.set_at((ex, 11), (10, 10, 10))
    pygame.draw.arc(s, dark, (11, 12, 10, 6), 3.4, 6.0, 1)
    if stitches:
        pygame.draw.line(s, dark, (6, 20), (26, 24))
        for x in range(8, 26, 4):
            pygame.draw.line(s, dark, (x, 19 + (x - 6) // 5), (x + 1, 23 + (x - 6) // 5))
    if wrap:                                             # cling film, kept inside the body
        body = pygame.surfarray.array_alpha(s) > 0
        for k in range(-20, 32, 7):
            pygame.draw.line(s, (240, 250, 255), (k, 31), (k + 18, 4))
        a = pygame.surfarray.pixels_alpha(s)
        a[~body] = 0
        del a
    if crown:
        pygame.draw.polygon(s, (255, 205, 60), [(9, 6), (23, 6), (23, 0), (20, 3), (16, -1), (12, 3), (9, 0)])


BODIES = {
    "gnawer": lambda s, c: _beast(s, c, "round", tail=True, small=True),
    "goblin": lambda s, c: _biped(s, c),
    "vacbot": _robot,
    "skeleton": lambda s, c: _biped(s, c, ribs=True),
    "brute": lambda s, c: _biped(s, c, big=True),
    "cultist": lambda s, c: _biped(s, c, robe=True, hood=True),
    "golem": lambda s, c: _blob(s, c, stitches=True),
    "stalker": _ghost,
    "boss_1": lambda s, c: _blob(s, c, crown=True),
    "boss_2": lambda s, c: _biped(s, c, robe=True, glasses=True),
    "boss_3": lambda s, c: _biped(s, c, big=True, hat=True),
    "boss_4": lambda s, c: _biped(s, c, robe=True, hood=True, horns=True, staff=True),
    "boss_5": lambda s, c: _blob(s, c, wrap=True),
    "boss_6": lambda s, c: _biped(s, c, big=True, horns=True, tie=True),
    "cat": lambda s, c: _beast(s, c, "pointy"),
    "dog": lambda s, c: _beast(s, c, "floppy"),
    "budgie": _bird,
    "mouse": lambda s, c: _beast(s, c, "round", tail=True, small=True),
}


def creature_sprite(key, colour, outline=(14, 12, 18)):
    """A 32 x 32 pixel-art creature: a body plan drawn in its colour, lit from above, outlined
    (bosses get their tier's colour as the outline)."""
    s = pygame.Surface((32, 32), pygame.SRCALPHA)
    BODIES.get(key, lambda s, c: _biped(s, c))(s, colour)
    rgb = pygame.surfarray.array3d(s).astype(float)
    alpha = pygame.surfarray.array_alpha(s) > 0
    rgb *= np.linspace(1.1, 0.75, 32)[None, :, None]          # light from above
    pad = np.pad(alpha, 1)
    edge = (pad[:-2, 1:-1] | pad[2:, 1:-1] | pad[1:-1, :-2] | pad[1:-1, 2:]) & ~alpha
    rgb[edge] = outline
    out = pygame.Surface((32, 32), pygame.SRCALPHA)
    pygame.surfarray.blit_array(out, _clip(rgb))
    a = pygame.surfarray.pixels_alpha(out)
    a[:] = np.where(alpha | edge, 255, 0)
    del a
    return out


def glyph_sprite(font, ch, colour):
    """An item: its glyph on a small shadow, lying on the floor."""
    surf = pygame.Surface((16, 16), pygame.SRCALPHA)
    pygame.draw.ellipse(surf, (0, 0, 0, 120), (2, 11, 12, 5))
    img = font.render(ch, True, colour)
    surf.blit(img, img.get_rect(center=(8, 7)))
    return surf


def stairs_sprite(locked=False):
    """A floating arrow over a stairwell: gold when open, red with a padlock when locked."""
    surf = pygame.Surface((16, 16), pygame.SRCALPHA)
    colour = (235, 80, 80) if locked else (255, 196, 64)
    pygame.draw.polygon(surf, colour, [(3, 5), (13, 5), (8, 13)])
    pygame.draw.polygon(surf, (60, 30, 10), [(3, 5), (13, 5), (8, 13)], 1)
    if locked:
        pygame.draw.rect(surf, (40, 30, 30), (6, 7, 4, 3))
        pygame.draw.arc(surf, (40, 30, 30), (6, 4, 4, 5), 0, 3.15, 1)
    return surf


def furniture_sprite(kind):
    """Safe-room furniture: a bed, a crafting bench and the shop counter."""
    s = pygame.Surface((32, 32), pygame.SRCALPHA)
    if kind == "bed":
        pygame.draw.rect(s, (90, 60, 40), (2, 18, 28, 8))
        pygame.draw.rect(s, (150, 180, 230), (3, 13, 26, 7))
        pygame.draw.rect(s, (240, 240, 240), (4, 11, 8, 5))
        for x in (3, 27):
            pygame.draw.rect(s, (70, 45, 30), (x, 24, 2, 8))
    elif kind == "bench":
        pygame.draw.rect(s, (160, 115, 70), (1, 14, 30, 5))
        for x in (3, 26):
            pygame.draw.rect(s, (110, 80, 50), (x, 19, 3, 13))
        pygame.draw.rect(s, (170, 170, 180), (6, 9, 7, 5))          # vice
        pygame.draw.line(s, (200, 200, 210), (18, 13), (26, 6), 2)  # spanner
    else:
        pygame.draw.rect(s, (120, 90, 140), (0, 14, 32, 18))
        pygame.draw.rect(s, (255, 196, 64), (0, 12, 32, 3))
        pygame.draw.rect(s, (60, 200, 120), (11, 4, 10, 8))         # till
        pygame.draw.rect(s, (20, 40, 30), (13, 6, 6, 3))
    return s


# --- The view -----------------------------------------------------------------

class FirstPersonView:
    def __init__(self):
        self.facing = 1
        self.cam = None                       # [x, y, angle] that glides towards the player
        self._floor_id = None
        self._sprites = {}
        self.font = pygame.font.SysFont("dejavusansmono,menlo,consolas,monospace", 13, bold=True)
        self.big = pygame.font.SysFont("dejavusansmono,menlo,consolas,monospace", 18, bold=True)
        self.item_font = pygame.font.SysFont("dejavusansmono,menlo,consolas,monospace", 12, bold=True)
        self.flash = 0.0
        self._last_hp = None
        ys = np.arange(VIEW_H)[:, None]
        self._ys = ys
        self._row_dist = np.where(ys > VIEW_H / 2, (VIEW_H / 2) / np.maximum(ys - VIEW_H / 2, 1e-6),
                                  (VIEW_H / 2) / np.maximum(VIEW_H / 2 - ys, 1e-6))
        self._camx = 2 * np.arange(VIEW_W) / VIEW_W - 1

    # --- Movement helpers (the rules only ever see move_player(dx, dy)) ---

    def forward(self):
        return DIRS[self.facing]

    def relative(self, move):
        """Map forward/back/left/right to a world step for the current facing."""
        fx, fy = DIRS[self.facing]
        return {"forward": (fx, fy), "back": (-fx, -fy),
                "left": (fy, -fx), "right": (-fy, fx)}[move]

    def turn(self, step):
        self.facing = (self.facing + step) % 4

    def target_ahead(self, world):
        """The monster this step would attack: straight ahead, else front-left or front-right."""
        p, (fx, fy) = world.player, DIRS[self.facing]
        spots = [(p.x + fx, p.y + fy), (p.x + fx + fy, p.y + fy - fx), (p.x + fx - fy, p.y + fy + fx)]
        at = {(m.x, m.y): m for m in world.monsters}
        for s in spots:
            if s in at:
                return at[s], (s[0] - p.x, s[1] - p.y)
        return None, None

    # --- Setup per floor ---

    def _prepare_floor(self, world):
        f = world.floor
        if self._floor_id == id(f):
            return
        self._floor_id = id(f)
        self.textures = make_textures(world.depth)
        tiles = np.array(f.tiles)
        safe = np.array(f.safe)
        self.solid = tiles == WALL
        kind = np.full(tiles.shape, T_FLOOR)
        kind[safe] = T_SAFE_FLOOR
        kind[tiles == STAIRS] = T_STAIRS
        self.floor_kind = kind
        self.safe = safe
        self.cam = None

    def _sprite(self, key, make):
        s = self._sprites.get(key)
        if s is None:
            s = self._sprites[key] = make()
        return s

    # --- Drawing ---

    def update_camera(self, world, dt=1.0):
        """Glide the camera towards the player's tile and facing. dt=1 snaps."""
        p = world.player
        target = [p.x + 0.5, p.y + 0.5, self.facing * math.pi / 2 - math.pi / 2]
        if self.cam is None or dt >= 1:
            self.cam = target
            return
        da = (target[2] - self.cam[2] + math.pi) % (2 * math.pi) - math.pi
        self.cam[0] += (target[0] - self.cam[0]) * dt
        self.cam[1] += (target[1] - self.cam[1]) * dt
        self.cam[2] += da * dt

    def render(self, world):
        """The 3D scene as a 320 x 200 surface."""
        self._prepare_floor(world)
        if self.cam is None:
            self.update_camera(world)
        px, py, ang = self.cam
        dx, dy = math.cos(ang), math.sin(ang)
        plx, ply = -dy * PLANE, dx * PLANE
        rdx = dx + plx * self._camx
        rdy = dy + ply * self._camx

        dist, side, texx, wkind = self._cast(px, py, rdx, rdy)
        frame = self._floor_and_ceiling(px, py, rdx, rdy)
        frame = self._walls(frame, dist, side, texx, wkind)
        surf = pygame.surfarray.make_surface(frame.swapaxes(0, 1))
        self._draw_sprites(surf, world, px, py, dx, dy, plx, ply, dist)
        return surf

    def _cast(self, px, py, rdx, rdy):
        """DDA per column: perpendicular distance, wall side, texture column and kind."""
        solid, safe = self.solid, self.safe
        h, w = solid.shape
        n = len(rdx)
        dist = np.full(n, 1e9)
        side = np.zeros(n, int)
        texx = np.zeros(n, int)
        wkind = np.zeros(n, int)
        max_steps = int(LIGHT * 2) + 2
        for i in range(n):
            rx, ry = rdx[i], rdy[i]
            mx, my = int(px), int(py)
            ddx = abs(1 / rx) if rx else 1e30
            ddy = abs(1 / ry) if ry else 1e30
            if rx < 0:
                sx, sdx = -1, (px - mx) * ddx
            else:
                sx, sdx = 1, (mx + 1 - px) * ddx
            if ry < 0:
                sy, sdy = -1, (py - my) * ddy
            else:
                sy, sdy = 1, (my + 1 - py) * ddy
            prev = (mx, my)
            for _ in range(max_steps):
                prev = (mx, my)
                if sdx < sdy:
                    sdx += ddx
                    mx += sx
                    s = 0
                else:
                    sdy += ddy
                    my += sy
                    s = 1
                if not (0 <= mx < w and 0 <= my < h) or solid[my, mx]:
                    d = (sdx - ddx) if s == 0 else (sdy - ddy)
                    dist[i], side[i] = max(d, 1e-3), s
                    hit = (py + d * ry) if s == 0 else (px + d * rx)
                    tx = int((hit - math.floor(hit)) * TEX)
                    if (s == 0 and rx < 0) or (s == 1 and ry > 0):
                        tx = TEX - 1 - tx
                    texx[i] = tx
                    wkind[i] = T_SAFE_WALL if safe[prev[1], prev[0]] else T_BRICK
                    break
        return dist, side, texx, wkind

    def _fog(self, d):
        return np.clip(1 - d / LIGHT, 0, 1) ** 1.3

    def _floor_and_ceiling(self, px, py, rdx, rdy):
        rd = self._row_dist                                    # (H, 1)
        wx = px + rd * rdx[None, :]
        wy = py + rd * rdy[None, :]
        h, w = self.floor_kind.shape
        cx = np.clip(wx.astype(int), 0, w - 1)
        cy = np.clip(wy.astype(int), 0, h - 1)
        tx = ((wx % 1) * TEX).astype(int) % TEX
        ty = ((wy % 1) * TEX).astype(int) % TEX
        below = self._ys > VIEW_H / 2
        kind = np.where(below, self.floor_kind[cy, cx], T_CEIL)
        frame = self.textures[kind, ty, tx].astype(float)
        frame *= (self._fog(rd) * np.where(below, 1.0, 0.8))[..., None]
        return frame

    def _walls(self, frame, dist, side, texx, wkind):
        line = VIEW_H / dist                                   # (W,)
        top = VIEW_H / 2 - line / 2
        rel = (self._ys - top[None, :]) / line[None, :]        # (H, W) 0..1 inside the wall
        inside = (rel >= 0) & (rel < 1)
        ty = np.clip((rel * TEX).astype(int), 0, TEX - 1)
        cols = self.textures[wkind[None, :], ty, texx[None, :]].astype(float)
        shade = self._fog(dist) * np.where(side == 1, 0.78, 1.0)
        cols *= shade[None, :, None]
        frame[inside] = cols[inside]
        return _clip(frame)

    def _draw_sprites(self, surf, world, px, py, dx, dy, plx, ply, zbuf):
        vis = world.visible
        items = []                                             # (x, y, sprite, scale, lift, extra)
        for (x, y), keys in world.floor_items.items():
            if (x, y) in vis:
                k = keys[-1]
                spr = self._sprite(("item", k), lambda k=k: glyph_sprite(self.item_font, glyph(k),
                                                                          ITEMS[k]["colour"]))
                items.append((x + 0.5, y + 0.5, spr, 0.32, 0.0, None))
        locked = world.stairs_locked or world.exit_sealed
        for sx, sy in world.floor.stairs:
            if (sx, sy) in vis:
                spr = self._sprite(("stairs", locked), lambda: stairs_sprite(locked))
                items.append((sx + 0.5, sy + 0.5, spr, 0.3, 0.55, None))
        for (fx, fy), kind in world.floor.furniture.items():
            if (fx, fy) in vis:
                spr = self._sprite(("furniture", kind), lambda k=kind: furniture_sprite(k))
                items.append((fx + 0.5, fy + 0.5, spr, 0.75, 0.0, None))
        pet = world.active_pet
        if pet and (pet.x, pet.y) in vis:
            spr = self._sprite(("pet", pet.species), lambda: creature_sprite(pet.species, pet.colour))
            items.append((pet.x + 0.5, pet.y + 0.5, spr, 0.5, 0.0, None))
        for m in world.monsters:
            if (m.x, m.y) in vis:
                look = m.base or m.key
                spr = self._sprite(("mon", look, m.tier), lambda m=m, k=look: creature_sprite(
                    k, m.colour, TIER_OUTLINE.get(m.tier, (14, 12, 18))))
                scale = TIER_SCALE.get(m.tier) or 0.62 + 0.03 * min(m.max_hp, 12) / 4
                items.append((m.x + 0.5, m.y + 0.5, spr, scale, 0.0, m))

        inv_det = 1.0 / (plx * dy - dx * ply)
        projected = []
        for x, y, spr, scale, lift, m in items:
            rx, ry = x - px, y - py
            tx = inv_det * (dy * rx - dx * ry)
            tz = inv_det * (-ply * rx + plx * ry)
            if tz > 0.2:
                projected.append((tz, tx, spr, scale, lift, m))
        projected.sort(key=lambda t: -t[0])
        for tz, tx, spr, scale, lift, m in projected:
            screen_x = int(VIEW_W / 2 * (1 + tx / tz))
            size = int(VIEW_H / tz * scale)
            if size < 2 or size > VIEW_H * 3:
                continue
            floor_y = VIEW_H / 2 + (VIEW_H / 2) / tz           # where the floor is at this distance
            y0 = int(floor_y - size - lift * VIEW_H / tz)
            x0 = screen_x - size // 2
            img = pygame.transform.scale(spr, (size, size))
            f = float(self._fog(np.array(tz)))
            v = int(255 * max(0.12, f))
            img.fill((v, v, v, 255), special_flags=pygame.BLEND_RGBA_MULT)
            # Blit runs of columns in front of the walls.
            lo, hi = max(0, x0), min(VIEW_W, x0 + size)
            col = lo
            while col < hi:
                if zbuf[col] <= tz:
                    col += 1
                    continue
                start = col
                while col < hi and zbuf[col] > tz:
                    col += 1
                surf.blit(img, (start, y0), area=(start - x0, 0, col - start, size))
            if m is not None and m.hp < m.max_hp and lo < hi and zbuf[min(max(screen_x, 0), VIEW_W - 1)] > tz:
                bw = max(6, size // 2)
                bx = screen_x - bw // 2
                surf.fill((60, 10, 10), (bx, y0 - 4, bw, 2))
                surf.fill(C.DANGER, (bx, y0 - 4, int(bw * m.hp / m.max_hp), 2))

    # --- Full-resolution overlays ---------------------------------------------

    def draw(self, surface, world, rect, dt=1.0):
        """Render, scale into rect, then draw the minimap, compass and warnings on top."""
        self.update_camera(world, dt)
        scene = self.render(world)
        surface.blit(pygame.transform.scale(scene, rect.size), rect.topleft)
        p = world.player
        if self._last_hp is not None and p.hp < self._last_hp:
            self.flash = 1.0
        self._last_hp = p.hp
        if self.flash > 0.02:
            red = pygame.Surface(rect.size, pygame.SRCALPHA)
            red.fill((200, 20, 20, int(110 * self.flash)))
            surface.blit(red, rect.topleft)
            self.flash *= 0.8
        self._minimap(surface, world, rect)
        self._warnings(surface, world, rect)
        self._ahead(surface, world, rect)

    def _minimap(self, surface, world, rect):
        f = world.floor
        s = 2 if f.width > 80 else 3
        w, h = f.width * s, f.height * s
        x0, y0 = rect.right - w - 10, rect.top + 10
        mm = pygame.Surface((w, h), pygame.SRCALPHA)
        mm.fill((0, 0, 0, 150))
        for y in range(f.height):
            row, seen = f.tiles[y], f.explored[y]
            for x in range(f.width):
                if seen[x] and row[x] != WALL:
                    c = C.ACCENT if row[x] == STAIRS else C.SAFE_LIT if f.safe[y][x] else C.FLOOR_LIT
                    mm.fill(c, (x * s, y * s, s, s))
        for m in world.monsters:
            if (m.x, m.y) in world.visible:
                mm.fill(C.DANGER, (m.x * s, m.y * s, s, s))
        p, (fx, fy) = world.player, DIRS[self.facing]
        cx, cy = p.x * s + s / 2, p.y * s + s / 2
        tip = (cx + fx * 5, cy + fy * 5)
        left = (cx - fx * 3 + fy * 3, cy - fy * 3 - fx * 3)
        right = (cx - fx * 3 - fy * 3, cy - fy * 3 + fx * 3)
        pygame.draw.polygon(mm, (255, 255, 255), [tip, left, right])
        surface.blit(mm, (x0, y0))
        pygame.draw.rect(surface, C.WALL_LIT, (x0 - 1, y0 - 1, w + 2, h + 2), 1)
        label = self.big.render(f"Facing {COMPASS[self.facing]}", True, C.TEXT)
        surface.blit(label, (x0, y0 + h + 6))

    def _warnings(self, surface, world, rect):
        """Red chevrons for monsters right next to you that you can't see."""
        p = world.player
        fx, fy = DIRS[self.facing]
        for m in world.monsters:
            ddx, ddy = m.x - p.x, m.y - p.y
            if max(abs(ddx), abs(ddy)) != 1:
                continue
            fwd = ddx * fx + ddy * fy
            if fwd > 0:
                continue                                  # in front: you can see it
            rgt = ddx * -fy + ddy * fx
            cx, cy = rect.center
            if fwd < 0 and rgt == 0:
                pts = [(cx - 40, rect.bottom - 40), (cx + 40, rect.bottom - 40), (cx, rect.bottom - 12)]
                text, pos = "BEHIND YOU", (cx, rect.bottom - 58)
            elif rgt > 0:
                pts = [(rect.right - 40, cy - 40), (rect.right - 40, cy + 40), (rect.right - 12, cy)]
                text, pos = "RIGHT", (rect.right - 60, cy - 58)
            else:
                pts = [(rect.left + 40, cy - 40), (rect.left + 40, cy + 40), (rect.left + 12, cy)]
                text, pos = "LEFT", (rect.left + 60, cy - 58)
            pygame.draw.polygon(surface, C.DANGER, pts)
            img = self.big.render(text, True, C.DANGER)
            surface.blit(img, img.get_rect(center=pos))

    def _ahead(self, surface, world, rect):
        m, _ = self.target_ahead(world)
        if m is None:
            return
        name = f"{m.name}  {m.hp}/{m.max_hp}"
        img = self.big.render(name, True, C.DANGER if m.boss else C.TEXT)
        r = img.get_rect(midtop=(rect.centerx, rect.top + 12))
        bg = pygame.Surface((r.width + 20, r.height + 8), pygame.SRCALPHA)
        bg.fill((0, 0, 0, 160))
        surface.blit(bg, (r.x - 10, r.y - 4))
        surface.blit(img, r)

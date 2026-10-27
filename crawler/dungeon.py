"""Floor generation and field of view.

A floor is a grid of tiles carved into rooms joined by L-shaped corridors.
Rooms are connected in creation order, which guarantees every room is
reachable; a few extra corridors add loops. One room is the safe room and
the rooms furthest from the start hold the stairwells.
"""
from dataclasses import dataclass

from . import config as C

WALL, FLOOR, STAIRS, FURNITURE = 0, 1, 2, 3   # furniture blocks movement, not sight

NEIGHBOURS_8 = ((-1, -1), (0, -1), (1, -1), (-1, 0), (1, 0), (-1, 1), (0, 1), (1, 1))


@dataclass
class Room:
    x: int
    y: int
    w: int
    h: int

    @property
    def centre(self):
        return self.x + self.w // 2, self.y + self.h // 2

    def contains(self, x, y):
        return self.x <= x < self.x + self.w and self.y <= y < self.y + self.h

    def intersects(self, other, pad=1):
        return (self.x - pad < other.x + other.w and other.x - pad < self.x + self.w
                and self.y - pad < other.y + other.h and other.y - pad < self.y + self.h)

    def tiles(self):
        for y in range(self.y, self.y + self.h):
            for x in range(self.x, self.x + self.w):
                yield x, y


class Floor:
    def __init__(self, width, height, depth):
        self.width, self.height, self.depth = width, height, depth
        self.tiles = [[WALL] * width for _ in range(height)]   # tiles[y][x]
        self.safe = [[False] * width for _ in range(height)]
        self.explored = [[False] * width for _ in range(height)]
        self.rooms: list[Room] = []
        self.start_room: Room | None = None
        self.safe_room: Room | None = None
        self.stairs: list[tuple[int, int]] = []
        self.furniture: dict[tuple[int, int], str] = {}    # (x, y) -> "bed" | "bench" | "counter"
        self.safe_door: tuple[int, int] | None = None

    def in_bounds(self, x, y):
        return 0 <= x < self.width and 0 <= y < self.height

    def walkable(self, x, y):
        return self.in_bounds(x, y) and self.tiles[y][x] in (FLOOR, STAIRS)

    def is_safe(self, x, y):
        return self.safe[y][x]

    def _adjacency(self, avoid_safe):
        """Walkable 8-way neighbours of every open tile, as flat indices.

        Built once per floor on first use (walls and safe rooms never change
        after generation), so each BFS only follows ready-made lists.
        """
        attr = "_adj_no_safe" if avoid_safe else "_adj_all"
        adj = self.__dict__.get(attr)
        if adj is None:
            w, h, tiles, safe = self.width, self.height, self.tiles, self.safe
            ok = [[tiles[y][x] in (FLOOR, STAIRS) and not (avoid_safe and safe[y][x])
                   for x in range(w)] for y in range(h)]
            adj = [()] * (w * h)
            for y in range(h):
                for x in range(w):
                    if tiles[y][x] not in (FLOOR, STAIRS):
                        continue
                    adj[y * w + x] = tuple((y + dy) * w + x + dx for dx, dy in NEIGHBOURS_8
                                           if 0 <= x + dx < w and 0 <= y + dy < h
                                           and ok[y + dy][x + dx])
            setattr(self, attr, adj)
        return adj

    def forget_paths(self):
        """Drop the cached neighbour lists after the layout changes (generation only)."""
        self.__dict__.pop("_adj_all", None)
        self.__dict__.pop("_adj_no_safe", None)

    def distance_map(self, sx, sy, max_dist=None, avoid_safe=False):
        """BFS step counts (8-way) from (sx, sy) as a flat list; -1 = unreachable.

        One BFS per turn lets every monster path to the player by stepping
        downhill, which is far cheaper than a path search per monster.
        The start tile is always expanded, even if it is itself a safe tile.
        """
        adj = self._adjacency(avoid_safe)
        dist = [-1] * (self.width * self.height)
        start = sy * self.width + sx
        dist[start] = 0
        frontier, d = [start], 0
        while frontier and (max_dist is None or d < max_dist):
            d += 1
            nxt = []
            for i in frontier:
                for j in adj[i]:
                    if dist[j] == -1:
                        dist[j] = d
                        nxt.append(j)
            frontier = nxt
        return dist


# --- Generation -----------------------------------------------------------

def _carve_room(floor, room):
    for x, y in room.tiles():
        floor.tiles[y][x] = FLOOR


def _carve_corridor(floor, rng, a, b):
    (x1, y1), (x2, y2) = a, b
    if rng.random() < 0.5:
        corner = (x2, y1)
    else:
        corner = (x1, y2)
    for (sx, sy), (ex, ey) in (((x1, y1), corner), (corner, (x2, y2))):
        for x in range(min(sx, ex), max(sx, ex) + 1):
            for y in range(min(sy, ey), max(sy, ey) + 1):
                floor.tiles[y][x] = FLOOR


def _random_room(rng, width, height):
    w = rng.randint(C.ROOM_MIN_W, C.ROOM_MAX_W)
    h = rng.randint(C.ROOM_MIN_H, C.ROOM_MAX_H)
    return Room(rng.randint(1, width - w - 1), rng.randint(1, height - h - 1), w, h)


def generate_floor(rng, depth, width=C.MAP_W, height=C.MAP_H) -> Floor:
    while True:
        floor = _try_generate(rng, depth, width, height)
        if floor is not None:
            return floor


def _try_generate(rng, depth, width, height):
    floor = Floor(width, height, depth)
    for _ in range(C.MAX_ROOMS * 15):
        if len(floor.rooms) >= C.MAX_ROOMS:
            break
        room = _random_room(rng, width, height)
        if any(room.intersects(r) for r in floor.rooms):
            continue
        _carve_room(floor, room)
        if floor.rooms:
            _carve_corridor(floor, rng, floor.rooms[-1].centre, room.centre)
        floor.rooms.append(room)

    # Need start + safe room + a room per stairwell, plus one for monsters.
    if len(floor.rooms) < C.STAIRS_PER_FLOOR + 3:
        return None

    for _ in range(C.EXTRA_CORRIDORS):
        a, b = rng.sample(floor.rooms, 2)
        _carve_corridor(floor, rng, a.centre, b.centre)

    floor.start_room = floor.rooms[0]
    sx, sy = floor.start_room.centre
    dist = floor.distance_map(sx, sy)
    others = sorted(floor.rooms[1:], key=lambda r: dist[r.centre[1] * width + r.centre[0]])
    if not _add_safe_room(floor, rng, dist):
        return None

    # Stairwells in the furthest rooms, on an interior tile away from walls.
    for room in others[-C.STAIRS_PER_FLOOR:]:
        x = rng.randint(room.x + 1, room.x + room.w - 2)
        y = rng.randint(room.y + 1, room.y + room.h - 2)
        floor.tiles[y][x] = STAIRS
        floor.stairs.append((x, y))
    return floor


def _add_safe_room(floor, rng, dist):
    """Build the safe room in solid rock: a small room with one doorway and a short
    corridor to the nearest open tile, so it reads as a real room, not a hall.
    Several candidate spots are found and the one about mid-way from the start wins,
    so reaching it is a reward for pushing on."""
    w, h = C.SAFE_W, C.SAFE_H
    candidates = []
    for _ in range(600):
        room = Room(rng.randint(2, floor.width - w - 3), rng.randint(2, floor.height - h - 3), w, h)
        if not all(floor.tiles[y][x] == WALL for y in range(room.y - 2, room.y + h + 2)
                   for x in range(room.x - 2, room.x + w + 2)):
            continue
        cx, cy = room.centre
        sides = [((cx, room.y - 1), (0, -1)), ((cx, room.y + h), (0, 1)),
                 ((room.x - 1, cy), (-1, 0)), ((room.x + w, cy), (1, 0))]
        rng.shuffle(sides)
        for door, (dx, dy) in sides:
            path = [door]
            x, y = door
            for _ in range(14):
                x, y = x + dx, y + dy
                if not floor.in_bounds(x, y):
                    break
                if floor.tiles[y][x] != WALL:
                    d = dist[y * floor.width + x]
                    if d >= 0:
                        candidates.append((d, room, door, path, (-dx, -dy)))
                    break
                path.append((x, y))
            else:
                continue
            break
        if len(candidates) >= 24:
            break
    if not candidates:
        return False
    candidates.sort(key=lambda c: c[0])
    _, room, door, path, inward = candidates[len(candidates) // 2]
    _carve_room(floor, room)
    for x, y in path:
        floor.tiles[y][x] = FLOOR
    for x, y in list(room.tiles()) + [door]:
        floor.safe[y][x] = True
    floor.safe_room, floor.safe_door = room, door
    floor.rooms.append(room)
    # Furniture along the wall opposite the door: bed, crafting bench, shop counter.
    ix, iy = inward
    if iy:
        y = room.y + (room.h - 1 if iy > 0 else 0)
        spots = [(room.x, y), (room.x + room.w // 2, y), (room.x + room.w - 1, y)]
    else:
        x = room.x + (room.w - 1 if ix > 0 else 0)
        spots = [(x, room.y), (x, room.y + room.h // 2), (x, room.y + room.h - 1)]
    for (x, y), kind in zip(spots, ("bed", "bench", "counter")):
        floor.tiles[y][x] = FURNITURE
        floor.furniture[(x, y)] = kind
    floor.forget_paths()
    return True


# --- Field of view (recursive shadowcasting) -----------------------------

_OCTANTS = ((1, 0, 0, 1), (0, 1, 1, 0), (0, -1, 1, 0), (-1, 0, 0, 1),
            (-1, 0, 0, -1), (0, -1, -1, 0), (0, 1, -1, 0), (1, 0, 0, -1))


def compute_fov(floor, ox, oy, radius=C.FOV_RADIUS):
    visible = {(ox, oy)}
    for xx, xy, yx, yy in _OCTANTS:
        _cast(floor, ox, oy, 1, 1.0, 0.0, radius, xx, xy, yx, yy, visible)
    return visible


def _cast(floor, cx, cy, row, start, end, radius, xx, xy, yx, yy, visible):
    if start < end:
        return
    r2 = radius * radius
    new_start = start
    for j in range(row, radius + 1):
        dx, dy = -j - 1, -j
        blocked = False
        while dx <= 0:
            dx += 1
            x, y = cx + dx * xx + dy * xy, cy + dx * yx + dy * yy
            l_slope = (dx - 0.5) / (dy + 0.5)
            r_slope = (dx + 0.5) / (dy - 0.5)
            if start < r_slope:
                continue
            if end > l_slope:
                break
            inside = floor.in_bounds(x, y)
            if inside and dx * dx + dy * dy < r2:
                visible.add((x, y))
            opaque = not inside or floor.tiles[y][x] == WALL
            if blocked:
                if opaque:
                    new_start = r_slope
                    continue
                blocked = False
                start = new_start
            elif opaque and j < radius:
                blocked = True
                _cast(floor, cx, cy, j + 1, start, l_slope, radius, xx, xy, yx, yy, visible)
                new_start = r_slope
        if blocked:
            break

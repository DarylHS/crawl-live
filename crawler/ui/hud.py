"""In-game drawing: map, side panel and message log."""
import pygame

from .. import config as C
from ..attributes import ATTRS, fmt_mod, mod
from ..classes import CLASSES, RACES, SKILLS
from ..combat import expected_damage, hit_chance
from ..dice import needed_roll
from ..dungeon import FURNITURE, STAIRS, WALL
from ..encounter import PARTS
from ..entities import PETS
from ..items import ITEMS, glyph
from ..loot import BOX_TIERS

MONO = "dejavusansmono,menlo,consolas,couriernew,monospace"
FURNITURE_GLYPHS = {"bed": ("=", (150, 180, 230)), "bench": ("&", (200, 160, 100)),
                    "counter": ("$", (255, 196, 64))}
MAP_RECT = pygame.Rect(0, 0, C.VIEW_W * C.TILE, C.VIEW_H * C.TILE)   # map or 3D view
TRACKER_W = 270                     # initiative tracker box, top-left of the view
TRACKER_ROWS = 8                    # fighters listed before "+N more"
COMBAT_TOAST_TURNS = 2              # the "roll for initiative" banner is short
TIER_COLOURS = {"opening": (110, 170, 240), "featured": (255, 196, 64), "headliner": (235, 80, 80)}


class Renderer:
    def __init__(self):
        self.glyph_font = pygame.font.SysFont(MONO, C.TILE, bold=True)
        self.font = pygame.font.SysFont(MONO, 15)
        self.small = pygame.font.SysFont(MONO, 13)
        self.big = pygame.font.SysFont(MONO, 22, bold=True)
        self.huge = pygame.font.SysFont(MONO, 56, bold=True)
        self._glyphs = {}
        self._cam = (0, 0)
        self._avoid = []                    # screen rects boxes over the map keep clear of
        self.last_tracker, self.last_toasts = None, []

    def glyph(self, ch, colour):
        key = (ch, colour)
        surf = self._glyphs.get(key)
        if surf is None:
            surf = self._glyphs[key] = self.glyph_font.render(ch, True, colour)
        return surf

    def text(self, surface, text, pos, colour=C.TEXT, font=None, centre=False):
        img = (font or self.font).render(text, True, colour)
        rect = img.get_rect(center=pos) if centre else img.get_rect(topleft=pos)
        surface.blit(img, rect)
        return rect

    # --- Map -----------------------------------------------------------

    def _camera(self, world):
        """Top-left tile of the visible window: centred on the player, clamped to the floor."""
        f, p = world.floor, world.player
        cx = min(max(0, p.x - C.VIEW_W // 2), max(0, f.width - C.VIEW_W))
        cy = min(max(0, p.y - C.VIEW_H // 2), max(0, f.height - C.VIEW_H))
        return cx, cy

    def _provoke_marker(self, surface, px, py):
        """Orange corner brackets just outside the tile: stepping away provokes it. Brackets,
        not a box, so it can't be mistaken for the 1px boss-tier outline."""
        T, c, k = C.TILE, C.WARN, 5
        x0, y0, x1, y1 = px - 2, py - 2, px + T + 1, py + T + 1
        for (x, y, sx, sy) in ((x0, y0, 1, 1), (x1, y0, -1, 1), (x0, y1, 1, -1), (x1, y1, -1, -1)):
            pygame.draw.line(surface, c, (x, y), (x + sx * k, y), 2)
            pygame.draw.line(surface, c, (x, y), (x, y + sy * k), 2)

    def _blit_glyph(self, surface, ch, colour, tx, ty):
        img = self.glyph(ch, colour)
        cx, cy = self._cam
        surface.blit(img, img.get_rect(center=((tx - cx) * C.TILE + C.TILE // 2,
                                               (ty - cy) * C.TILE + C.TILE // 2)))

    def draw_map(self, surface, world):
        floor, visible = world.floor, world.visible
        T = C.TILE
        self._cam = cx, cy = self._camera(world)
        surface.set_clip((0, 0, C.VIEW_W * T, C.VIEW_H * T))
        for y in range(cy, min(floor.height, cy + C.VIEW_H)):
            row, safe_row, seen_row = floor.tiles[y], floor.safe[y], floor.explored[y]
            sy = (y - cy) * T
            for x in range(cx, min(floor.width, cx + C.VIEW_W)):
                if not seen_row[x]:
                    continue
                lit = (x, y) in visible
                tile = row[x]
                if tile == WALL:
                    colour = C.WALL_LIT if lit else C.WALL_DIM
                elif safe_row[x]:
                    colour = C.SAFE_LIT if lit else C.SAFE_DIM
                else:
                    colour = C.FLOOR_LIT if lit else C.FLOOR_DIM
                surface.fill(colour, ((x - cx) * T, sy, T - (tile != WALL), T - (tile != WALL)))
                if tile == STAIRS:
                    open_ = not world.stairs_locked
                    self._blit_glyph(surface, ">", (C.ACCENT if open_ else C.DANGER) if lit
                                     else C.TEXT_DIM, x, y)
                elif tile == FURNITURE:
                    kind = floor.furniture[(x, y)]
                    self._blit_glyph(surface, FURNITURE_GLYPHS[kind][0],
                                     FURNITURE_GLYPHS[kind][1] if lit else C.TEXT_DIM, x, y)

        for (x, y), keys in world.floor_items.items():
            if (x, y) in visible:
                self._blit_glyph(surface, glyph(keys[-1]), ITEMS[keys[-1]]["colour"], x, y)
        threats = world.threats()           # combat: stepping out of their reach provokes
        for m in world.monsters:
            if (m.x, m.y) in visible:
                px, py = (m.x - cx) * T, (m.y - cy) * T
                if m.boss:
                    pygame.draw.rect(surface, TIER_COLOURS.get(m.tier, C.DANGER), (px, py, T, T), 1)
                if m in threats:
                    self._provoke_marker(surface, px, py)
                self._blit_glyph(surface, m.glyph, m.colour, m.x, m.y)
                if m.hp < m.max_hp:
                    w = int((T - 2) * m.hp / m.max_hp)
                    surface.fill(C.DANGER, (px + 1, py + T - 2, w, 2))
        pet = world.active_pet
        if pet:
            self._blit_glyph(surface, pet.glyph, pet.colour, pet.x, pet.y)
        p = world.player
        self._blit_glyph(surface, p.glyph, p.colour, p.x, p.y)
        surface.set_clip(None)

    # --- Panel ---------------------------------------------------------

    def _bar(self, surface, x, y, w, frac, colour, label):
        surface.fill((45, 42, 58), (x, y, w, 16))
        surface.fill(colour, (x, y, int(w * max(0.0, min(1.0, frac))), 16))
        self.text(surface, label, (x + w // 2, y + 8), C.TEXT, self.small, centre=True)

    def draw_panel(self, surface, world):
        x0 = C.VIEW_W * C.TILE
        surface.fill(C.PANEL_BG, (x0, 0, C.PANEL_W, C.SCREEN_H))
        x, w = x0 + 16, C.PANEL_W - 32
        p = world.player
        y = 14
        self.text(surface, "CRAWL LIVE!", (x, y), C.ACCENT, self.big)
        y += 28
        from ..character import BACKSTORIES
        who = world.hero_name + (f", {BACKSTORIES[world.backstory]['name']}" if world.backstory else "")
        self.text(surface, who, (x, y), C.TEXT_DIM, self.small)
        y += 20
        self.text(surface, f"Floor {world.depth} of {C.NUM_FLOORS}", (x, y))
        y += 26

        frac_left = world.timer / world.timer_max
        timer_colour = C.DANGER if frac_left <= 0.1 else C.ACCENT if frac_left <= 0.25 else C.INFO
        self.text(surface, "Floor collapses in", (x, y), C.TEXT_DIM, self.small)
        y += 16
        self.text(surface, world.timer_text(), (x, y), timer_colour, self.big)
        y += 30
        self._bar(surface, x, y, w, frac_left, timer_colour, "")
        y += 20
        if world.exit_sealed:
            stairs, colour = "Exit sealed: beat the Headliner", C.DANGER
        elif world.stairs_locked:
            stairs, colour = f"Stairs unlock in {world.timer_text(world.stairs_wait)}", C.TEXT_DIM
        else:
            stairs, colour = ("Stairs open (key)" if world.has_key and world.stairs_wait
                              else "Stairs open"), C.GOOD
        self.text(surface, stairs, (x, y), colour, self.small)
        y += 22

        self._bar(surface, x, y, w, p.hp / p.max_hp, C.DANGER, f"HP {p.hp}/{p.max_hp}")
        y += 22
        self._bar(surface, x, y, w, p.xp / p.xp_to_next(), C.INFO,
                  f"Level {p.level}  XP {p.xp}/{p.xp_to_next()}")
        y += 30
        col = w // len(ATTRS)
        for i, (key, a) in enumerate(ATTRS.items()):
            cx = x + i * col + col // 2
            score = world.score(key)
            self.text(surface, a["short"], (cx, y + 6), C.TEXT_DIM, self.small, centre=True)
            self.text(surface, str(score), (cx, y + 23), C.TEXT, self.font, centre=True)
            self.text(surface, fmt_mod(mod(score)), (cx, y + 40), C.INFO, self.small, centre=True)
        y += 52
        if p.stat_points:
            self.text(surface, f"L: {p.stat_points} point{'s' if p.stat_points != 1 else ''} "
                               f"to spend", (x, y), C.ACCENT, self.small)
            y += 18
        for label, value in (("Armour Class", p.ac), ("To hit", fmt_mod(p.attack)),
                             ("Damage", p.damage_text()),
                             ("Kills", p.kills), ("Gold", world.gold),
                             ("Viewers", f"{world.viewers:,}")):
            self.text(surface, label, (x, y), C.TEXT_DIM)
            self.text(surface, str(value), (x + w - self.font.size(str(value))[0], y))
            y += 20

        y += 4
        if world.cls:
            skill = SKILLS[world.skill]
            ready = (f"{world.skill_cooldown} turns" if world.skill_cooldown else "ready")
            self.text(surface, f"{RACES[world.race]['name']} {CLASSES[world.cls]['name']}",
                      (x, y), C.ACCENT, self.small)
            self.text(surface, f"1: {skill['name']} ({ready})", (x, y + 16),
                      C.TEXT if not world.skill_cooldown else C.TEXT_DIM, self.small)
            y += 36
        if world.contract:
            from ..contracts import CONTRACTS
            self.text(surface, f"Deal: {CONTRACTS[world.contract]['name']}", (x, y), C.ACCENT,
                      self.small)
            y += 18
        pet = world.pet
        if pet:
            status = "DOWN: revive in a safe room" if pet.downed else \
                f"HP {pet.hp}/{pet.max_hp}   mode: {pet.mode}"
            self.text(surface, f"{pet.name}, L{pet.level} {PETS[pet.species]['name']}", (x, y),
                      pet.colour, self.small)
            self.text(surface, status, (x, y + 16), C.DANGER if pet.downed else C.TEXT_DIM,
                      self.small)
            y += 36

        if world.boxes:
            x2 = x
            for tier in BOX_TIERS:
                n = world.boxes.count(tier)
                if n:
                    label = f"{n}x{BOX_TIERS[tier]['name'][0]}"
                    x2 = self.text(surface, label, (x2, y), BOX_TIERS[tier]["colour"],
                                   self.small).right + 8
            y += 18
        y += 6
        if world.in_safe_room:
            self.text(surface, "SAFE ROOM", (x, y), C.GOOD, self.big)
            y += 26
            self.text(surface, "R: rest   M: menu", (x, y), C.TEXT_DIM, self.small)
            y += 16
        elif world.on_stairs:
            self.text(surface, "STAIRWELL", (x, y), C.ACCENT, self.big)
            y += 26
            self.text(surface, "> or Enter: descend", (x, y), C.TEXT_DIM, self.small)
            y += 16
        if world.scout_turns:
            self.draw_scout_report(surface, world, x, y + 14, w)

        self.text(surface, "? for all the controls", (x, C.SCREEN_H - 26), C.TEXT_DIM, self.small)

    def actor_rects(self, world):
        """Screen rects of you, your pet and the monsters in sight on the map (after draw_map),
        so boxes drawn over the map can keep clear of them."""
        cx, cy = self._cam
        T = C.TILE
        ents = [world.player] + ([world.active_pet] if world.active_pet else []) + \
            [m for m in world.monsters if (m.x, m.y) in world.visible]
        return [pygame.Rect((e.x - cx) * T, (e.y - cy) * T, T, T) for e in ents]

    @staticmethod
    def _clear_spot(candidates, avoid):
        """The first rect that covers none of avoid (avoid[0], you, matters most), else the one
        that covers you not at all and the fewest others."""
        def cost(r):
            hits = r.collidelistall(avoid)
            return (0 in hits, len(hits))
        return min(candidates, key=cost)

    def draw_tracker(self, surface, world, rect, avoid=None):
        """Initiative tracker over the map or 3D view: top-left (clear of the minimap, the
        "ahead" label, the toasts and the side chevrons), or bottom-left on the map when the
        top-left would hide you or a fighter. Fighters in order with HP, boss rows in their
        tier colour, you highlighted with your Move / Action / Bonus pips. Monsters act between
        your turns, so whenever you can press a key it is your turn. Returns the box drawn."""
        enc, p = world.combat, world.player
        rows = enc.entities
        shown = rows[:TRACKER_ROWS]
        h = 30 + 18 * len(shown) + 22 + (16 if len(rows) > len(shown) else 0) + 20
        avoid = self._avoid if avoid is None else avoid
        box = self._clear_spot([pygame.Rect(rect.left + 10, rect.top + 10, TRACKER_W, h),
                                pygame.Rect(rect.left + 10, rect.bottom - 10 - h, TRACKER_W, h)],
                               avoid)
        self.last_tracker = box
        bg = pygame.Surface(box.size, pygame.SRCALPHA)
        bg.fill((*C.PANEL_BG, 225))
        surface.blit(bg, box.topleft)
        pygame.draw.rect(surface, C.DANGER, box, 1)
        x, y = box.left + 10, box.top + 6
        self.text(surface, "COMBAT", (x, y), C.DANGER, self.font)
        rnd = f"round {max(1, enc.round)}"
        self.text(surface, rnd, (box.right - 10 - self.small.size(rnd)[0], y + 2), C.TEXT_DIM,
                  self.small)
        y += 24
        for ent in shown:
            you = ent is p
            if you:
                surface.fill((60, 52, 30), (box.left + 2, y - 1, box.width - 4, 38))
            name = "You" if you else ent.name
            tier = getattr(ent, "tier", "")
            colour = C.ACCENT if you else TIER_COLOURS.get(tier, ent.colour)
            hp = f"{ent.hp}/{ent.max_hp}"
            room = box.right - 18 - self.small.size(hp)[0] - (x - 6)
            label = self.fit_name((">" if you else " ") + f"{enc.total(ent):>3} ", name, room)
            self.text(surface, label, (x - 6, y), colour, self.small)
            self.text(surface, hp, (box.right - 10 - self.small.size(hp)[0], y),
                      C.TEXT if you else C.TEXT_DIM, self.small)
            y += 18
            if you:
                y = self._pips(surface, enc, x + 26, y) + 2
        if len(rows) > len(shown):
            self.text(surface, f"  +{len(rows) - len(shown)} more", (x, y), C.TEXT_DIM, self.small)
            y += 16
        if p not in shown:
            y = self._pips(surface, enc, x, y)
        self.text(surface, "Space ends your turn", (x, box.bottom - 18), C.TEXT_DIM, self.small)
        return box

    def fit_name(self, prefix, name, room):
        """prefix + name within room pixels: drop a leading "The ", then cut at a word with an
        ellipsis ("Grease Trap..."), never mid-word unless one word is too long."""
        font = self.small
        if font.size(prefix + name)[0] <= room:
            return prefix + name
        name = name.removeprefix("The ")
        words = name.split()
        while words:
            text = prefix + " ".join(words) + ("..." if len(words) < len(name.split()) else "")
            if font.size(text)[0] <= room:
                return text
            words.pop()
        text = prefix + name
        while font.size(text + "...")[0] > room and len(text) > len(prefix) + 1:
            text = text[:-1]
        return text + "..."

    def _pips(self, surface, enc, x, y):
        """Move / Action / Bonus boxes: filled while available, hollow once spent."""
        for part in PARTS:
            label = part.capitalize()
            w = self.small.size(label)[0] + 10
            r = pygame.Rect(x, y, w, 16)
            if enc.has(part):
                surface.fill(C.GOOD, r)
                self.text(surface, label, r.center, C.PANEL_BG, self.small, centre=True)
            else:
                pygame.draw.rect(surface, C.TEXT_DIM, r, 1)
                self.text(surface, label, r.center, C.TEXT_DIM, self.small, centre=True)
            x = r.right + 6
        return y + 18

    def draw_scout_report(self, surface, world, x, y, w):
        """Analyst skill: exact odds both ways for each visible monster."""
        p = world.player
        self.text(surface, f"SCOUT REPORT ({world.scout_turns})", (x, y), C.INFO, self.small)
        y += 18
        seen = sorted((m for m in world.monsters if (m.x, m.y) in world.visible),
                      key=lambda m: max(abs(m.x - p.x), abs(m.y - p.y)))
        if not seen:
            self.text(surface, "Nothing in sight.", (x, y), C.TEXT_DIM, self.small)
        for m in seen[:3]:
            self.text(surface, f"{m.glyph} {m.name}  {m.hp}/{m.max_hp}", (x, y), m.colour,
                      self.small)
            for i, (who, a, b) in enumerate((("you", p, m), ("it", m, p))):
                self.text(surface, f"{who:>3} need {needed_roll(a.attack, b.ac):>2}+ "
                                   f"{hit_chance(a, b):>4.0%}  ~{expected_damage(a, b):.1f} dmg",
                          (x, y + 15 + 14 * i), C.TEXT_DIM, self.small)
            y += 48

    # --- Log -----------------------------------------------------------

    def draw_log(self, surface, world):
        y0 = C.VIEW_H * C.TILE
        surface.fill(C.PANEL_BG, (0, y0, C.VIEW_W * C.TILE, C.LOG_H))
        surface.fill(C.WALL_DIM, (0, y0, C.VIEW_W * C.TILE, 1))
        # Wrap long messages so they never spill under the side panel.
        max_w = C.VIEW_W * C.TILE - 24
        lines = []
        for text, colour in world.messages.recent(C.LOG_LINES):
            words, line = text.split(), ""
            for word in words:
                trial = f"{line} {word}".strip()
                if self.font.size(trial)[0] > max_w and line:
                    lines.append((line, colour))
                    line = "  " + word
                else:
                    line = trial
            lines.append((line, colour))
        lines = lines[-C.LOG_LINES:]
        for i, (text, colour) in enumerate(lines):
            # Older lines fade toward the background.
            age = len(lines) - 1 - i
            fade = 1.0 - 0.1 * age
            col = tuple(int(c * fade + b * (1 - fade)) for c, b in zip(colour, C.PANEL_BG))
            self.text(surface, text, (12, y0 + 8 + i * 17), col)

    def toast_layout(self, world, avoid=()):
        """Up to three recent toasts and their rects, stacked at the top of the view, or at the
        bottom on the map when the top would hide you or a fighter."""
        live = [t for t in world.toasts
                if world.turn - t[0] < (COMBAT_TOAST_TURNS if t[2] == "combat" else C.TOAST_TURNS)][-3:]
        sizes = [46 if len(t) > 3 and t[3] else 30 for t in live]
        total = sum(sizes) + 6 * max(0, len(sizes) - 1)
        x = (C.VIEW_W * C.TILE - 420) // 2
        top = pygame.Rect(x, 10, 420, total)
        bottom = pygame.Rect(x, MAP_RECT.bottom - 10 - total, 420, total)
        y = self._clear_spot([top, bottom], avoid).top if live else 10
        out = []
        for toast, h in zip(live, sizes):
            out.append((toast, pygame.Rect(x, y, 420, h)))
            y += h + 6
        return out

    def draw_toasts(self, surface, world, avoid=None):
        """Draw the toasts (see toast_layout). Returns their rects."""
        avoid = self._avoid if avoid is None else avoid
        rects = []
        for toast, rect in self.toast_layout(world, avoid):
            text, tier = toast[1], toast[2]
            sub = toast[3] if len(toast) > 3 else None
            rects.append(rect)
            surface.fill(C.PANEL_BG, rect)
            colour = C.DANGER if tier == "combat" else BOX_TIERS[tier]["colour"]
            pygame.draw.rect(surface, colour, rect, 2)
            self.text(surface, text, (rect.centerx, rect.top + 15), C.TEXT, self.font, centre=True)
            if sub:
                self.text(surface, sub, (rect.centerx, rect.top + 33), colour,
                          self.small, centre=True)
        self.last_toasts = rects
        return rects

    def draw_game(self, surface, world, view=None, dt=1.0, hud=True):
        """The game screen. view is a FirstPersonView to look through, or None for the map.
        hud=False when a menu or end screen will cover it (the 3D view drops its overlays)."""
        surface.fill(C.BG)
        if view is None:
            self.draw_map(surface, world)
            self._avoid = self.actor_rects(world)
        else:
            toasts = self.toast_layout(world)   # the "ahead" label goes below any toasts
            view.ahead_top = max(r.bottom for _, r in toasts) + 8 if toasts else None
            view.draw(surface, world, MAP_RECT, dt, hud)
            self._avoid = []                    # the 3D view has nobody on screen to cover
        self.draw_panel(surface, world)
        self.draw_log(surface, world)
        if hud:                             # menus and help hide these (inventory redraws the tracker)
            if world.combat is not None:
                self.draw_tracker(surface, world, MAP_RECT)
            self.draw_toasts(surface, world)
        else:
            self.last_toasts = []

"""In-game drawing: map, side panel and message log."""
import pygame

from .. import config as C
from ..dungeon import STAIRS, WALL

MONO = "dejavusansmono,menlo,consolas,couriernew,monospace"


class Renderer:
    def __init__(self):
        self.glyph_font = pygame.font.SysFont(MONO, C.TILE, bold=True)
        self.font = pygame.font.SysFont(MONO, 15)
        self.small = pygame.font.SysFont(MONO, 13)
        self.big = pygame.font.SysFont(MONO, 22, bold=True)
        self.huge = pygame.font.SysFont(MONO, 56, bold=True)
        self._glyphs = {}

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

    def _blit_glyph(self, surface, ch, colour, tx, ty):
        img = self.glyph(ch, colour)
        surface.blit(img, img.get_rect(center=(tx * C.TILE + C.TILE // 2,
                                               ty * C.TILE + C.TILE // 2)))

    def draw_map(self, surface, world):
        floor, visible = world.floor, world.visible
        T = C.TILE
        for y in range(floor.height):
            row, safe_row, seen_row = floor.tiles[y], floor.safe[y], floor.explored[y]
            for x in range(floor.width):
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
                surface.fill(colour, (x * T, y * T, T - (tile != WALL), T - (tile != WALL)))
                if tile == STAIRS:
                    self._blit_glyph(surface, ">", C.ACCENT if lit else C.TEXT_DIM, x, y)

        for m in world.monsters:
            if (m.x, m.y) in visible:
                self._blit_glyph(surface, m.glyph, m.colour, m.x, m.y)
                if m.hp < m.max_hp:
                    w = int((T - 2) * m.hp / m.max_hp)
                    surface.fill(C.DANGER, (m.x * T + 1, m.y * T + T - 2, w, 2))
        p = world.player
        self._blit_glyph(surface, p.glyph, p.colour, p.x, p.y)

    # --- Panel ---------------------------------------------------------

    def _bar(self, surface, x, y, w, frac, colour, label):
        surface.fill((45, 42, 58), (x, y, w, 16))
        surface.fill(colour, (x, y, int(w * max(0.0, min(1.0, frac))), 16))
        self.text(surface, label, (x + w // 2, y + 8), C.TEXT, self.small, centre=True)

    def draw_panel(self, surface, world):
        x0 = C.MAP_W * C.TILE
        surface.fill(C.PANEL_BG, (x0, 0, C.PANEL_W, C.SCREEN_H))
        x, w = x0 + 16, C.PANEL_W - 32
        p = world.player
        y = 14
        self.text(surface, "CRAWL LIVE!", (x, y), C.ACCENT, self.big)
        y += 34
        self.text(surface, f"Floor {world.depth} of {C.NUM_FLOORS}", (x, y))
        y += 26

        frac_left = world.timer / world.timer_max
        timer_colour = C.DANGER if frac_left <= 0.1 else C.ACCENT if frac_left <= 0.25 else C.INFO
        self.text(surface, "Floor collapses in", (x, y), C.TEXT_DIM, self.small)
        y += 16
        self.text(surface, world.timer_text(), (x, y), timer_colour, self.big)
        y += 30
        self._bar(surface, x, y, w, frac_left, timer_colour, "")
        y += 30

        self._bar(surface, x, y, w, p.hp / p.max_hp, C.DANGER, f"HP {p.hp}/{p.max_hp}")
        y += 22
        self._bar(surface, x, y, w, p.xp / p.xp_to_next(), C.INFO,
                  f"Level {p.level}  XP {p.xp}/{p.xp_to_next()}")
        y += 30
        for label, value in (("Attack", p.power), ("Defence", p.defence),
                             ("Accuracy", p.accuracy), ("Evasion", p.evasion),
                             ("Kills", p.kills), ("Turn", world.turn)):
            self.text(surface, label, (x, y), C.TEXT_DIM)
            self.text(surface, str(value), (x + w - self.font.size(str(value))[0], y))
            y += 20

        y += 10
        if world.in_safe_room:
            self.text(surface, "SAFE ROOM", (x, y), C.GOOD, self.big)
            y += 26
            self.text(surface, "R: rest to full HP", (x, y), C.TEXT_DIM, self.small)
        elif world.on_stairs:
            self.text(surface, "STAIRWELL", (x, y), C.ACCENT, self.big)
            y += 26
            self.text(surface, "> or Enter: descend", (x, y), C.TEXT_DIM, self.small)

        self.text(surface, "? help   Esc quit", (x, C.SCREEN_H - 26), C.TEXT_DIM, self.small)

    # --- Log -----------------------------------------------------------

    def draw_log(self, surface, world):
        y0 = C.MAP_H * C.TILE
        surface.fill(C.PANEL_BG, (0, y0, C.MAP_W * C.TILE, C.LOG_H))
        surface.fill(C.WALL_DIM, (0, y0, C.MAP_W * C.TILE, 1))
        lines = world.messages.recent(C.LOG_LINES)
        for i, (text, colour) in enumerate(lines):
            # Older lines fade toward the background.
            age = len(lines) - 1 - i
            fade = 1.0 - 0.1 * age
            col = tuple(int(c * fade + b * (1 - fade)) for c, b in zip(colour, C.PANEL_BG))
            self.text(surface, text, (12, y0 + 8 + i * 17), col)

    def draw_game(self, surface, world):
        surface.fill(C.BG)
        self.draw_map(surface, world)
        self.draw_panel(surface, world)
        self.draw_log(surface, world)

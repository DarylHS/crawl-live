"""In-game drawing: map, side panel and message log."""
import pygame

from .. import config as C
from ..classes import CLASSES, RACES, SKILLS
from ..combat import expected_damage, hit_chance
from ..dungeon import STAIRS, WALL
from ..entities import PETS
from ..items import ITEMS, glyph
from ..loot import BOX_TIERS

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

        for (x, y), keys in world.floor_items.items():
            if (x, y) in visible:
                self._blit_glyph(surface, glyph(keys[-1]), ITEMS[keys[-1]]["colour"], x, y)
        for m in world.monsters:
            if (m.x, m.y) in visible:
                if m.boss:
                    pygame.draw.rect(surface, C.DANGER, (m.x * T, m.y * T, T, T), 1)
                self._blit_glyph(surface, m.glyph, m.colour, m.x, m.y)
                if m.hp < m.max_hp:
                    w = int((T - 2) * m.hp / m.max_hp)
                    surface.fill(C.DANGER, (m.x * T + 1, m.y * T + T - 2, w, 2))
        pet = world.active_pet
        if pet:
            self._blit_glyph(surface, pet.glyph, pet.colour, pet.x, pet.y)
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
        y += 30

        self._bar(surface, x, y, w, p.hp / p.max_hp, C.DANGER, f"HP {p.hp}/{p.max_hp}")
        y += 22
        self._bar(surface, x, y, w, p.xp / p.xp_to_next(), C.INFO,
                  f"Level {p.level}  XP {p.xp}/{p.xp_to_next()}")
        y += 30
        for label, value in (("Attack", p.power), ("Defence", p.defence),
                             ("Accuracy", p.accuracy), ("Evasion", p.evasion),
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

        self.text(surface, "I pack G get ? help", (x, C.SCREEN_H - 26), C.TEXT_DIM, self.small)

    def draw_scout_report(self, surface, world, x, y, w):
        """Analyst skill: exact odds both ways for each visible monster."""
        p = world.player
        self.text(surface, f"SCOUT REPORT ({world.scout_turns})", (x, y), C.INFO, self.small)
        y += 18
        seen = sorted((m for m in world.monsters if (m.x, m.y) in world.visible),
                      key=lambda m: max(abs(m.x - p.x), abs(m.y - p.y)))
        if not seen:
            self.text(surface, "Nothing in sight.", (x, y), C.TEXT_DIM, self.small)
        for m in seen[:4]:
            self.text(surface, f"{m.glyph} {m.name}  {m.hp}/{m.max_hp}", (x, y), m.colour,
                      self.small)
            self.text(surface, f"you {hit_chance(p, m):.0%} ~{expected_damage(p, m):.1f}  "
                               f"it {hit_chance(m, p):.0%} ~{expected_damage(m, p):.1f}",
                      (x, y + 15), C.TEXT_DIM, self.small)
            y += 34

    # --- Log -----------------------------------------------------------

    def draw_log(self, surface, world):
        y0 = C.MAP_H * C.TILE
        surface.fill(C.PANEL_BG, (0, y0, C.MAP_W * C.TILE, C.LOG_H))
        surface.fill(C.WALL_DIM, (0, y0, C.MAP_W * C.TILE, 1))
        # Wrap long messages so they never spill under the side panel.
        max_w = C.MAP_W * C.TILE - 24
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

    def draw_toasts(self, surface, world):
        live = [t for t in world.toasts if world.turn - t[0] < C.TOAST_TURNS][-3:]
        for i, (_, text, tier) in enumerate(live):
            w, h = 360, 30
            rect = pygame.Rect((C.MAP_W * C.TILE - w) // 2, 10 + i * (h + 6), w, h)
            surface.fill(C.PANEL_BG, rect)
            pygame.draw.rect(surface, BOX_TIERS[tier]["colour"], rect, 2)
            self.text(surface, text, rect.center, C.TEXT, self.font, centre=True)

    def draw_game(self, surface, world):
        surface.fill(C.BG)
        self.draw_map(surface, world)
        self.draw_panel(surface, world)
        self.draw_log(surface, world)
        self.draw_toasts(surface, world)

"""Full-screen and overlay screens: title, help, death and victory."""
import pygame

from .. import config as C

CONTROLS = [
    ("Arrows / WASD / numpad", "move, bump into monsters to attack"),
    ("Numpad 7 9 1 3", "move diagonally"),
    (". / Space / numpad 5", "wait a turn"),
    ("> / Enter", "descend a stairwell"),
    ("R", "rest to full HP (safe rooms only)"),
    ("?", "toggle this help"),
    ("Esc", "quit to title"),
]

PREMISE = [
    "Earth has been 'repurposed'. You are now a contestant.",
    "Each floor collapses when its timer hits zero. Anyone still on it dies.",
    "Find a stairwell before then. Safe rooms let you rest, at the cost of time.",
    "Billions of viewers are watching. Try to be entertaining.",
]


def _overlay(surface, alpha=200):
    shade = pygame.Surface(surface.get_size(), pygame.SRCALPHA)
    shade.fill((*C.BG, alpha))
    surface.blit(shade, (0, 0))


def draw_title(r, surface):
    surface.fill(C.BG)
    cx = C.SCREEN_W // 2
    r.text(surface, "CRAWL LIVE!", (cx, 200), C.ACCENT, r.huge, centre=True)
    r.text(surface, "The galaxy's favourite dungeon survival broadcast", (cx, 252),
           C.TEXT_DIM, r.font, centre=True)
    for i, line in enumerate(PREMISE):
        r.text(surface, line, (cx, 330 + i * 26), C.TEXT, r.font, centre=True)
    r.text(surface, "Press Enter to start", (cx, 500), C.GOOD, r.big, centre=True)
    r.text(surface, "? for controls   Esc to quit", (cx, 534), C.TEXT_DIM, r.font, centre=True)


def draw_help(r, surface):
    _overlay(surface)
    cx = C.SCREEN_W // 2
    r.text(surface, "CONTROLS", (cx, 180), C.ACCENT, r.big, centre=True)
    for i, (keys, what) in enumerate(CONTROLS):
        y = 230 + i * 28
        r.text(surface, keys, (cx - 20 - r.font.size(keys)[0], y), C.ACCENT)
        r.text(surface, what, (cx + 20, y))
    r.text(surface, "Press ? to close", (cx, 230 + len(CONTROLS) * 28 + 30), C.TEXT_DIM,
           r.font, centre=True)


def _summary(r, surface, world, y):
    cx = C.SCREEN_W // 2
    p = world.player
    for i, line in enumerate((f"Reached floor {world.depth} of {C.NUM_FLOORS}",
                              f"Level {p.level}   Kills {p.kills}   Turns {world.turn}",
                              f"Seed {world.seed}")):
        r.text(surface, line, (cx, y + i * 26), C.TEXT, r.font, centre=True)
    r.text(surface, "Enter: new run   Esc: title", (cx, y + 110), C.TEXT_DIM, r.font,
           centre=True)


def draw_death(r, surface, world):
    _overlay(surface)
    cx = C.SCREEN_W // 2
    r.text(surface, "YOU DIED", (cx, 230), C.DANGER, r.huge, centre=True)
    r.text(surface, world.death_cause or "", (cx, 290), C.TEXT, r.big, centre=True)
    _summary(r, surface, world, 350)


def draw_victory(r, surface, world):
    _overlay(surface)
    cx = C.SCREEN_W // 2
    r.text(surface, "YOU SURVIVED", (cx, 230), C.GOOD, r.huge, centre=True)
    r.text(surface, "The ratings were... acceptable.", (cx, 290), C.TEXT, r.big, centre=True)
    _summary(r, surface, world, 350)

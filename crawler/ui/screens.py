"""Full-screen and overlay screens: title, help, death and victory."""
import pygame

from .. import config as C

# Help is split by view: movement differs, everything else is shared.
TOP_CONTROLS = [
    ("Arrows / WASD / numpad", "move, bump into monsters to attack"),
    ("Numpad 7 9 1 3", "move diagonally"),
]
FP_CONTROLS = [
    ("W / Up", "walk where you look (hold); bumps what's ahead"),
    ("S / Down", "walk back (hold)"),
    ("A / D", "step left / right (strafe; hold)"),
    ("Q / E, Left / Right", "turn: tap 45 degrees, hold to look (free)"),
    ("Numpad", "move by the compass, 7 9 1 3 diagonally"),
    ("In combat", "W / S / A / D step one tile, Q / E turn 90 degrees"),
    ("W in combat", "attacks ahead, else front-left / front-right"),
]
SHARED_CONTROLS = [
    (". / Space / numpad 5", "wait a turn; in combat, end your turn"),
    ("> / Enter", "descend a stairwell"),
    ("G", "pick up items on your tile"),
    ("I", "inventory: use, equip, drop"),
    ("R", "rest to full HP (safe rooms only)"),
    ("M", "safe-room menu: boxes, shop, craft, revive, save"),
    ("C", "command your pet: follow / attack / stay"),
    ("K / L", "practice skills / attributes to spend points on"),
    ("1", "use your class skill (from floor 3)"),
    ("Tab", "switch view: first-person / map"),
    ("?", "toggle this help"),
    ("Esc", "close a menu, or quit to title"),
]
# Combat mode, the same in both views.
COMBAT_CONTROLS = [
    ("Combat turn", "one move, one action and one bonus action"),
    ("Move / action", "a step / attack, bomb, skill, pick up, descend"),
    ("Bonus action", "drink a potion (equip, drop, C and menus are free)"),
    ("Leaving reach", "gives it a free swing (not swapping with your pet)"),
]
VIEW_NAMES = {"fp": "first-person view", "top": "map view"}
HELP_CX = C.VIEW_W * C.TILE // 2    # help is centred on the map / 3D view, clear of the side panel
HELP_STEP = 22


def controls(view):
    """The help list for a view: "fp" (first-person) or "top" (map)."""
    return (FP_CONTROLS if view == "fp" else TOP_CONTROLS) + SHARED_CONTROLS + COMBAT_CONTROLS


PREMISE = [
    "Earth has been 'repurposed'. You are now a contestant.",
    "Each floor collapses when its timer hits zero. Anyone still on it dies.",
    "Find a stairwell before then. Safe rooms let you rest, at the cost of time.",
    "Billions of viewers are watching. Try to be entertaining.",
]


def overlay(surface, alpha=200):
    shade = pygame.Surface(surface.get_size(), pygame.SRCALPHA)
    shade.fill((*C.BG, alpha))
    surface.blit(shade, (0, 0))


def draw_title(r, surface, can_load=False):
    surface.fill(C.BG)
    cx = C.SCREEN_W // 2
    r.text(surface, "CRAWL LIVE!", (cx, 200), C.ACCENT, r.huge, centre=True)
    r.text(surface, "The galaxy's favourite dungeon survival broadcast", (cx, 252),
           C.TEXT_DIM, r.font, centre=True)
    for i, line in enumerate(PREMISE):
        r.text(surface, line, (cx, 330 + i * 26), C.TEXT, r.font, centre=True)
    r.text(surface, "Press Enter to start", (cx, 500), C.GOOD, r.big, centre=True)
    r.text(surface, "? for controls   Esc to quit", (cx, 534), C.TEXT_DIM, r.font, centre=True)
    if can_load:
        r.text(surface, "L to continue your saved run", (cx, 562), C.INFO, r.font, centre=True)


def draw_help(r, surface, view="top"):
    overlay(surface, 225)
    cx, rows, step = HELP_CX, controls(view), HELP_STEP
    y0 = help_top(rows)
    r.text(surface, "CONTROLS", (cx, y0 - 70), C.ACCENT, r.big, centre=True)
    r.text(surface, f"In the {VIEW_NAMES.get(view, 'map view')}. Tab switches.", (cx, y0 - 40),
           C.TEXT_DIM, r.font, centre=True)
    for i, (keys, what) in enumerate(rows):
        y = y0 + i * step
        combat = (keys, what) in COMBAT_CONTROLS or keys.endswith("n combat")
        r.text(surface, keys, (cx - 20 - r.font.size(keys)[0], y), C.DANGER if combat else C.ACCENT)
        r.text(surface, what, (cx + 20, y))
    r.text(surface, "Press ? to close", (cx, y0 + len(rows) * step + 14), C.TEXT_DIM,
           r.font, centre=True)
    return rows


def help_top(rows):
    """y of the first help row: the block (title to close line) centred on the map area."""
    return (C.VIEW_H * C.TILE - len(rows) * HELP_STEP) // 2 + 20


def _summary(r, surface, world, y):
    cx = C.SCREEN_W // 2
    p = world.player
    for i, line in enumerate((f"Reached floor {world.depth} of {C.NUM_FLOORS}",
                              f"Level {p.level}   Kills {p.kills}   Turns {world.turn}   Gold {world.gold}",
                              f"Final viewers: {world.viewers:,}   (peak {world.showrunner.peak:,})",
                              f"Seed {world.seed}")):
        r.text(surface, line, (cx, y + i * 26), C.TEXT, r.font, centre=True)
    r.text(surface, "Enter: new run   R: run report   Esc: title", (cx, y + 136), C.TEXT_DIM, r.font,
           centre=True)


def draw_death(r, surface, world):
    overlay(surface)
    cx = C.SCREEN_W // 2
    r.text(surface, "YOU DIED", (cx, 230), C.DANGER, r.huge, centre=True)
    r.text(surface, world.death_cause or "", (cx, 290), C.TEXT, r.big, centre=True)
    _summary(r, surface, world, 350)


def draw_victory(r, surface, world):
    overlay(surface)
    cx = C.SCREEN_W // 2
    r.text(surface, "YOU SURVIVED", (cx, 230), C.GOOD, r.huge, centre=True)
    r.text(surface, "The ratings were... acceptable.", (cx, 290), C.TEXT, r.big, centre=True)
    _summary(r, surface, world, 350)

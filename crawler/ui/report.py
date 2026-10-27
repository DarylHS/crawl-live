"""Post-run report: three small charts about the run that just ended."""
import pygame

from .. import config as C
from ..contracts import CONTRACTS
from ..report import run_report
from .screens import overlay

GRID = (48, 45, 62)
EXPECTED = (150, 146, 170)


def _panel(r, surface, rect, title, subtitle):
    x, y, w, h = rect
    pygame.draw.rect(surface, C.PANEL_BG, rect)
    pygame.draw.rect(surface, C.WALL_DIM, rect, 1)
    r.text(surface, title, (x + 14, y + 10), C.ACCENT, r.font)
    r.text(surface, subtitle, (x + 14, y + 30), C.TEXT_DIM, r.small)
    return pygame.Rect(x + 50, y + 60, w - 70, h - 95)       # plot area


def nice_max(v):
    """Round an axis maximum up to 2, 5 or 10 times a power of ten (at least 2)."""
    v, step = max(v, 2), 1
    while True:
        for m in (2, 5, 10):
            if m * step >= v:
                return m * step
        step *= 10


def _axes(r, surface, plot, ymax, ylabel_fmt="{:.0f}"):
    for frac in (0, 0.5, 1):
        yy = plot.bottom - round(plot.height * frac)
        pygame.draw.line(surface, GRID, (plot.left, yy), (plot.right, yy))
        label = ylabel_fmt.format(ymax * frac)
        r.text(surface, label, (plot.left - 6 - r.small.size(label)[0], yy - 7), C.TEXT_DIM, r.small)


def _bars(r, surface, plot, pairs, colour):
    ymax = nice_max(max([v for _, v in pairs] + [0]))
    _axes(r, surface, plot, ymax)
    n = max(1, len(pairs))
    slot = plot.width / n
    for i, (label, v) in enumerate(pairs):
        h = round(plot.height * v / ymax)
        bx = plot.left + round(i * slot + slot * 0.2)
        surface.fill(colour, (bx, plot.bottom - h, max(2, round(slot * 0.6)), h))
        r.text(surface, str(label), (bx + round(slot * 0.3), plot.bottom + 12), C.TEXT_DIM, r.small,
               centre=True)


def _line(surface, plot, xs, ys, xmax, ymax, colour, width=2):
    if len(xs) < 2:
        return
    pts = [(plot.left + round(plot.width * x / max(1, xmax)),
            plot.bottom - round(plot.height * y / max(1, ymax))) for x, y in zip(xs, ys)]
    pygame.draw.lines(surface, colour, False, pts, width)


def plural(n, word):
    """'1 turn', '2 turns', '1,234 viewers'."""
    return f"{n:,} {word}{'' if n == 1 else 's'}"


def draw_report(r, surface, world):
    data = run_report(world)
    overlay(surface, 255)                   # fully opaque: the end screen mustn't show through
    cx = C.SCREEN_W // 2
    r.text(surface, "RUN REPORT", (cx, 34), C.ACCENT, r.big, centre=True)
    t = data["totals"]
    r.text(surface, f"{plural(t['turns'], 'turn')}   {plural(t['kills'], 'kill')}   "
                    f"{t['gold']} gold earned   {t['damage']} damage taken   "
                    f"peak {plural(t['peak_viewers'], 'viewer')}",
           (cx, 64), C.TEXT, r.small, centre=True)

    # 1. Damage taken by floor.
    plot = _panel(r, surface, (40, 90, 380, 300), "Damage taken by floor",
                  "Where the run hurt most")
    _bars(r, surface, plot, data["damage_by_floor"], C.DANGER)

    # 2. Loot boxes: expected vs realised value, cumulative.
    plot = _panel(r, surface, (450, 90, 380, 300), "Loot boxes: luck vs average",
                  "Running total of gold value")
    plot.height -= 20                       # room for the two-line caption inside the panel
    exp, got = data["box_expected"], data["box_realised"]
    if exp:
        ymax = nice_max(max(exp + got))
        _axes(r, surface, plot, ymax)
        xs = list(range(len(exp) + 1))
        _line(surface, plot, xs, [0] + exp, len(exp), ymax, EXPECTED)
        _line(surface, plot, xs, [0] + got, len(exp), ymax, C.ACCENT, 3)
        diff = got[-1] - exp[-1]
        verdict = "luckier" if diff > 0 else "unluckier" if diff < 0 else "exactly as lucky"
        r.text(surface, f"{len(exp)} boxes: {got[-1]} gold vs {exp[-1]:.0f} expected,",
               (plot.left - 36, plot.bottom + 6), C.TEXT, r.small)
        r.text(surface, f"so you were {verdict} than average.", (plot.left - 36, plot.bottom + 21),
               C.TEXT, r.small)
        r.text(surface, "average", (plot.right - 60, plot.top - 4), EXPECTED, r.small)
        r.text(surface, "yours", (plot.right - 60, plot.top + 12), C.ACCENT, r.small)
    else:
        r.text(surface, "No boxes opened this run.", plot.center, C.TEXT_DIM, r.small, centre=True)

    # 3. Viewer curve.
    plot = _panel(r, surface, (860, 90, 380, 300), "Viewers over time",
                  "Your score, turn by turn")
    v = data["viewers"]
    ymax = nice_max(max(n for _, n in v))
    _axes(r, surface, plot, ymax, "{:,.0f}")
    _line(surface, plot, [x for x, _ in v], [n for _, n in v], v[-1][0], ymax, C.INFO, 3)
    for turn, _ in world.showrunner.history[1:]:           # floor boundaries
        xx = plot.left + round(plot.width * turn / max(1, v[-1][0]))
        pygame.draw.line(surface, GRID, (xx, plot.top), (xx, plot.bottom))
    r.text(surface, "turns", (plot.right - 30, plot.bottom + 12), C.TEXT_DIM, r.small)

    # Contracts and notes.
    y = 420
    r.text(surface, "Sponsor deals", (40, y), C.ACCENT, r.font)
    y += 26
    gold = dict(data["gold_by_floor"])
    dmg = dict(data["damage_by_floor"])
    if not data["contracts"]:
        r.text(surface, "None signed.", (40, y), C.TEXT_DIM, r.small)
    for depth, key in data["contracts"]:
        r.text(surface, f"Floor {depth}: {CONTRACTS[key]['name']} ({CONTRACTS[key]['sponsor']}). "
                        f"That floor: {gold.get(depth, 0)} gold, {dmg.get(depth, 0)} damage taken.",
               (40, y), C.TEXT, r.small)
        y += 20
    r.text(surface, f"Boxes opened: {t['boxes']}   Rerolls: {t['rerolls']}   "
                    "Grey lines on the viewer chart mark each new floor.",
           (40, max(y + 10, 500)), C.TEXT_DIM, r.small)
    r.text(surface, "Enter or Esc: back", (cx, C.SCREEN_H - 40), C.TEXT_DIM, r.font, centre=True)

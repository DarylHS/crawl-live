"""Shared helpers for the analysis notebooks: loading the run tables and chart style."""
import sys
from pathlib import Path

import matplotlib as mpl
import matplotlib.pyplot as plt
import pandas as pd

ROOT = Path(__file__).resolve().parents[1]
RUNS = ROOT / "runs"
sys.path.insert(0, str(ROOT))                   # so notebooks can import crawler.*

# Validated categorical palette, used in this fixed order (never cycled).
SERIES = ["#2a78d6", "#eb6834", "#1baf7a", "#eda100", "#e87ba4", "#008300", "#6250d6", "#e34948"]
SEQUENTIAL = "#2a78d6"
MUTED = "#8a8985"
TEXT = "#0b0b0b"
TEXT_2 = "#52514e"
GRID = "#e6e5e1"
SURFACE = "#fcfcfb"

# Fixed colour per entity, so a companion or class is the same colour in every chart.
PET_COLOURS = dict(zip(["cat", "dog", "budgie", "mouse"], SERIES))
CLASS_COLOURS = dict(zip(["brawler", "arcanist", "analyst"], SERIES))


def load(table, source="bot"):
    """Read runs/<source>_<table>.csv. source="all" stacks bot and player runs."""
    sources = ["bot", "player"] if source == "all" else [source]
    frames = [pd.read_csv(RUNS / f"{s}_{table}.csv") for s in sources
              if (RUNS / f"{s}_{table}.csv").exists()]
    if not frames:
        raise FileNotFoundError(f"No {table} data in {RUNS}. Run: python analysis/bot.py --runs 2000")
    return pd.concat(frames, ignore_index=True)


def has_player_runs():
    return (RUNS / "player_runs.csv").exists()


def style():
    """Quiet axes and grid, readable text; data marks carry the colour."""
    mpl.rcParams.update({
        "figure.facecolor": SURFACE, "axes.facecolor": SURFACE, "savefig.facecolor": SURFACE,
        "figure.dpi": 110, "figure.figsize": (8, 4.2),
        "font.size": 10, "axes.titlesize": 12, "axes.titleweight": "bold",
        "axes.titlelocation": "left", "axes.labelcolor": TEXT_2, "text.color": TEXT,
        "xtick.color": TEXT_2, "ytick.color": TEXT_2,
        "axes.edgecolor": GRID, "axes.grid": True, "axes.grid.axis": "y",
        "grid.color": GRID, "grid.linewidth": 0.8,
        "axes.spines.top": False, "axes.spines.right": False,
        "axes.prop_cycle": mpl.cycler(color=SERIES),
        "lines.linewidth": 2, "lines.markersize": 6, "legend.frameon": False,
    })


def pct_axis(ax, axis="y"):
    """Whole-number percentage ticks."""
    fmt = mpl.ticker.PercentFormatter(1, decimals=0)
    (ax.yaxis if axis == "y" else ax.xaxis).set_major_formatter(fmt)


def value_grid(ax):
    """For horizontal dot/interval plots the value axis is x, so grid on x only."""
    ax.grid(axis="x", visible=True)
    ax.grid(axis="y", visible=False)


def label_line_ends(ax, lines, labels, fmt="{:.0%}", dx=0.15):
    """Direct-label the last point of each line in ink (identity comes from the marker beside it)."""
    for line, label in zip(lines, labels):
        x, y = line.get_xdata()[-1], line.get_ydata()[-1]
        ax.annotate(f"{label} {fmt.format(y)}", (x, y), xytext=(x + dx, y), va="center",
                    color=TEXT_2, fontsize=9)
        ax.plot([x], [y], "o", color=line.get_color(), markersize=6)


def wilson(successes, n, z=1.96):
    """95% Wilson score interval for a proportion: better than p +/- 1.96 SE near 0 or 1."""
    if n == 0:
        return (float("nan"), float("nan"))
    p = successes / n
    denom = 1 + z * z / n
    centre = (p + z * z / (2 * n)) / denom
    half = z * ((p * (1 - p) / n + z * z / (4 * n * n)) ** 0.5) / denom
    return centre - half, centre + half

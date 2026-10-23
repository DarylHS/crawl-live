"""Overlay menus: inventory, safe-room menu and the box reveal."""
import pygame

from .. import config as C
from ..items import ITEMS, describe, glyph
from ..loot import BOX_TIERS
from .screens import overlay

X0, WIDTH = 330, 620


def _frame(r, surface, title, y=90, h=560):
    overlay(surface)
    pygame.draw.rect(surface, C.PANEL_BG, (X0, y, WIDTH, h))
    pygame.draw.rect(surface, C.WALL_LIT, (X0, y, WIDTH, h), 1)
    r.text(surface, title, (X0 + WIDTH // 2, y + 28), C.ACCENT, r.big, centre=True)


def inventory_rows(world):
    """Selectable rows: equipped items first, then the pack."""
    rows = [("equip", slot, key) for slot, key in world.equipment.items() if key]
    return rows + [("pack", i, key) for i, key in enumerate(world.inventory)]


def draw_inventory(r, surface, world, cursor):
    _frame(r, surface, "INVENTORY")
    rows = inventory_rows(world)
    y = 140
    for i, (where, ref, key) in enumerate(rows):
        it = ITEMS[key]
        if i == cursor:
            surface.fill((50, 46, 70), (X0 + 10, y - 2, WIDTH - 20, 22))
        tag = f"[{ref}]" if where == "equip" else ""
        r.text(surface, glyph(key), (X0 + 22, y), it["colour"])
        r.text(surface, f"{it['name']} {tag}", (X0 + 46, y), C.TEXT)
        r.text(surface, describe(key), (X0 + 290, y), C.TEXT_DIM, r.small)
        y += 24
    if not rows:
        r.text(surface, "Nothing but lint.", (X0 + 46, y), C.TEXT_DIM)
    r.text(surface, f"Pack {len(world.inventory)}/{C.INVENTORY_SIZE}   Boxes {len(world.boxes)}",
           (X0 + 22, 560), C.TEXT_DIM, r.small)
    if rows:
        r.text(surface, ITEMS[rows[cursor][2]]["desc"], (X0 + 22, 585), C.TEXT, r.small)
    r.text(surface, "Up/Down select   Enter use/equip   U unequip   D drop   Esc close",
           (X0 + WIDTH // 2, 625), C.TEXT_DIM, r.small, centre=True)


def menu_options(world):
    """Safe-room menu entries as (action, tier, label)."""
    opts = [("rest", None, "Rest to full HP")]
    for tier in BOX_TIERS:
        n = world.boxes.count(tier)
        if n:
            opts.append(("box", tier, f"Open a {BOX_TIERS[tier]['name']} box (x{n})"))
    return opts


def draw_safe_menu(r, surface, world, cursor):
    _frame(r, surface, "SAFE ROOM", 160, 380)
    y = 220
    for i, (action, tier, label) in enumerate(menu_options(world)):
        if i == cursor:
            surface.fill((50, 46, 70), (X0 + 10, y - 2, WIDTH - 20, 26))
        colour = BOX_TIERS[tier]["colour"] if tier else C.TEXT
        r.text(surface, label, (X0 + 30, y), colour)
        y += 30
    r.text(surface, "Shop, crafting and saving arrive in later phases.", (X0 + 30, 470),
           C.TEXT_DIM, r.small)
    r.text(surface, "Up/Down select   Enter choose   Esc close", (X0 + WIDTH // 2, 510),
           C.TEXT_DIM, r.small, centre=True)


def draw_reveal(r, surface, world):
    tier, key = world.last_reveal
    box = BOX_TIERS[tier]
    _frame(r, surface, f"{box['name'].upper()} BOX", 200, 300)
    it = ITEMS[key]
    cx = X0 + WIDTH // 2
    r.text(surface, glyph(key), (cx, 300), it["colour"], r.huge, centre=True)
    r.text(surface, it["name"], (cx, 360), it["colour"], r.big, centre=True)
    r.text(surface, describe(key), (cx, 392), C.TEXT, r.font, centre=True)
    r.text(surface, it["desc"], (cx, 418), C.TEXT_DIM, r.small, centre=True)
    r.text(surface, "Added to your pack. Press Enter", (cx, 470), C.GOOD, r.font, centre=True)

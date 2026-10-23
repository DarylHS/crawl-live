"""Overlay menus: inventory, safe-room menu and the box reveal."""
import pygame

from .. import config as C
from ..classes import CLASSES, RACES, SKILLS
from ..crafting import CRAFT_TURNS, RECIPES, can_craft
from ..entities import PETS
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
    if world.pet and world.pet.downed:
        opts.append(("revive", None, f"Revive {world.pet.name} ({C.PET_REVIVE_TURNS} min)"))
    for tier in BOX_TIERS:
        n = world.boxes.count(tier)
        if n:
            opts.append(("box", tier, f"Open a {BOX_TIERS[tier]['name']} box (x{n})"))
    opts.append(("craft", None, "Crafting bench"))
    opts.append(("save", None, "Save and quit to title"))
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
    r.text(surface, "The shop opens in a later phase.", (X0 + 30, 470), C.TEXT_DIM, r.small)
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


def draw_craft(r, surface, world, cursor):
    _frame(r, surface, "CRAFTING BENCH", 140, 440)
    y = 200
    for i, rec in enumerate(RECIPES):
        ok = can_craft(rec, world.inventory)
        if i == cursor:
            surface.fill((50, 46, 70), (X0 + 10, y - 2, WIDTH - 20, 44))
        out = ITEMS[rec["makes"]]
        r.text(surface, f"{rec['name']}  ->  {out['name']}", (X0 + 30, y),
               out["colour"] if ok else C.TEXT_DIM)
        parts = " + ".join(ITEMS[k]["name"] for k in rec["needs"])
        r.text(surface, f"{parts}   {'ready' if ok else 'missing parts'}", (X0 + 30, y + 20),
               C.GOOD if ok else C.TEXT_DIM, r.small)
        y += 52
    r.text(surface, RECIPES[cursor]["desc"], (X0 + 30, 430), C.TEXT, r.small)
    r.text(surface, f"Each craft takes {CRAFT_TURNS} minutes of floor time.", (X0 + 30, 455),
           C.TEXT_DIM, r.small)
    r.text(surface, "Up/Down select   Enter craft   Esc back", (X0 + WIDTH // 2, 550),
           C.TEXT_DIM, r.small, centre=True)


def class_rows(step):
    return list(RACES) if step == "race" else list(CLASSES)


def draw_class_select(r, surface, world, step, race, cursor):
    title = "CHOOSE YOUR RACE" if step == "race" else "CHOOSE YOUR CLASS"
    _frame(r, surface, title, 100, 530)
    r.text(surface, "The System has decided you're interesting enough for a class.",
           (X0 + WIDTH // 2, 180), C.TEXT_DIM, r.small, centre=True)
    if race:
        r.text(surface, f"Race: {RACES[race]['name']}", (X0 + WIDTH // 2, 200), C.ACCENT,
               r.small, centre=True)
    y = 225
    table = RACES if step == "race" else CLASSES
    for i, key in enumerate(class_rows(step)):
        spec = table[key]
        lines = [spec["desc"]]
        if "skill" in spec:
            sk = SKILLS[spec["skill"]]
            lines += _wrap(r, f"Skill (1): {sk['name']}, every {sk['cooldown']} turns. "
                              f"{sk['desc']}", WIDTH - 60)
        h = 30 + 17 * len(lines)
        if i == cursor:
            surface.fill((50, 46, 70), (X0 + 10, y - 4, WIDTH - 20, h + 4))
        r.text(surface, spec["name"], (X0 + 30, y), C.ACCENT if i == cursor else C.TEXT, r.big)
        for j, line in enumerate(lines):
            r.text(surface, line, (X0 + 30, y + 28 + j * 17), C.TEXT if j == 0 else C.TEXT_DIM,
                   r.small)
        y += h + 12
    r.text(surface, "Up/Down select   Enter choose", (X0 + WIDTH // 2, 605), C.TEXT_DIM,
           r.small, centre=True)


def draw_pet_select(r, surface, species_idx, name):
    surface.fill(C.BG)
    cx = C.SCREEN_W // 2
    r.text(surface, "PICK YOUR COMPANION", (cx, 140), C.ACCENT, r.big, centre=True)
    r.text(surface, "Every contestant gets one. It's in the contract.", (cx, 172), C.TEXT_DIM,
           r.font, centre=True)
    for i, (key, spec) in enumerate(PETS.items()):
        x = cx - 300 + i * 320
        sel = i == species_idx
        pygame.draw.rect(surface, C.ACCENT if sel else C.WALL_DIM, (x, 220, 280, 200),
                         2 if sel else 1)
        r.text(surface, spec["glyph"], (x + 140, 270), spec["colour"], r.huge, centre=True)
        r.text(surface, spec["name"], (x + 140, 325), C.TEXT, r.big, centre=True)
        for j, line in enumerate(_wrap(r, spec["desc"], 250)):
            r.text(surface, line, (x + 140, 355 + j * 17), C.TEXT_DIM, r.small, centre=True)
    shown = name or PETS[list(PETS)[species_idx]]["default_name"]
    r.text(surface, "Name:", (cx - 160, 470), C.TEXT_DIM, r.font)
    r.text(surface, shown + ("_" if name else ""), (cx - 100, 466),
           C.TEXT if name else C.TEXT_DIM, r.big)
    r.text(surface, "Left/Right choose   type a name   Enter start   Esc back", (cx, 540),
           C.TEXT_DIM, r.font, centre=True)


def _wrap(r, text, width):
    lines, line = [], ""
    for word in text.split():
        trial = f"{line} {word}".strip()
        if r.small.size(trial)[0] > width and line:
            lines.append(line)
            line = word
        else:
            line = trial
    return lines + [line] if line else lines

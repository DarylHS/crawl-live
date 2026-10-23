"""Overlay menus: inventory, safe-room menu and the box reveal."""
import pygame

from .. import config as C
from ..classes import CLASSES, RACES, SKILLS
from ..crafting import CRAFT_TURNS, RECIPES, can_craft
from ..entities import PETS
from ..contracts import CONTRACTS, preview
from ..items import ITEMS, describe, glyph
from ..loot import BOX_TIERS, TRADE_UP_COST, box_stats, next_tier, odds, reroll_fee
from ..shop import BASE_DEMAND
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
            opts.append(("box", tier, f"{BOX_TIERS[tier]['name']} boxes (x{n}): odds, open, trade"))
    opts.append(("shop", None, f"Shop ({world.gold} gold)"))
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
    r.text(surface, "Up/Down select   Enter choose   Esc close", (X0 + WIDTH // 2, 510),
           C.TEXT_DIM, r.small, centre=True)


def draw_reveal(r, surface, world):
    tier, key = world.last_reveal
    box = BOX_TIERS[tier]
    _frame(r, surface, f"{box['name'].upper()} BOX", 200, 340)
    it = ITEMS[key]
    cx = X0 + WIDTH // 2
    r.text(surface, glyph(key), (cx, 300), it["colour"], r.huge, centre=True)
    r.text(surface, it["name"], (cx, 360), it["colour"], r.big, centre=True)
    r.text(surface, describe(key), (cx, 392), C.TEXT, r.font, centre=True)
    r.text(surface, it["desc"], (cx, 418), C.TEXT_DIM, r.small, centre=True)
    ev, sd = box_stats(tier)
    v = it["value"]
    verdict = "above" if v > ev else "below" if v < ev else "exactly"
    r.text(surface, f"Worth {v} gold: {verdict} this box's average of {ev:.1f} (give or take "
                    f"{sd:.1f}).", (cx, 445), C.TEXT, r.small, centre=True)
    fee = reroll_fee(tier)
    if key in world.inventory:
        r.text(surface, f"R: hand it back and reroll for {fee} gold (you have {world.gold}).",
               (cx, 470), C.TEXT_DIM, r.small, centre=True)
        r.text(surface, f"A reroll pays on average only if this is worth under "
                        f"{ev:.1f} - {fee} = {ev - fee:.1f} gold.",
               (cx, 488), C.TEXT_DIM, r.small, centre=True)
    r.text(surface, "Enter: keep it", (cx, 512), C.GOOD, r.font, centre=True)


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
    box_w, gap = 260, 20
    left = cx - (len(PETS) * box_w + (len(PETS) - 1) * gap) // 2
    for i, (key, spec) in enumerate(PETS.items()):
        x = left + i * (box_w + gap)
        sel = i == species_idx
        pygame.draw.rect(surface, C.ACCENT if sel else C.WALL_DIM, (x, 220, box_w, 220),
                         2 if sel else 1)
        mid = x + box_w // 2
        r.text(surface, spec["glyph"], (mid, 270), spec["colour"], r.huge, centre=True)
        r.text(surface, spec["name"], (mid, 325), C.TEXT, r.big, centre=True)
        for j, line in enumerate(_wrap(r, spec["desc"], box_w - 24)):
            r.text(surface, line, (mid, 355 + j * 17), C.TEXT_DIM, r.small, centre=True)
    shown = name or PETS[list(PETS)[species_idx]]["default_name"]
    r.text(surface, "Name:", (cx - 160, 480), C.TEXT_DIM, r.font)
    r.text(surface, shown + ("_" if name else ""), (cx - 100, 476),
           C.TEXT if name else C.TEXT_DIM, r.big)
    r.text(surface, "Left/Right choose   type a name   Enter start   Esc back", (cx, 550),
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


def draw_box_info(r, surface, world, tier):
    """Odds disclosure: the real drop table, expected value and spread, before opening."""
    box = BOX_TIERS[tier]
    _frame(r, surface, f"{box['name'].upper()} BOX", 110, 520)
    r.text(surface, "The System is legally required to show you the odds.", (X0 + WIDTH // 2, 160),
           C.TEXT_DIM, r.small, centre=True)
    y = 195
    r.text(surface, "Item", (X0 + 40, y), C.TEXT_DIM, r.small)
    r.text(surface, "Chance", (X0 + 330, y), C.TEXT_DIM, r.small)
    r.text(surface, "Worth", (X0 + 470, y), C.TEXT_DIM, r.small)
    y += 22
    for key, p in sorted(odds(tier), key=lambda row: -row[1]):
        it = ITEMS[key]
        r.text(surface, it["name"], (X0 + 40, y), it["colour"])
        surface.fill(C.WALL_DIM, (X0 + 330, y + 4, 100, 10))
        surface.fill(box["colour"], (X0 + 330, y + 4, round(100 * p), 10))
        r.text(surface, f"{p:.0%}", (X0 + 436, y), C.TEXT, r.small)
        r.text(surface, f"{it['value']} gold", (X0 + 470, y), C.TEXT, r.small)
        y += 26
    ev, sd = box_stats(tier)
    y += 10
    r.text(surface, f"Expected value {ev:.1f} gold, give or take {sd:.1f}.", (X0 + 40, y), C.TEXT)
    r.text(surface, "('Give or take' is one standard deviation: most boxes land within it.)",
           (X0 + 40, y + 20), C.TEXT_DIM, r.small)
    y += 50
    to = next_tier(tier)
    have = world.boxes.count(tier)
    if to:
        ev2, sd2 = box_stats(to)
        r.text(surface, f"T: trade {TRADE_UP_COST} for one {BOX_TIERS[to]['name']} box "
                        f"(you have {have}).", (X0 + 40, y), C.TEXT if have >= TRADE_UP_COST
               else C.TEXT_DIM)
        r.text(surface, f"In: {TRADE_UP_COST} x {ev:.1f} = {TRADE_UP_COST * ev:.1f} gold.   "
                        f"Out: {ev2:.1f}, give or take {sd2:.1f}.", (X0 + 40, y + 20), C.TEXT_DIM,
               r.small)
    y += 56
    r.text(surface, f"Rerolling a {box['name']} box after opening costs {reroll_fee(tier)} gold.",
           (X0 + 40, y), C.TEXT_DIM, r.small)
    r.text(surface, "Enter open   T trade up   Esc back", (X0 + WIDTH // 2, 600), C.TEXT_DIM,
           r.small, centre=True)


def shop_rows(world, mode):
    if mode == "buy":
        return list(BASE_DEMAND)
    return list(range(len(world.inventory)))


def draw_shop(r, surface, world, cursor, mode):
    shop = world.shop
    _frame(r, surface, "SAFE ROOM SHOP", 70, 600)
    tabs = "BUY   sell" if mode == "buy" else "buy   SELL"
    r.text(surface, f"{tabs}   (Tab to switch)     Your gold: {world.gold}",
           (X0 + WIDTH // 2, 120), C.TEXT_DIM, r.small, centre=True)
    rows = shop_rows(world, mode)
    y = 150
    if mode == "buy":
        heads = (("Item", 30), ("Price", 215), ("Stock", 275), ("Forecast", 350),
                 ("Reorder at", 450), ("On order", 540))
        for label, dx in heads:
            r.text(surface, label, (X0 + dx, y), C.TEXT_DIM, r.small)
        y += 20
        for i, key in enumerate(rows):
            s = shop.stock[key]
            if i == cursor:
                surface.fill((50, 46, 70), (X0 + 10, y - 2, WIDTH - 20, 22))
            out = s.on_hand == 0
            price = shop.price(key)
            r.text(surface, ITEMS[key]["name"], (X0 + 30, y), C.TEXT_DIM if out else ITEMS[key]["colour"],
                   r.small)
            r.text(surface, f"{price}" + ("*" if price > ITEMS[key]["value"] else ""), (X0 + 215, y),
                   C.ACCENT if price > ITEMS[key]["value"] else C.TEXT, r.small)
            r.text(surface, "OUT" if out else str(s.on_hand), (X0 + 275, y),
                   C.DANGER if out else C.TEXT, r.small)
            r.text(surface, f"{s.forecast:.1f}/floor", (X0 + 350, y), C.TEXT, r.small)
            r.text(surface, f"{shop.reorder_point(key):.1f}", (X0 + 450, y), C.TEXT, r.small)
            r.text(surface, str(s.on_order) if s.on_order else "-", (X0 + 540, y), C.TEXT, r.small)
            y += 24
        key = rows[cursor]
        s = shop.stock[key]
        notes = [f"Other crawlers buy about {s.forecast:.1f} {ITEMS[key]['name']}s a floor (forecast). "
                 f"Safety stock: {shop.safety_stock(key):.1f}.",
                 "Stock arrives one floor after it's ordered. When stock falls to the reorder point, "
                 "the shop orders enough to cover two floors plus safety stock.",
                 "* price is up because stock is low. Prices drop when deliveries land."]
        if s.history:
            notes.insert(0, f"Demand on recent floors: {', '.join(map(str, s.history[-5:]))}.")
        y += 10
        for note in notes:
            for line in _wrap(r, note, WIDTH - 60):
                r.text(surface, line, (X0 + 30, y), C.TEXT_DIM, r.small)
                y += 17
            y += 4
    else:
        r.text(surface, "Item", (X0 + 30, y), C.TEXT_DIM, r.small)
        r.text(surface, "They pay", (X0 + 330, y), C.TEXT_DIM, r.small)
        y += 20
        for i in rows:
            key = world.inventory[i]
            if i == cursor:
                surface.fill((50, 46, 70), (X0 + 10, y - 2, WIDTH - 20, 22))
            r.text(surface, ITEMS[key]["name"], (X0 + 30, y), ITEMS[key]["colour"], r.small)
            r.text(surface, f"{shop.sell_price(key)} gold", (X0 + 330, y), C.TEXT, r.small)
            y += 22
        if not rows:
            r.text(surface, "Nothing to sell.", (X0 + 30, y), C.TEXT_DIM, r.small)
        r.text(surface, "The shop pays 40% of an item's value. Junk sells too.", (X0 + 30, 600),
               C.TEXT_DIM, r.small)
    r.text(surface, f"Up/Down select   Enter {mode}   Tab buy/sell   Esc back",
           (X0 + WIDTH // 2, 650), C.TEXT_DIM, r.small, centre=True)


def draw_contract(r, surface, world):
    c = CONTRACTS[world.pending_offer]
    _frame(r, surface, "SPONSOR OFFER", 150, 400)
    cx = X0 + WIDTH // 2
    r.text(surface, f"{c['sponsor']} presents: {c['name']}", (cx, 210), C.ACCENT, r.font, centre=True)
    r.text(surface, c["desc"], (cx, 240), C.TEXT, r.small, centre=True)
    r.text(surface, "This floor only. What it means for you:", (X0 + 40, 280), C.TEXT_DIM, r.small)
    y = 302
    for line in preview(world, world.pending_offer):
        for part in _wrap(r, line, WIDTH - 90):
            r.text(surface, part, (X0 + 50, y), C.TEXT, r.small)
            y += 18
        y += 4
    r.text(surface, "Y accept   N decline", (cx, 520), C.TEXT_DIM, r.font, centre=True)

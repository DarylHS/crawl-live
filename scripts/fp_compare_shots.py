"""Replay the Godot screenshots (first-person, top-down map, minimap) in pygame, for a side by side.

    xvfb-run -a godot --path godot --rendering-driver opengl3 -s res://tools/screenshots.gd \
        -- --screenshots=OUT/godot
    python scripts/fp_compare_shots.py OUT/godot/shots.json --pygame OUT/pygame --side OUT/side_by_side

godot/tools/screenshots.gd writes shots.json: for each shot the seed, pet and hero, the floors it
made with new_floor, the edits it made to the world (monsters cleared or spawned, items dropped,
the player moved, the Headliner's key, a fight started), the look angle and the exact camera
[x, y, a]. The rules are seed-for-seed identical in both versions, so the same seed and edits give
the same world. Each record has a "view":
  fp       crawler/ui/firstperson.py at 320 x 200, scaled to 1024 x 640 with hard pixels (no overlays)
  top      the map view (Renderer.draw_map) cropped to the 1024 x 640 map area
  minimap  the first-person minimap and "Facing X" label, cropped and scaled 3x like the Godot close-up
  hud_fp / hud_top  the whole 1280 x 768 window through `Renderer.draw_game` (side panel, log, tracker,
           toasts, chevrons, "ahead" label) in the first-person or map view, with the death and victory
           overlays when the run has ended (P6)
and with --side, Godot is pasted left and pygame right.

P7 menus and screens: godot/tools/screenshots.gd also writes <name>_top.png and <name>_fp.png for every
screen of tests/test_render.py (title, creation, inventory, safe room, boxes, shop, craft, reports, combat,
help, ... 77 names), under pygame's own names. Run the pygame side with
`CRAWL_SCREENSHOTS=OUT/pygame_raw python -m pytest tests/test_render.py` and pair them by file name:
    python scripts/fp_compare_shots.py OUT/godot --menus OUT/pygame_raw --pygame OUT/pygame --side OUT/side_by_side
(the first argument may be the Godot directory instead of its shots.json when only menus are paired). The Godot sprite sheet (sprite_sheet.png) is
paired with pygame's creature_sprite for the same keys (sprite_sheet in --pygame / --side).
"""
import argparse
import json
import os
import sys

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import pygame  # noqa: E402

from crawler import config as C  # noqa: E402
from crawler.bosses import spawn_act, spawn_boss  # noqa: E402
from crawler.entities import MONSTERS, PETS, spawn_monster  # noqa: E402
from crawler.bosses import BOSSES  # noqa: E402
from crawler.ui.firstperson import TIER_OUTLINE, FirstPersonView, creature_sprite  # noqa: E402
from crawler.encounter import Encounter  # noqa: E402
from crawler.ui import screens  # noqa: E402
from crawler.ui.hud import Renderer  # noqa: E402
from crawler.world import World  # noqa: E402

OUT_SIZE = (1024, 640)


def build_world(spec, shot):
    pet = tuple(spec["pet"]) if spec["pet"] else None
    w = World(spec["seed"], pet=pet, hero=spec["hero"])
    for d in shot["floors"]:
        w.new_floor(d)
    for edit in shot["edits"]:
        kind = edit[0]
        if kind == "quiet":
            w.monsters.clear()
            if w.pet:
                w.pet.downed = True
        elif kind == "clear_monsters":
            w.monsters.clear()
        elif kind == "place":
            w.player.x, w.player.y = edit[1], edit[2]
            w.update_fov()
        elif kind == "has_key":
            w.has_key = True
        elif kind in ("mon", "act", "boss"):
            if kind == "mon":
                m = spawn_monster(edit[1], edit[3], edit[4])
            elif kind == "act":
                m = spawn_act(edit[1], edit[2], edit[3], edit[4])
            else:
                m = spawn_boss(int(edit[1]), edit[3], edit[4])
            m.hp = max(1, int(m.max_hp * edit[5]))
            w.monsters.append(m)
        elif kind == "item":
            w.floor_items[(edit[2], edit[3])] = [edit[1]]
        elif kind == "pet_to":
            w.pet.x, w.pet.y = edit[1], edit[2]
        elif kind == "spawn_fight":
            m = spawn_monster(edit[1], edit[2], edit[3])
            m.hp = m.max_hp = 999
            w.monsters.append(m)
            w.update_fov()
            assert w.join_combat(m)
            w.combat.round = 1
            m.stunned = 99
        elif kind == "fight":                        # a sturdy, stunned fighter and the fight on (P6 shots)
            m = spawn_boss(w.depth, edit[2], edit[3]) if edit[1] == "boss" else spawn_monster(edit[1], edit[2], edit[3])
            m.hp = m.max_hp = 999
            w.monsters.append(m)
            w.update_fov()
            assert w.join_combat(m)
            w.combat.round = 1
            m.stunned = 0 if len(edit) > 4 else 99
        elif kind == "player_hp":
            w.player.max_hp = w.player.hp = edit[1]
        elif kind == "move":
            w.move_player(edit[1], edit[2])
        elif kind == "wait":
            w.wait()
        elif kind == "toast":
            w.add_toast(edit[1], edit[2], edit[3])
        elif kind == "encounter":
            w.combat = enc = Encounter(w.player)
            enc.add(w.player, 10, 1)
            for i in range(edit[1]):
                enc.add(spawn_monster("goblin", 0, 0), i, 0)
        elif kind == "class":
            assert w.choose_class(edit[1], edit[2])
        elif kind == "use_skill":
            assert w.use_skill()
        elif kind == "box":
            w.add_box(edit[1], "A screenshot test.")
        elif kind == "gold":
            w.gold = edit[1]
        elif kind == "state":
            w.state, w.death_cause = edit[1], edit[2]
        else:
            raise ValueError(f"unknown edit {edit!r}")
    w.update_fov()
    return w


def _first_person(w, shot):
    v = FirstPersonView()
    v._prepare_floor(w)
    v._faced_floor = w.floor          # draw() would otherwise turn you to face the open way
    v.angle = shot["angle"]
    v.grid = shot["grid"]
    v.cam = list(shot["cam"])
    return v


def render(spec, shot):
    w = build_world(spec, shot)
    assert [w.player.x, w.player.y] == shot["player"], (shot["name"], w.player.x, w.player.y)
    kind = shot.get("view", "fp")
    if kind == "top":
        r = Renderer()
        screen = pygame.Surface((C.SCREEN_W, C.SCREEN_H))
        screen.fill(C.BG)
        r.draw_map(screen, w)
        return screen.subsurface((0, 0, *OUT_SIZE)).copy()
    v = _first_person(w, shot)
    if kind in ("hud_fp", "hud_top"):
        r = Renderer()
        screen = pygame.Surface((C.SCREEN_W, C.SCREEN_H))
        r.draw_game(screen, w, v if kind == "hud_fp" else None, 1, hud=w.state == "playing")
        if w.state == "dead":
            screens.draw_death(r, screen, w)
        elif w.state == "victory":
            screens.draw_victory(r, screen, w)
        return screen
    if kind == "minimap":
        screen = pygame.Surface((C.SCREEN_W, C.SCREEN_H))
        v.draw(screen, w, pygame.Rect(0, 0, *OUT_SIZE))
        r = v.minimap_rect
        crop = pygame.Rect(r.x - 2, r.y - 2, r.width + 4, r.height + 40)
        return pygame.transform.scale(screen.subsurface(crop).copy(), (crop.w * 3, crop.h * 3))
    return pygame.transform.scale(v.render(w), OUT_SIZE)


def sprite_sheet(spec_dir):
    """Pygame's creature sprites for the creature keys of Godot's sheet, 3 x 36 px cells."""
    with open(os.path.join(spec_dir, "sprite_sheet_keys.json")) as f:
        meta = json.load(f)
    cols = meta["columns"]
    rows = -(-len(meta["keys"]) // cols)
    sheet = pygame.Surface((cols * 108, rows * 108))
    sheet.fill((52, 48, 64))
    for i, key in enumerate(meta["keys"]):
        kind, _, name = key.partition(":")
        if kind not in ("mon", "boss", "pet"):
            continue                                   # items and furniture are glyphs in pygame
        tier = ""
        look = name
        for t in ("opening", "featured"):
            if name.startswith(t + "_"):
                tier, look = t, name[len(t) + 1:]
        if kind == "boss":
            tier, colour = "headliner", BOSSES[int(look.split("_")[1])]["colour"]
        elif kind == "pet":
            colour = PETS[look]["colour"]
        else:
            colour = MONSTERS[look]["colour"]
        spr = creature_sprite(look, colour, TIER_OUTLINE.get(tier, (14, 12, 18)))
        sheet.blit(pygame.transform.scale(spr, (96, 96)), ((i % cols) * 108 + 6, (i // cols) * 108 + 6))
    return sheet


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("shots", help="shots.json from godot/tools/screenshots.gd, or its directory (menus only)")
    ap.add_argument("--menus", help="directory of pygame menu PNGs (CRAWL_SCREENSHOTS of tests/test_render.py) to pair "
                                    "with Godot's <name>_<view>.png of the same name")
    ap.add_argument("--pygame", required=True, help="directory for the pygame PNGs")
    ap.add_argument("--side", help="directory for side by side PNGs (Godot left, pygame right)")
    args = ap.parse_args()
    pygame.init()
    if os.path.isdir(args.shots):
        spec, godot_dir = {"shots": []}, os.path.abspath(args.shots)
    else:
        with open(args.shots) as f:
            spec = json.load(f)
        godot_dir = os.path.dirname(os.path.abspath(args.shots))
    os.makedirs(args.pygame, exist_ok=True)
    if args.side:
        os.makedirs(args.side, exist_ok=True)
    font = pygame.font.SysFont("dejavusansmono,monospace", 22, bold=True)

    def pair(name, gimg, img):
        pygame.image.save(img, os.path.join(args.pygame, name + ".png"))
        if args.side:
            h = max(gimg.get_height(), img.get_height())
            side = pygame.Surface((gimg.get_width() + img.get_width() + 16, h + 40))
            side.fill((12, 11, 16))
            side.blit(gimg, (0, 40))
            side.blit(img, (gimg.get_width() + 16, 40))
            side.blit(font.render(f"Godot: {name}", True, (225, 222, 235)), (8, 8))
            side.blit(font.render("pygame (Phase 7)", True, (225, 222, 235)), (gimg.get_width() + 24, 8))
            pygame.image.save(side, os.path.join(args.side, name + ".png"))
        print(f"{name}")

    done = {shot["name"] for shot in spec["shots"]}
    if args.menus:
        for fname in sorted(os.listdir(args.menus)):
            name = fname[:-4]
            if fname.endswith(".png") and name not in done and os.path.exists(os.path.join(godot_dir, fname)):
                pair(name, pygame.image.load(os.path.join(godot_dir, fname)),
                     pygame.image.load(os.path.join(args.menus, fname)))
    for shot in spec["shots"]:
        img = render(spec, shot)
        gimg = pygame.image.load(os.path.join(godot_dir, shot["name"] + ".png"))
        pair(shot["name"], gimg, img)
    if os.path.exists(os.path.join(godot_dir, "sprite_sheet_keys.json")):
        pair("sprite_sheet", pygame.image.load(os.path.join(godot_dir, "sprite_sheet.png")),
             sprite_sheet(godot_dir))
    pygame.quit()


if __name__ == "__main__":
    main()

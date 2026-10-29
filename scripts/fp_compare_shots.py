"""Replay the Godot first-person screenshots in the Python raycaster, for a side by side.

    xvfb-run -a godot --path godot --rendering-driver opengl3 -s res://tools/screenshots.gd \
        -- --screenshots=OUT/godot
    python scripts/fp_compare_shots.py OUT/godot/shots.json --pygame OUT/pygame --side OUT/side_by_side

godot/tools/screenshots.gd writes shots.json: for each shot the seed, pet and hero, the floors it
made with new_floor, the edits it made to the world (monsters cleared, the player moved, the
Headliner's key, a fight started), the look angle and the exact camera [x, y, a]. The rules are
seed-for-seed identical in both versions, so the same seed and edits give the same world; this
script renders it with crawler/ui/firstperson.py (read only) at 320 x 200, scales it to
1024 x 640 with hard pixels and, with --side, pastes Godot left and pygame right.
"""
import argparse
import json
import os
import sys

os.environ.setdefault("SDL_VIDEODRIVER", "dummy")
sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))

import pygame  # noqa: E402

from crawler.entities import spawn_monster  # noqa: E402
from crawler.ui.firstperson import FirstPersonView  # noqa: E402
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
        elif kind == "place":
            w.player.x, w.player.y = edit[1], edit[2]
            w.update_fov()
        elif kind == "has_key":
            w.has_key = True
        elif kind == "spawn_fight":
            m = spawn_monster(edit[1], edit[2], edit[3])
            m.hp = m.max_hp = 999
            w.monsters.append(m)
            w.update_fov()
            assert w.join_combat(m)
            w.combat.round = 1
            m.stunned = 99
        else:
            raise ValueError(f"unknown edit {edit!r}")
    w.update_fov()
    return w


def render(spec, shot):
    w = build_world(spec, shot)
    assert [w.player.x, w.player.y] == shot["player"], (shot["name"], w.player.x, w.player.y)
    v = FirstPersonView()
    v._prepare_floor(w)
    v.angle = shot["angle"]
    v.grid = shot["grid"]
    v.cam = list(shot["cam"])
    return pygame.transform.scale(v.render(w), OUT_SIZE)


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("shots", help="shots.json from godot/tools/screenshots.gd")
    ap.add_argument("--pygame", required=True, help="directory for the pygame PNGs")
    ap.add_argument("--side", help="directory for side by side PNGs (Godot left, pygame right)")
    args = ap.parse_args()
    pygame.init()
    with open(args.shots) as f:
        spec = json.load(f)
    godot_dir = os.path.dirname(os.path.abspath(args.shots))
    os.makedirs(args.pygame, exist_ok=True)
    if args.side:
        os.makedirs(args.side, exist_ok=True)
    font = pygame.font.SysFont("dejavusansmono,monospace", 22, bold=True)
    for shot in spec["shots"]:
        img = render(spec, shot)
        path = os.path.join(args.pygame, shot["name"] + ".png")
        pygame.image.save(img, path)
        if args.side:
            gimg = pygame.image.load(os.path.join(godot_dir, shot["name"] + ".png"))
            side = pygame.Surface((OUT_SIZE[0] * 2 + 16, OUT_SIZE[1] + 40))
            side.fill((12, 11, 16))
            side.blit(gimg, (0, 40))
            side.blit(img, (OUT_SIZE[0] + 16, 40))
            side.blit(font.render(f"Godot: {shot['name']}", True, (225, 222, 235)), (8, 8))
            side.blit(font.render("pygame (Phase 7)", True, (225, 222, 235)), (OUT_SIZE[0] + 24, 8))
            pygame.image.save(side, os.path.join(args.side, shot["name"] + ".png"))
        print(f"{shot['name']}: {path}")
    pygame.quit()


if __name__ == "__main__":
    main()

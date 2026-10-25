"""First-person proof of concept.  Usage: python fp_demo.py [--seed N] [--pet dog]

Same rules, same turns, seen through the crawler's eyes. Controls:
  W / Up        step forward (attacks whatever is ahead, or front-left / front-right)
  S / Down      step back
  A / D         strafe left / right
  Q / E, Left / Right   turn 90 degrees (free: turning costs no time)
  Space or .    wait a turn         G   pick up       R   rest (safe rooms)
  Enter or >    descend a stairwell Tab  overhead map  Esc  quit
"""
import argparse
import random

import pygame

from crawler import config as C
from crawler.entities import PETS
from crawler.ui.firstperson import FirstPersonView
from crawler.ui.hud import Renderer
from crawler.world import World

VIEW = pygame.Rect(0, 0, C.MAP_W * C.TILE, C.MAP_H * C.TILE)


def main(seed=None, pet="dog"):
    pygame.init()
    screen = pygame.display.set_mode((C.SCREEN_W, C.SCREEN_H))
    pygame.display.set_caption("Crawl Live! (first-person preview)")
    seed = random.randrange(1_000_000) if seed is None else seed
    world = World(seed, pet=(pet, PETS[pet]["default_name"]))
    hud, view = Renderer(), FirstPersonView()
    overhead, clock = False, pygame.time.Clock()
    while True:
        dt = clock.tick(60) / 1000
        for ev in pygame.event.get():
            if ev.type == pygame.QUIT or ev.type == pygame.KEYDOWN and ev.key == pygame.K_ESCAPE:
                return
            if ev.type != pygame.KEYDOWN:
                continue
            k = ev.key
            if world.state != "playing":
                if k == pygame.K_r:
                    world, view = World(random.randrange(1_000_000), pet=(pet, PETS[pet]["default_name"])), \
                        FirstPersonView()
                continue
            if k in (pygame.K_w, pygame.K_UP):
                m, step = view.target_ahead(world)
                world.move_player(*(step if m else view.relative("forward")))
            elif k in (pygame.K_s, pygame.K_DOWN):
                world.move_player(*view.relative("back"))
            elif k == pygame.K_a:
                world.move_player(*view.relative("left"))
            elif k == pygame.K_d:
                world.move_player(*view.relative("right"))
            elif k in (pygame.K_q, pygame.K_LEFT):
                view.turn(-1)
            elif k in (pygame.K_e, pygame.K_RIGHT):
                view.turn(1)
            elif k in (pygame.K_SPACE, pygame.K_PERIOD):
                world.wait()
            elif k == pygame.K_g:
                world.pickup()
            elif k == pygame.K_r:
                world.rest()
            elif k in (pygame.K_RETURN, pygame.K_KP_ENTER) or ev.unicode == ">":
                world.descend()
            elif k == pygame.K_TAB:
                overhead = not overhead
        screen.fill(C.BG)
        if overhead:
            hud.draw_map(screen, world)
        else:
            view.draw(screen, world, VIEW, dt=min(1.0, dt * 14))
        hud.draw_panel(screen, world)
        hud.draw_log(screen, world)
        hud.draw_toasts(screen, world)
        if world.state != "playing":
            msg = "YOU DIED" if world.state == "dead" else "YOU SURVIVED"
            hud.text(screen, f"{msg}   R: new run   Esc: quit", VIEW.center, C.ACCENT, hud.big, centre=True)
        pygame.display.flip()


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Crawl Live! first-person preview")
    ap.add_argument("--seed", type=int)
    ap.add_argument("--pet", choices=list(PETS), default="dog")
    args = ap.parse_args()
    main(args.seed, args.pet)

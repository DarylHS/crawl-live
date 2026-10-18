"""pygame front end: scene state machine, input mapping and the main loop.

Rendering only happens after input, since the game is turn-based.
"""
import pygame

from . import config as C
from .ui import screens
from .ui.hud import Renderer
from .world import World

MOVES = {
    pygame.K_UP: (0, -1), pygame.K_w: (0, -1), pygame.K_KP8: (0, -1),
    pygame.K_DOWN: (0, 1), pygame.K_s: (0, 1), pygame.K_KP2: (0, 1),
    pygame.K_LEFT: (-1, 0), pygame.K_a: (-1, 0), pygame.K_KP4: (-1, 0),
    pygame.K_RIGHT: (1, 0), pygame.K_d: (1, 0), pygame.K_KP6: (1, 0),
    pygame.K_KP7: (-1, -1), pygame.K_KP9: (1, -1),
    pygame.K_KP1: (-1, 1), pygame.K_KP3: (1, 1),
}
WAIT_KEYS = {pygame.K_PERIOD, pygame.K_SPACE, pygame.K_KP5}
DESCEND_KEYS = {pygame.K_RETURN, pygame.K_KP_ENTER}


class App:
    def __init__(self, screen=None, seed=None):
        if not pygame.get_init():
            pygame.init()
        self.screen = screen or pygame.display.set_mode((C.SCREEN_W, C.SCREEN_H))
        pygame.display.set_caption("Crawl Live!")
        self.renderer = Renderer()
        self.seed = seed
        self.scene = "title"        # "title" | "game"
        self.world: World | None = None
        self.show_help = False
        self.running = True

    def start_run(self):
        self.world = World(self.seed)
        self.seed = None            # only the first run uses a fixed seed
        self.scene = "game"
        self.show_help = False

    # --- Input ---------------------------------------------------------

    def handle_key(self, event):
        key, ch = event.key, event.unicode
        if ch == "?":
            self.show_help = not self.show_help
            return
        if self.show_help:
            if key == pygame.K_ESCAPE:
                self.show_help = False
            return

        if self.scene == "title":
            if key in DESCEND_KEYS:
                self.start_run()
            elif key == pygame.K_ESCAPE:
                self.running = False
            return

        world = self.world
        if key == pygame.K_ESCAPE:
            self.scene = "title"
        elif world.state != "playing":
            if key in DESCEND_KEYS:
                self.start_run()
        elif ch == ">" or key in DESCEND_KEYS:
            world.descend()
        elif key in MOVES:
            world.move_player(*MOVES[key])
        elif key in WAIT_KEYS:
            world.wait()
        elif key == pygame.K_r:
            world.rest()

    # --- Drawing -------------------------------------------------------

    def draw(self):
        r, s = self.renderer, self.screen
        if self.scene == "title":
            screens.draw_title(r, s)
        else:
            r.draw_game(s, self.world)
            if self.world.state == "dead":
                screens.draw_death(r, s, self.world)
            elif self.world.state == "victory":
                screens.draw_victory(r, s, self.world)
        if self.show_help:
            screens.draw_help(r, s)

    def run(self):
        clock = pygame.time.Clock()
        dirty = True
        while self.running:
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False
                elif event.type == pygame.KEYDOWN:
                    self.handle_key(event)
                    dirty = True
                elif event.type in (pygame.WINDOWEXPOSED, pygame.VIDEOEXPOSE):
                    dirty = True
            if dirty:
                self.draw()
                pygame.display.flip()
                dirty = False
            clock.tick(C.FPS)
        pygame.quit()


def main(seed=None):
    App(seed=seed).run()

"""Draw every scene headless to catch rendering crashes.

Set CRAWL_SCREENSHOTS=<folder> to save a PNG of each scene for a visual check.
"""
import os

import pygame
import pytest

from crawler import config as C
from crawler.game import App


@pytest.fixture
def app():
    pygame.init()
    a = App(screen=pygame.Surface((C.SCREEN_W, C.SCREEN_H)), seed=1)
    yield a
    pygame.quit()


def _key(key, unicode=""):
    return pygame.event.Event(pygame.KEYDOWN, key=key, unicode=unicode, mod=0)


def _shot(app, name):
    app.draw()
    out = os.environ.get("CRAWL_SCREENSHOTS")
    if out:
        os.makedirs(out, exist_ok=True)
        pygame.image.save(app.screen, os.path.join(out, f"{name}.png"))


def test_all_scenes_draw(app):
    _shot(app, "title")
    app.handle_key(_key(pygame.K_RETURN))
    assert app.scene == "game"
    for _ in range(4):
        app.handle_key(_key(pygame.K_RIGHT))
    _shot(app, "game")

    # Reveal the whole map so the screenshot shows the full layout.
    for row in app.world.floor.explored:
        row[:] = [True] * len(row)
    _shot(app, "game_revealed")

    app.handle_key(_key(pygame.K_SLASH, "?"))
    assert app.show_help
    _shot(app, "help")
    app.handle_key(_key(pygame.K_SLASH, "?"))

    app.world.state, app.world.death_cause = "dead", "Killed by a unit test on floor 1"
    _shot(app, "death")
    app.world.state = "victory"
    _shot(app, "victory")

    app.handle_key(_key(pygame.K_RETURN))       # new run from the end screen
    assert app.world.state == "playing"

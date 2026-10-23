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
    assert app.scene == "pet_select"
    for ch in "Rex":
        app.handle_key(_key(getattr(pygame, f"K_{ch.lower()}"), ch))
    app.handle_key(_key(pygame.K_RIGHT))
    _shot(app, "pet_select")
    app.handle_key(_key(pygame.K_RETURN))
    assert app.scene == "game" and app.world.pet.name == "Rex" and app.world.pet.species == "dog"
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
    assert app.scene == "pet_select"
    app.handle_key(_key(pygame.K_RETURN))
    assert app.world.state == "playing" and app.world.pet


def test_item_screens_draw(app):
    app.handle_key(_key(pygame.K_RETURN))
    app.handle_key(_key(pygame.K_RETURN))
    w = app.world
    w.inventory = ["pan", "jersey", "tonic", "popper", "sock", "elixir"]
    w.equip(0)
    w.floor_items[(w.player.x + 1, w.player.y)] = ["brew"]
    w.add_box("bronze", "test")
    w.add_box("legendary", "test")
    w.toasts.append((w.turn, "Achievement: First Blood", "silver"))
    _shot(app, "game_items")

    app.handle_key(_key(pygame.K_i, "i"))
    assert app.overlay == "inventory"
    app.handle_key(_key(pygame.K_DOWN))
    _shot(app, "inventory")
    app.handle_key(_key(pygame.K_d, "d"))               # drop the selected item
    assert len(w.inventory) == 4
    app.handle_key(_key(pygame.K_ESCAPE))
    assert app.overlay is None and app.scene == "game"

    app.handle_key(_key(pygame.K_m, "m"))               # not in a safe room
    assert app.overlay is None
    w.player.x, w.player.y = w.floor.safe_room.centre
    w.update_fov()
    app.handle_key(_key(pygame.K_m, "m"))
    assert app.overlay == "safe"
    app.handle_key(_key(pygame.K_DOWN))
    _shot(app, "safe_menu")
    app.handle_key(_key(pygame.K_RETURN))               # open the bronze box
    assert app.overlay == "reveal" and w.last_reveal
    _shot(app, "box_reveal")
    app.handle_key(_key(pygame.K_RETURN))
    assert app.overlay == "safe"
    app.handle_key(_key(pygame.K_ESCAPE))

    w.state, w.death_cause = "dead", "Killed by a unit test"
    _shot(app, "death_viewers")


def test_phase3_screens_draw(tmp_path):
    pygame.init()
    app = App(screen=pygame.Surface((C.SCREEN_W, C.SCREEN_H)), seed=3,
              save_path=tmp_path / "slot.json")
    app.handle_key(_key(pygame.K_RETURN))
    app.handle_key(_key(pygame.K_RETURN))                # default cat
    w = app.world
    w.new_floor(3)
    app.handle_key(_key(pygame.K_PERIOD, "."))           # any key opens the class picker
    assert app.overlay == "class"
    _shot(app, "class_race")
    app.handle_key(_key(pygame.K_DOWN))
    app.handle_key(_key(pygame.K_RETURN))                # elf
    app.handle_key(_key(pygame.K_DOWN))
    app.handle_key(_key(pygame.K_DOWN))
    _shot(app, "class_class")
    app.handle_key(_key(pygame.K_RETURN))                # analyst
    assert w.cls == "analyst" and app.overlay is None

    for row in w.floor.explored:
        row[:] = [True] * len(row)
    w.visible = {(m.x, m.y) for m in w.monsters} | w.visible
    w.scout_turns = 20
    _shot(app, "scout_report")

    w.pet.downed = True
    w.inventory = ["sock", "mug", "trophy", "pan"]
    w.player.x, w.player.y = w.floor.safe_room.centre
    w.update_fov()
    app.handle_key(_key(pygame.K_m, "m"))
    _shot(app, "safe_menu_p3")
    labels = [o[0] for o in __import__("crawler.ui.menus", fromlist=["x"]).menu_options(w)]
    app.cursor = labels.index("craft")
    app.handle_key(_key(pygame.K_RETURN))
    assert app.overlay == "craft"
    _shot(app, "craft")
    app.handle_key(_key(pygame.K_RETURN))                # sock tea
    assert "tonic" in w.inventory
    app.handle_key(_key(pygame.K_ESCAPE))
    assert app.overlay == "safe"
    app.cursor = labels.index("save")
    app.handle_key(_key(pygame.K_RETURN))
    assert app.scene == "title" and (tmp_path / "slot.json").exists()
    _shot(app, "title_with_save")
    app.handle_key(_key(pygame.K_l, "l"))
    assert app.scene == "game" and app.world.cls == "analyst" and app.world.pet.downed
    pygame.quit()

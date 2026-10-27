"""Draw every scene headless to catch rendering crashes.

Set CRAWL_SCREENSHOTS=<folder> to save a PNG of each scene for a visual check; each
scene is saved twice, as <name>_top.png and <name>_fp.png. Every App here passes
settings_path=None (or a tmp_path) so tests never write the repo's saves/.
"""
import json
import os

import pygame
import pytest

from crawler import config as C
from crawler.game import App
from crawler.ui import firstperson as fpv
from crawler.ui import menus, screens

VIEWS = ("top", "fp")


@pytest.fixture
def app():
    pygame.init()
    a = App(screen=pygame.Surface((C.SCREEN_W, C.SCREEN_H)), seed=1, runs_dir=None,
            settings_path=None)
    yield a
    pygame.quit()


def _key(key, unicode=""):
    return pygame.event.Event(pygame.KEYDOWN, key=key, unicode=unicode, mod=0)


def _shot(app, name):
    """Draw the scene in both views (dt=1 snaps the camera), then restore the view."""
    out = os.environ.get("CRAWL_SCREENSHOTS")
    view = app.view
    for app.view in ("top", "fp"):
        app.draw(dt=1)
        if out:
            os.makedirs(out, exist_ok=True)
            pygame.image.save(app.screen, os.path.join(out, f"{name}_{app.view}.png"))
    app.view = view


def _start(app):
    for _ in range(4):                                   # title, identity, backstory, companion
        app.handle_key(_key(pygame.K_RETURN))
    return app.world


def _empty(w, x, y):
    return w.floor.walkable(x, y) and not w.monster_at(x, y) and not w.pet_at(x, y)


def _record(w, name):
    """A list that collects every `name` event the world emits from now on."""
    seen = []
    w.events.subscribe(name, lambda n, d: seen.append(d))
    return seen


@pytest.mark.parametrize("view", VIEWS)
def test_all_scenes_draw(app, view):
    app.view = view
    _shot(app, "title")
    app.handle_key(_key(pygame.K_RETURN))
    assert app.scene == "identity"
    for ch in "Daz":
        app.handle_key(_key(getattr(pygame, f"K_{ch.lower()}"), ch))
    app.handle_key(_key(pygame.K_RIGHT))                 # Man
    _shot(app, "identity")
    app.handle_key(_key(pygame.K_RETURN))
    assert app.scene == "backstory"
    for _ in range(5):
        app.handle_key(_key(pygame.K_DOWN))              # Tradie
    _shot(app, "backstory")
    app.handle_key(_key(pygame.K_RETURN))
    assert app.scene == "pet_select"
    for ch in "Rex":
        app.handle_key(_key(getattr(pygame, f"K_{ch.lower()}"), ch))
    app.handle_key(_key(pygame.K_RIGHT))
    _shot(app, "pet_select")
    app.handle_key(_key(pygame.K_RETURN))
    assert app.scene == "game" and app.world.pet.name == "Rex" and app.world.pet.species == "dog"
    assert app.world.hero_name == "Daz" and app.world.gender == "male" and app.world.backstory == "tradie"
    app.view = "top"                                     # the walk below uses absolute arrows
    for _ in range(4):
        app.handle_key(_key(pygame.K_RIGHT))
    app.view = view
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
    assert app.scene == "identity"
    for _ in range(3):
        app.handle_key(_key(pygame.K_RETURN))
    assert app.world.state == "playing" and app.world.pet and app.view == view


@pytest.mark.parametrize("view", VIEWS)
def test_item_screens_draw(app, view):
    app.view = view
    for _ in range(4):                                   # title, identity, backstory, companion
        app.handle_key(_key(pygame.K_RETURN))
    w = app.world
    w.inventory = ["pan", "jersey", "tonic", "popper", "sock", "elixir"]
    w.equip(0)
    w.floor_items[(w.player.x + 1, w.player.y)] = ["brew"]
    w.add_box("bronze", "Show Stopper: The Shrink-Wrapped Colossus. Took down floor 5's Headliner, "
                        "The Shrink-Wrapped Colossus.")
    w.add_box("legendary", "test")
    w.toasts.append((w.turn, "Achievement: First Blood", "silver", "Silver box. Open it in a safe room."))
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
    app.handle_key(_key(pygame.K_RETURN))               # bronze box odds
    assert app.overlay == "box"
    _shot(app, "box_odds")
    app.handle_key(_key(pygame.K_RETURN))               # open it
    assert app.overlay == "reveal" and w.last_reveal
    _shot(app, "box_reveal")
    app.handle_key(_key(pygame.K_RETURN))
    assert app.overlay == "safe"
    app.handle_key(_key(pygame.K_ESCAPE))

    w.state, w.death_cause = "dead", "Killed by a unit test"
    _shot(app, "death_viewers")


@pytest.mark.parametrize("view", VIEWS)
def test_phase3_screens_draw(tmp_path, view):
    pygame.init()
    app = App(screen=pygame.Surface((C.SCREEN_W, C.SCREEN_H)), seed=3,
              save_path=tmp_path / "slot.json", runs_dir=None, settings_path=None)
    app.view = view
    for _ in range(4):                                   # defaults, cat
        app.handle_key(_key(pygame.K_RETURN))
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
    assert w.cls == "analyst"
    if app.overlay == "contract":                       # floor 3 may come with a sponsor offer
        app.handle_key(_key(pygame.K_n, "n"))
    assert app.overlay is None

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
    labels = [o[0] for o in __import__("crawler.ui.menus", fromlist=["x"]).menu_options(w)]
    app.cursor = labels.index("save")                    # crafting earned a box, so rows moved
    app.handle_key(_key(pygame.K_RETURN))
    assert app.scene == "title" and (tmp_path / "slot.json").exists()
    _shot(app, "title_with_save")
    app.handle_key(_key(pygame.K_l, "l"))
    assert app.scene == "game" and app.world.cls == "analyst" and app.world.pet.downed
    pygame.quit()


@pytest.mark.parametrize("view", VIEWS)
def test_phase4_screens_draw(tmp_path, view):
    pygame.init()
    app = App(screen=pygame.Surface((C.SCREEN_W, C.SCREEN_H)), seed=5,
              save_path=tmp_path / "slot.json", runs_dir=None, settings_path=None)
    app.view = view
    for _ in range(4):                                   # title, identity, backstory, companion
        app.handle_key(_key(pygame.K_RETURN))
    w = app.world
    w.new_floor(2)
    w.pending_offer = "hazard_pay"
    app.handle_key(_key(pygame.K_PERIOD, "."))
    assert app.overlay == "contract"
    _shot(app, "contract")
    app.handle_key(_key(pygame.K_y, "y"))
    assert w.contract == "hazard_pay" and app.overlay is None

    w.gold = 200
    w.boxes = ["silver"] * 4
    w.player.x, w.player.y = w.floor.safe_room.centre
    w.update_fov()
    app.handle_key(_key(pygame.K_m, "m"))
    labels = [o[0] for o in __import__("crawler.ui.menus", fromlist=["x"]).menu_options(w)]
    app.cursor = labels.index("shop")
    app.handle_key(_key(pygame.K_RETURN))
    assert app.overlay == "shop"
    app.handle_key(_key(pygame.K_RETURN))                # buy a tonic
    assert "tonic" in w.inventory and w.gold < 200
    _shot(app, "shop_buy")
    app.handle_key(_key(pygame.K_TAB))                   # Tab in the shop is buy/sell, not the view
    assert app.shop_mode == "sell" and app.view == view and app.overlay == "shop"
    _shot(app, "shop_sell")
    app.handle_key(_key(pygame.K_ESCAPE))
    assert app.overlay == "safe"

    labels = [o[0] for o in __import__("crawler.ui.menus", fromlist=["x"]).menu_options(w)]
    app.cursor = labels.index("box")
    app.handle_key(_key(pygame.K_RETURN))
    assert app.overlay == "box" and app.box_tier == "silver"
    _shot(app, "box_odds_silver")
    app.handle_key(_key(pygame.K_t, "t"))                # trade 3 silver for a gold
    assert w.boxes.count("gold") == 1 and w.boxes.count("silver") == 1
    app.handle_key(_key(pygame.K_RETURN))                # open the remaining silver
    assert app.overlay == "reveal"
    _shot(app, "reveal_reroll")
    gold = w.gold
    app.handle_key(_key(pygame.K_r, "r"))                # reroll
    assert w.gold < gold and len(w.box_log) == 2

    w.state, w.death_cause = "dead", "Killed by a unit test on floor 2"
    app.overlay = None
    app.handle_key(_key(pygame.K_r, "r"))
    assert app.overlay == "report"
    _shot(app, "report")
    app.handle_key(_key(pygame.K_ESCAPE))
    assert app.overlay is None
    pygame.quit()


@pytest.mark.parametrize("view", VIEWS)
def test_attribute_screen_spends_points(app, view):
    app.view = view
    for _ in range(4):
        app.handle_key(_key(pygame.K_RETURN, "\r"))
    w = app.world
    pts = w.player.stat_points
    app.handle_key(_key(pygame.K_l, "l"))
    assert app.overlay == "attributes"
    _shot(app, "attributes")
    app.handle_key(_key(pygame.K_RETURN, "\r"))             # first row: Strength
    assert w.player.stat_points == pts - 1 and w.player.attrs["str"] == 11
    app.handle_key(_key(pygame.K_l, "l"))
    assert app.overlay is None
    _shot(app, "game_attributes_panel")


def test_tab_toggles_and_remembers_the_view(tmp_path):
    pygame.init()
    path = tmp_path / "settings.json"
    screen = pygame.Surface((C.SCREEN_W, C.SCREEN_H))
    app = App(screen=screen, seed=1, runs_dir=None, settings_path=path)
    assert app.view == "fp" and not path.exists()        # first-person on a fresh install
    _start(app)
    app.handle_key(_key(pygame.K_i, "i"))
    app.handle_key(_key(pygame.K_TAB))                   # an open menu swallows Tab
    assert app.view == "fp" and app.overlay == "inventory"
    app.handle_key(_key(pygame.K_ESCAPE))
    turn = app.world.turn
    app.handle_key(_key(pygame.K_TAB))
    assert app.view == "top" and app.world.turn == turn
    assert json.loads(path.read_text()) == {"view": "top"}
    _shot(app, "game_tab")
    assert App(screen=screen, runs_dir=None, settings_path=path).view == "top"
    app.handle_key(_key(pygame.K_TAB))
    assert app.view == "fp" and App(screen=screen, runs_dir=None, settings_path=path).view == "fp"
    pygame.quit()


def test_movement_follows_the_view(app):
    w = _start(app)
    w.monsters.clear()
    assert app.view == "fp"
    v = app.fp
    for _ in range(8):                                   # face somewhere D can strafe to
        dx, dy = v.relative("right")
        if _empty(w, w.player.x + dx, w.player.y + dy):
            break
        app.handle_key(_key(pygame.K_e, "e"))
    turn, (x, y) = w.turn, (w.player.x, w.player.y)
    assert turn == 0                                     # turning was free
    app.draw(dt=1)
    assert not app.animating()
    app.handle_key(_key(pygame.K_d, "d"))
    assert (w.player.x, w.player.y) == (x + dx, y + dy) and w.turn == turn + 1
    app.draw(dt=0.05)                                    # mid-glide: the loop keeps drawing
    assert app.animating()
    app.draw(dt=1)
    assert not app.animating()
    angle = v.angle
    app.handle_key(_key(pygame.K_LEFT))                  # a tap turns 45 degrees
    assert v.angle == (angle - 45) % 360 and w.turn == turn + 1

    app.view = "top"
    spot = next((x, y) for y in range(w.floor.height) for x in range(w.floor.width)
                if _empty(w, x, y) and _empty(w, x + 1, y))
    w.player.x, w.player.y = spot
    w.update_fov()
    app.handle_key(_key(pygame.K_d, "d"))
    assert (w.player.x, w.player.y) == (spot[0] + 1, spot[1])


def test_forward_attacks_and_a_monster_in_view_draws(app):
    from crawler.entities import spawn_monster
    w = _start(app)
    w.monsters.clear()
    v, p = app.fp, w.player
    for _ in range(4):                                   # face an open tile
        fx, fy = v.relative("forward")
        if _empty(w, p.x + fx, p.y + fy) and _empty(w, p.x + 2 * fx, p.y + 2 * fy):
            break
        v.turn(1)
    assert not w.in_safe_room
    w.monsters.append(spawn_monster("goblin", p.x + 2 * fx, p.y + 2 * fy))
    w.update_fov()
    _shot(app, "game_monster")
    w.monsters.clear()
    goblin = spawn_monster("goblin", p.x + fx, p.y + fy)
    w.monsters.append(goblin)
    w.update_fov()
    _shot(app, "game_monster_adjacent")
    turn, pos = w.turn, (p.x, p.y)
    attacks = _record(w, "player_attack")
    app.handle_key(_key(pygame.K_w, "w"))                # bump: attack (hit or miss), don't move
    assert (p.x, p.y) == pos and len(attacks) == 1
    # The attack starts combat and is your action; a one-hit kill ends it and passes the turn.
    assert (not w.combat.has("action")) if w.combat else w.turn == turn + 1


def test_tab_still_cycles_gender_and_species(app):
    app.handle_key(_key(pygame.K_RETURN))
    g = app.gender_idx
    app.handle_key(_key(pygame.K_TAB))
    assert app.scene == "identity" and app.gender_idx != g and app.view == "fp"
    app.handle_key(_key(pygame.K_RETURN))
    app.handle_key(_key(pygame.K_RETURN))
    pet = app.pet_idx
    app.handle_key(_key(pygame.K_TAB))
    assert app.scene == "pet_select" and app.pet_idx != pet and app.view == "fp"


def test_help_lists_the_controls_for_the_view(app):
    def text(rows):
        return " ".join(f"{k} {what}" for k, what in rows)
    surf = pygame.Surface((C.SCREEN_W, C.SCREEN_H))
    fp, top = (text(screens.draw_help(app.renderer, surf, v)) for v in ("fp", "top"))
    assert "Q / E" in fp and "strafe" in fp and "hold" in fp and "Q / E" not in top
    assert "numpad" in top and "Arrows / WASD" not in fp
    assert "Tab switch view" in fp and "Tab switch view" in top
    _start(app)
    app.handle_key(_key(pygame.K_SLASH, "?"))
    _shot(app, "help_game")                              # draws each view's own list


def test_menus_in_first_person_leave_you_where_you_were(app):
    w = _start(app)
    assert app.view == "fp"
    w.monsters.clear()
    v, p = app.fp, w.player

    def check(opened, *keys, cursor_keys=True):
        """Open with the first key, W/S the cursor, close with the rest: no move, no turn."""
        pos, facing, turn = (p.x, p.y), v.facing, w.turn
        app.handle_key(_key(*opened))
        assert app.overlay or app.show_help
        app.draw(dt=1)
        if cursor_keys:
            app.handle_key(_key(pygame.K_s, "s"))
            app.handle_key(_key(pygame.K_w, "w"))
        for k in keys:
            app.handle_key(_key(*k))
        assert not app.overlay and not app.show_help
        assert (p.x, p.y) == pos and v.facing == facing and w.turn == turn

    w.inventory = ["tonic", "pan"]
    app.handle_key(_key(pygame.K_i, "i"))
    app.handle_key(_key(pygame.K_s, "s"))                # S moves the cursor, not the player
    assert app.cursor == 1
    app.handle_key(_key(pygame.K_ESCAPE))
    check((pygame.K_i, "i"), (pygame.K_ESCAPE,))
    check((pygame.K_i, "i"), (pygame.K_i, "i"))
    check((pygame.K_k, "k"), (pygame.K_k, "k"), cursor_keys=False)
    check((pygame.K_l, "l"), (pygame.K_l, "l"))
    check((pygame.K_SLASH, "?"), (pygame.K_SLASH, "?"))

    w.remote_shop = True                                 # a Supply Drop out in the dungeon
    app.overlay, app.cursor, app.shop_mode = "shop", 0, "buy"
    _shot(app, "shop_remote")
    app.handle_key(_key(pygame.K_TAB))                   # no selling from a Supply Drop
    assert app.shop_mode == "buy" and app.view == "fp"
    app.handle_key(_key(pygame.K_ESCAPE))
    assert app.overlay is None and not w.remote_shop

    w.player.x, w.player.y = w.floor.safe_room.centre
    w.update_fov()
    v.face_open(w)
    w.add_box("bronze", "test")
    check((pygame.K_m, "m"), (pygame.K_ESCAPE,))
    labels = [o[0] for o in menus.menu_options(w)]
    for action, back in (("shop", 2), ("craft", 2), ("box", 2)):
        app.handle_key(_key(pygame.K_m, "m"))
        app.cursor = labels.index(action)
        app.handle_key(_key(pygame.K_RETURN))
        assert app.overlay == action
        check_pos = (p.x, p.y), v.facing
        app.draw(dt=1)
        for _ in range(back):
            app.handle_key(_key(pygame.K_ESCAPE))
        assert app.overlay is None and ((p.x, p.y), v.facing) == check_pos


def test_menus_hide_the_first_person_overlays(app, monkeypatch):
    w = _start(app)
    drawn = []
    monkeypatch.setattr(app.fp, "_minimap", lambda *a: drawn.append("minimap"))
    monkeypatch.setattr(app.fp, "_ahead", lambda *a: drawn.append("ahead"))
    app.draw(dt=1)
    assert drawn == ["minimap", "ahead"]
    for setup in (lambda: app.open_overlay("inventory"), lambda: setattr(app, "show_help", True),
                  lambda: setattr(w, "state", "dead")):
        app.overlay, app.show_help, w.state = None, False, "playing"
        setup()
        drawn.clear()
        w.player.hp -= 1                                 # a hit behind the menu doesn't flash later
        app.draw(dt=1)
        assert drawn == [] and app.fp.flash == 0


def test_tab_back_to_first_person_has_no_stale_hurt_flash(app):
    w = _start(app)
    app.draw(dt=1)
    app.handle_key(_key(pygame.K_TAB))
    assert app.view == "top"
    w.player.hp -= 3                                     # hurt while on the map
    app.draw(dt=1)
    app.handle_key(_key(pygame.K_TAB))
    app.draw(dt=1)
    assert app.fp.flash == 0 and not app.animating()


def _open_run(floor, x, y, d):
    dx, dy = fpv.DIRS[d]
    n = 0
    while floor.walkable(x + dx * (n + 1), y + dy * (n + 1)):
        n += 1
    return n


def test_new_runs_and_floors_face_the_most_open_way(app, tmp_path):
    w = _start(app)
    p, v = w.player, app.fp

    def facing_is_open():
        best = max(_open_run(w.floor, p.x, p.y, d) for d in range(4))
        return _open_run(w.floor, p.x, p.y, v.facing) == best > 0

    assert facing_is_open()
    v.turn(1)
    w.new_floor(2)                                       # what descend does
    app.handle_key(_key(pygame.K_PERIOD, "."))
    assert facing_is_open()
    v.turn(1)
    from crawler import save
    app.save_path = tmp_path / "slot.json"
    save.save(w, app.save_path)
    app.load_run()
    w, p = app.world, app.world.player
    assert facing_is_open()


def test_attributes_and_shop_text_fit_their_panel(app):
    small = app.renderer.small
    assert menus.ATTR_SOURCE_X + small.size(menus.attr_source(10, 20))[0] <= menus.WIDTH - 20
    assert menus.ATTR_SOURCE_X + small.size(menus.attr_source(10, 4))[0] <= menus.WIDTH - 20
    label, dx = menus.SHOP_COLS[-1]
    assert dx + small.size(label)[0] <= menus.WIDTH - 30


def test_end_screens_ignore_tab(app):
    w = _start(app)
    w.state, w.death_cause = "dead", "Killed by a unit test"
    app.handle_key(_key(pygame.K_TAB))
    assert app.view == "fp" and app.scene == "game"
    app.handle_key(_key(pygame.K_RETURN))
    assert app.scene == "identity"


def test_skills_screen_draws(app):
    from crawler.practice import SKILLS as PRACTICE
    w = _start(app)
    for i, key in enumerate(list(PRACTICE)[::2]):        # some discovered, some still ???
        w.training.gain(key, 3 * i + 1)
    app.handle_key(_key(pygame.K_k, "k"))
    assert app.overlay == "skills"
    _shot(app, "skills")
    app.handle_key(_key(pygame.K_k, "k"))
    assert app.overlay is None
    room = menus.WIDTH - menus.PRACTICE_TEXT_X - 14
    for sk in PRACTICE.values():                          # every effect line fits the panel
        for text in (sk["effect"], sk["trains"]):
            fitted = menus._fit(app.renderer, text, room)
            assert app.renderer.small.size(fitted)[0] <= room and fitted[:12] == text[:12]


def test_contract_text_fits_its_panel(app):
    from crawler.contracts import CONTRACTS
    w = _start(app)
    surf = pygame.Surface((C.SCREEN_W, C.SCREEN_H))
    for key in CONTRACTS:
        w.pending_offer = key
        rects = menus.draw_contract(app.renderer, surf, w)
        *body, footer = rects
        for r in rects:
            assert menus.X0 + 10 <= r.left and r.right <= menus.X0 + menus.WIDTH - 10, key
        assert body[-1].bottom < footer.top, key


def test_help_fits_the_map_area(app):
    font, right = app.renderer.font, C.VIEW_W * C.TILE - 10
    for view in VIEWS:
        rows = screens.controls(view)
        for keys, what in rows:
            assert screens.HELP_CX - 20 - font.size(keys)[0] >= 10, keys
            assert screens.HELP_CX + 20 + font.size(what)[0] <= right, what
        y0 = screens.help_top(rows)
        assert y0 - 70 - app.renderer.big.get_height() // 2 >= 0             # the title
        close_bottom = y0 + len(rows) * screens.HELP_STEP + 14 + font.get_height() // 2
        assert close_bottom <= C.VIEW_H * C.TILE - 4, view                     # above the log


def test_inventory_names_clear_the_stats_column(app):
    from crawler.items import ITEMS
    font, small = app.renderer.font, app.renderer.small
    for it in ITEMS.values():
        assert 46 + font.size(f"{it['name']} [weapon]")[0] + 10 <= menus.INV_STATS_X, it["name"]
    assert menus._fit(app.renderer, "a long line of text", 1) == "..."    # never loops forever


def test_report_is_opaque_and_its_caption_sits_inside(app, monkeypatch):
    from crawler.ui.report import draw_report
    w = _start(app)
    w.gold = 500
    w.add_box("bronze", "test")
    w.player.x, w.player.y = w.floor.safe_room.centre
    w.update_fov()
    assert w.open_box("bronze") and w.box_log
    w.state, w.death_cause = "dead", "Killed by a unit test"
    surf = app.screen
    app.draw(dt=1)                                       # the death screen behind
    drawn = []
    text = app.renderer.text
    monkeypatch.setattr(app.renderer, "text", lambda s, t, *a, **k: drawn.append((t, text(s, t, *a, **k)))
                        or drawn[-1][1])
    draw_report(app.renderer, surf, w)
    for x, y in ((435, 200), (845, 300), (600, 400), (20, 200)):    # between and under panels
        assert tuple(surf.get_at((x, y)))[:3] == C.BG
    caption = next(r for t, r in drawn if t.endswith("than average."))
    assert caption.bottom < 90 + 300 - 2 and caption.top > 90


def _corridor(w, n, dirs=range(8)):
    """A tile and a direction (0-7) with exactly n empty tiles ahead, then something solid."""
    f = w.floor
    for y in range(f.height):
        for x in range(f.width):
            if not _empty(w, x, y) or f.safe[y][x]:
                continue
            for d, (dx, dy) in enumerate(fpv.DIRS8):
                if d not in dirs:
                    continue
                run = 0
                while _empty(w, x + dx * (run + 1), y + dy * (run + 1)):
                    run += 1
                if run == n and not f.walkable(x + dx * (n + 1), y + dy * (n + 1)):
                    return (x, y), d
    raise AssertionError("no corridor")


def _place(app, spot, d):
    w = app.world
    w.player.x, w.player.y = spot
    w.update_fov()
    app.fp.angle = d * 45 + 10                           # off the line: walking still picks it
    app.fp.reset_camera()
    app.draw(dt=1)


def test_holding_w_walks_a_tile_per_turn_and_stops_at_a_wall(app):
    w = _start(app)
    w.monsters.clear()
    w.pet.downed = True                                  # nothing in the way
    spot, d = _corridor(w, 3)
    _place(app, spot, d)
    dx, dy = fpv.DIRS8[d]
    turn, frames = w.turn, 0
    while w.turn < turn + 3:
        app.update(1 / 30, held={pygame.K_w})
        frames += 1
        assert frames < 60
    assert 0.4 <= frames / 30 <= 1.0                     # about 4 tiles a second
    for _ in range(60):                                  # keep holding into the wall
        app.update(1 / 30, held={pygame.K_w})
    assert w.turn == turn + 3 and (w.player.x, w.player.y) == (spot[0] + 3 * dx, spot[1] + 3 * dy)
    app.update(1 / 30, held=set())
    assert app.fp.glide_left(w) == 0                     # rests on the tile centre
    assert app.fp.cam[:2] == [w.player.x + 0.5, w.player.y + 0.5]

    back = w.turn                                        # S walks back the way you came
    for _ in range(12):
        app.update(1 / 30, held={pygame.K_s})
    assert w.turn > back and (w.player.x - spot[0]) * dx + (w.player.y - spot[1]) * dy < 3


def test_holding_w_into_a_monster_attacks_once(app):
    from crawler.entities import spawn_monster
    w = _start(app)
    w.monsters.clear()
    w.pet.downed = True
    spot, d = _corridor(w, 3)
    _place(app, spot, d)
    dx, dy = fpv.DIRS8[d]
    goblin = spawn_monster("goblin", spot[0] + dx, spot[1] + dy)
    goblin.hp = goblin.max_hp = 999
    w.monsters.append(goblin)
    attacks = _record(w, "player_attack")
    for _ in range(30):
        app.update(1 / 30, held={pygame.K_w})
    assert len(attacks) == 1 and (w.player.x, w.player.y) == spot
    assert w.combat and not w.combat.has("action")       # the bump started combat as your action


def test_holding_q_looks_around_for_free(app):
    w = _start(app)
    v, turn = app.fp, w.turn
    angle = v.angle
    for _ in range(5):                                   # 0.25 s
        app.update(0.05, held={pygame.K_q})
    assert v.angle != angle and w.turn == turn
    app.update(0.05, held=set())
    angle = v.angle
    app.handle_key(_key(pygame.K_e, "e"))                # a tap lands on the next 45 degree line
    assert v.angle % 45 == 0 and 0 < (v.angle - angle) % 360 <= 45 and w.turn == turn
    app.open_overlay("inventory")                        # held keys do nothing under a menu
    for _ in range(10):
        app.update(0.05, held={pygame.K_q, pygame.K_w})
    assert v.angle % 45 == 0 and w.turn == turn


def test_compass_and_minimap_arrow_follow_the_free_angle(app):
    w = _start(app)
    v = app.fp
    v.angle = 135
    app.draw(dt=1)
    assert v.compass() == "SE" and v.facing in (1, 2)
    r, s, (ox, oy) = v.minimap_rect, v.minimap_scale, v.minimap_origin
    cx, cy = r.x + (w.player.x - ox) * s + s // 2, r.y + (w.player.y - oy) * s + s // 2
    assert tuple(app.screen.get_at((cx + 2, cy + 2)))[:3] == (255, 255, 255)   # tip points SE
    assert tuple(app.screen.get_at((cx - 4, cy - 4)))[:3] != (255, 255, 255)


def test_looking_diagonally_down_a_corridor(app):
    w = _start(app)
    f = w.floor
    best = (0, None, None)
    for y in range(f.height):
        for x in range(f.width):
            if not _empty(w, x, y):
                continue
            for d in (1, 3, 5, 7):
                dx, dy = fpv.DIRS8[d]
                run, cx, cy = 0, x, y                    # open diagonal: no corner cutting
                while (run < 8 and f.walkable(cx + dx, cy + dy) and f.walkable(cx + dx, cy)
                       and f.walkable(cx, cy + dy)):
                    run, cx, cy = run + 1, cx + dx, cy + dy
                if run > best[0]:
                    best = (run, (x, y), d)
    run, spot, d = best
    assert run >= 3
    w.player.x, w.player.y = spot
    w.update_fov()
    app.fp.angle = d * 45
    _shot(app, "game_diagonal")


def test_strafing_into_a_monster_attacks_once(app):
    from crawler.entities import spawn_monster
    w = _start(app)
    w.monsters.clear()
    w.pet.downed = True
    spot, d = _corridor(w, 3)
    _place(app, spot, d)
    app.fp.angle = (d * 45 - 90) % 360                   # the corridor is on your right
    rx, ry = app.fp.relative("right")
    goblin = spawn_monster("goblin", spot[0] + rx, spot[1] + ry)
    goblin.hp = goblin.max_hp = 999
    w.monsters.append(goblin)
    attacks = _record(w, "player_attack")
    for _ in range(60):                                  # hold D for 2 s: one bump, no more
        app.update(1 / 30, held={pygame.K_d})
    assert len(attacks) == 1 and (w.player.x, w.player.y) == spot


def test_a_slow_frame_is_capped(app):
    from crawler.game import HOLD_DELAY, MAX_DT, TURN_RATE
    w = _start(app)
    v, angle = app.fp, app.fp.angle
    app.update(5.0, held={pygame.K_q})                   # a 5 s hitch: still a tap, no spin
    assert v.angle == angle and app._held_for[pygame.K_q] == MAX_DT < HOLD_DELAY
    for _ in range(5):
        app.update(5.0, held={pygame.K_q})
    assert 0 < (angle - v.angle) % 360 <= TURN_RATE * MAX_DT * 2 + 1e-6
    w.player.x += 1                                      # a glide moves a capped amount per frame
    app.update(5.0, held=set())
    assert 0 < app.fp.glide_left(w) < 1


def test_camera_lands_on_the_tile_under_a_menu(app):
    w = _start(app)
    w.monsters.clear()
    v = app.fp
    app.draw(dt=1)
    for _ in range(8):
        dx, dy = v.relative("forward")
        if _empty(w, w.player.x + dx, w.player.y + dy):
            break
        v.tap_turn(1)
    app.handle_key(_key(pygame.K_w, "w"))
    app.update(1 / 30, held=set())
    assert 0 < v.glide_left(w) < 1
    app.open_overlay("inventory")                        # a menu opens mid-glide
    for _ in range(30):
        app.update(1 / 30, held={pygame.K_w})
    assert v.glide_left(w) == 0 and not app.animating()
    w.state = "dead"
    app.overlay = None
    w.player.x -= dx
    w.player.y -= dy
    for _ in range(30):
        app.update(1 / 30, held=set())
    assert v.glide_left(w) == 0


def test_after_walking_screenshot(app):
    w = _start(app)
    w.monsters.clear()
    w.pet.downed = True
    spot, d = _corridor(w, 3)
    _place(app, spot, d)
    for _ in range(40):
        app.update(1 / 30, held={pygame.K_w})
    app.update(1 / 30, held=set())
    assert w.turn == 3
    _shot(app, "game_after_walking")


def _combat(app, gap=2, key="goblin", boss=False):
    """A fight on: the player at the start of a 3-tile corridor, a sturdy, stunned monster
    `gap` tiles ahead (so it waits while we look), first-person facing it."""
    from crawler.bosses import spawn_boss
    from crawler.entities import spawn_monster
    w = _start(app)
    w.monsters.clear()
    w.pet.downed = True
    w.player.max_hp = w.player.hp = 999
    spot, d = _corridor(w, 3, dirs=(0, 2, 4, 6))       # straight, so the grid lock keeps it
    _place(app, spot, d)
    dx, dy = fpv.DIRS8[d]
    x, y = spot[0] + gap * dx, spot[1] + gap * dy
    m = spawn_boss(w.depth, x, y) if boss else spawn_monster(key, x, y)
    m.hp = m.max_hp = 999
    w.monsters.append(m)
    w.update_fov()
    assert w.join_combat(m)
    w.combat.round = 1
    m.stunned = 99
    app.fp.angle = d * 45
    return w, m, (dx, dy)


def test_combat_tracker_and_screens_in_both_views(app):
    w, goblin, (dx, dy) = _combat(app)
    assert any(t[1] == "COMBAT: roll for initiative" for t in w.toasts)
    _shot(app, "combat_start")
    assert w.move_player(dx, dy) and not w.combat.has("move")
    _shot(app, "combat_mid")                             # tracker: move spent
    assert w.wait() and w.combat.round == 2              # Space ends your turn
    assert w.move_player(dx, dy)                         # a real attack: the action is spent
    assert not w.combat.has("action") and w.combat.has("move")
    _shot(app, "combat_attacked")
    w.inventory.append("tonic")                          # a potion to drink as the bonus action
    app.open_overlay("inventory")
    _shot(app, "inventory_combat")
    box = app.renderer.last_tracker                      # the pips show over the inventory
    assert box is not None and box.right < menus.X0 and w.combat.has("bonus")
    app.overlay = None
    app.show_help = True
    _shot(app, "help_combat")
    app.show_help = False
    w.player.attack, goblin.hp = 100, 1
    w.wait()
    assert w.move_player(dx, dy) and w.combat is None
    _shot(app, "combat_end")


def test_combat_with_a_boss_draws(app):
    w, boss, _ = _combat(app, boss=True)
    assert boss in w.combat
    _shot(app, "combat_boss")


@pytest.mark.parametrize("view", VIEWS)
def test_tracker_draws_with_none_one_and_many_fighters(app, view):
    from crawler.encounter import Encounter
    from crawler.entities import spawn_monster
    from crawler.ui.hud import MAP_RECT
    w = _start(app)
    app.view = view
    w.combat = enc = Encounter(w.player)
    enc.add(w.player, 10, 1)
    surf = app.screen
    sizes = []
    for n in (0, 1, 12):
        while len(enc.monsters) < n:
            enc.add(spawn_monster("goblin", 0, 0), len(enc.monsters), 0)
        app.draw(dt=1)
        box = app.renderer.draw_tracker(surf, w, MAP_RECT)
        sizes.append(box.height)
        assert box.right < MAP_RECT.centerx - 210        # clear of the toasts and ahead label
        assert box.bottom < MAP_RECT.centery - 60        # clear of the side chevrons
        if view == "fp":
            assert not box.colliderect(app.fp.minimap_rect)
    assert sizes[0] < sizes[1] < sizes[2]


def test_fp_combat_is_grid_locked(app):
    w, goblin, (dx, dy) = _combat(app, gap=3)
    app.update(1 / 30, held=set())
    assert app.fp.grid and app.fp.angle % 90 == 0
    start = (w.player.x, w.player.y)
    app.handle_key(_key(pygame.K_w, "w"))
    for _ in range(60):                                  # holding W: no more steps (move spent)
        app.update(1 / 30, held={pygame.K_w})
    assert (w.player.x, w.player.y) == (start[0] + dx, start[1] + dy)
    app.handle_key(_key(pygame.K_w, "w"))                # a second step is refused
    assert (w.player.x, w.player.y) == (start[0] + dx, start[1] + dy)
    angle = app.fp.angle
    app.handle_key(_key(pygame.K_q, "q"))                # a quarter turn, for free
    assert app.fp.angle == (angle - 90) % 360
    for _ in range(20):                                  # holding Q: no free look
        app.update(1 / 30, held={pygame.K_q})
    assert app.fp.angle == (angle - 90) % 360
    app.handle_key(_key(pygame.K_TAB))                   # Tab mid-combat keeps the lock
    app.handle_key(_key(pygame.K_TAB))
    app.update(1 / 30, held=set())
    assert app.view == "fp" and app.fp.grid
    w.combat = None                                      # the fight ends: free look again
    app.update(1 / 30, held=set())
    assert not app.fp.grid


def test_held_walk_stops_when_a_fight_starts(app):
    from crawler.entities import spawn_monster
    w = _start(app)
    w.monsters.clear()
    w.pet.downed = True
    spot, d = _corridor(w, 3)
    _place(app, spot, d)
    dx, dy = fpv.DIRS8[d]
    goblin = spawn_monster("goblin", spot[0] + 3 * dx, spot[1] + 3 * dy)
    goblin.hp = goblin.max_hp = 999
    w.monsters.append(goblin)
    for _ in range(90):                                  # hold W: it sees you within a step
        app.update(1 / 30, held={pygame.K_w})
        if w.combat:
            break
    assert w.combat and app.fp.grid
    for _ in range(60):
        app.update(1 / 30, held={pygame.K_w})
    assert w.combat is None or w.combat.has("move")      # the held key didn't spend your move


def test_help_has_a_combat_section_in_both_views(app):
    for view in VIEWS:
        rows = dict(screens.controls(view))
        assert "Combat turn" in rows and "Bonus action" in rows
        assert "end your turn" in rows[". / Space / numpad 5"]
    assert "In combat" in dict(screens.controls("fp"))


def test_boxes_over_the_map_never_hide_you_in_a_top_left_corner(app):
    """Tracker and toasts move off the top-left / top when they'd cover you or a fighter."""
    from crawler.entities import spawn_monster
    w = _start(app)
    app.view = "top"
    w.monsters.clear()
    f = w.floor
    spot = min(((x, y) for y in range(f.height) for x in range(f.width)
                if _empty(w, x, y) and not f.safe[y][x]
                and any(_empty(w, x + dx, y + dy) for dx, dy in fpv.DIRS8)),
               key=lambda s: s[0] + s[1])
    w.player.x, w.player.y = spot
    w.update_fov()
    for n, (dx, dy) in enumerate(fpv.DIRS8):
        if _empty(w, spot[0] + dx, spot[1] + dy) and n < 3:
            m = spawn_monster("goblin", spot[0] + dx, spot[1] + dy)
            m.stunned = 99
            w.monsters.append(m)
            w.join_combat(m)
    w.add_toast("Achievement: Test", "gold", "Bronze box. Open it in a safe room.")
    app.draw(dt=1)
    r = app.renderer
    actors = r.actor_rects(w)
    assert actors[0].topleft[0] < 18 * C.TILE and actors[0].topleft[1] < 15 * C.TILE
    assert r.last_tracker.collidelist(actors) == -1
    assert r.last_toasts and all(t.collidelist(actors) == -1 for t in r.last_toasts)
    _shot(app, "combat_corner")


def test_long_boss_names_fit_the_tracker_cleanly(app):
    r = app.renderer
    room = r.small.size(" 12 Grease Trap King")[0] - 4
    text = r.fit_name(" 12 ", "The Grease Trap King", room)
    assert text == " 12 Grease Trap..." and r.small.size(text)[0] <= room
    assert r.fit_name(" 3 ", "Goblin", 200) == " 3 Goblin"


def _behind_spot(w):
    """A straight-facing spot with an open tile ahead and an open tile behind it."""
    f = w.floor
    for y in range(f.height):
        for x in range(f.width):
            if not _empty(w, x, y) or f.safe[y][x]:
                continue
            for d in (0, 2, 4, 6):
                dx, dy = fpv.DIRS8[d]
                if _empty(w, x + dx, y + dy) and _empty(w, x - dx, y - dy) \
                        and not f.safe[y - dy][x - dx]:
                    return (x, y), d
    raise AssertionError("no spot")


def test_a_step_that_would_provoke_is_flagged_in_both_views(app):
    from crawler.entities import spawn_monster
    w = _start(app)
    w.monsters.clear()
    w.pet.downed = True
    w.player.max_hp = w.player.hp = 999
    spot, d = _behind_spot(w)
    _place(app, spot, d)
    app.fp.angle = d * 45
    dx, dy = fpv.DIRS8[d]
    g = spawn_monster("goblin", spot[0] - dx, spot[1] - dy)    # right behind you
    g.hp = g.max_hp = 999
    w.monsters.append(g)
    assert w.join_combat(g)
    app.update(1 / 30, held=set())
    assert w.threats() == [g] and app.fp.provoking(w) == [g]
    app.view = "fp"
    app.draw(dt=1)
    assert app.fp.ahead_text.startswith("W provokes the Knockoff Goblin")
    assert app.renderer.last_toasts                      # the COMBAT banner is up...
    assert app.fp.ahead_rect.collidelist(app.renderer.last_toasts) == -1   # ...and clear of it
    _shot(app, "aoo_warning")                            # orange label / brackets
    log = len(w.messages.lines)
    app.handle_key(_key(pygame.K_w, "w"))
    assert (w.player.x, w.player.y) == (spot[0] + dx, spot[1] + dy) or w.state != "playing"
    assert any("Attack of opportunity" in t for t, _ in list(w.messages.lines)[log:])
    _shot(app, "aoo_log")


SWEEP = ("title", "identity", "backstory", "pet_select", "game", "game_revealed", "help",
         "inventory", "safe_room", "safe", "box", "reveal", "shop_buy", "shop_sell", "craft",
         "skills", "attributes", "contract", "class_race", "class_class", "shop_remote",
         "combat_start", "combat_mid", "aoo_warning", "aoo_log", "inventory_combat",
         "help_combat", "report", "death", "victory")


def test_screenshot_sweep_of_every_screen_in_both_views(app):
    """Phase 7 sweep: every scene and overlay, including combat and attacks of opportunity,
    in both views. With CRAWL_SCREENSHOTS set it checks a PNG landed for each one."""
    import math
    import time
    from crawler.entities import spawn_monster
    done, started = [], time.time() - 1

    def shot(name):
        _shot(app, "sweep_" + name)
        done.append(name)

    shot("title")
    for name in ("identity", "backstory", "pet_select"):
        app.handle_key(_key(pygame.K_RETURN))
        assert app.scene == name
        shot(name)
    app.handle_key(_key(pygame.K_RETURN))
    w = app.world
    shot("game")
    explored = [row[:] for row in w.floor.explored]
    for row in w.floor.explored:
        row[:] = [True] * len(row)
    shot("game_revealed")
    w.floor.explored[:] = explored
    app.show_help = True
    shot("help")
    app.show_help = False
    w.inventory = ["pan", "tonic", "popper", "sock", "elixir"]
    app.open_overlay("inventory")
    shot("inventory")

    app.overlay = None
    w.player.x, w.player.y = w.floor.safe_room.centre
    w.update_fov()
    fx, fy = min(w.floor.furniture, key=lambda t: (t[0] - w.player.x) ** 2 + (t[1] - w.player.y) ** 2)
    app.fp.angle = math.degrees(math.atan2(fx - w.player.x, w.player.y - fy)) % 360
    app.fp.reset_camera()
    shot("safe_room")                                              # inside, facing the furniture
    w.gold = 300
    app.open_overlay("safe")
    shot("safe")
    w.add_box("bronze", "A sweep test.")
    app.overlay, app.box_tier = "box", "bronze"
    shot("box")
    assert w.open_box("bronze")
    app.overlay = "reveal"
    shot("reveal")
    app.overlay, app.cursor, app.shop_mode = "shop", 0, "buy"
    shot("shop_buy")
    app.shop_mode = "sell"
    shot("shop_sell")
    for name in ("craft", "skills", "attributes"):
        app.open_overlay(name)
        shot(name)
    w.pending_offer = "hazard_pay"
    app.open_overlay("contract")
    shot("contract")
    w.pending_offer = None
    app.open_overlay("class")
    app.class_step, app.class_race = "race", None
    shot("class_race")
    app.class_step, app.class_race = "class", "human"
    shot("class_class")
    app.overlay = None

    w.monsters.clear()
    w.pet.downed = True
    w.player.max_hp = w.player.hp = 999
    spot, d = _corridor(w, 3, dirs=(0, 2, 4, 6))
    _place(app, spot, d)
    app.fp.angle = d * 45
    w.remote_shop = True
    app.overlay, app.cursor, app.shop_mode = "shop", 0, "buy"
    shot("shop_remote")
    w.remote_shop, app.overlay = False, None
    dx, dy = fpv.DIRS8[d]
    g = spawn_monster("goblin", spot[0] + 3 * dx, spot[1] + 3 * dy)   # down the corridor
    g.hp = g.max_hp = 999
    w.monsters.append(g)
    assert w.join_combat(g)
    w.combat.round = 1
    g.stunned = 99                                                 # it waits for the pictures
    app.update(1 / 30, held=set())
    shot("combat_start")
    assert w.move_player(dx, dy) and not w.combat.has("move")
    shot("combat_mid")                                             # one step taken, move spent
    w.wait()                                                       # next round
    g.x, g.y, g.stunned = w.player.x - dx, w.player.y - dy, 0      # now right behind you
    w.update_fov()
    assert w.threats() == [g] and app.fp.provoking(w) == [g]
    shot("aoo_warning")
    log = len(w.messages.lines)
    app.handle_key(_key(pygame.K_w, "w"))                          # step away: it swings
    assert any("Attack of opportunity" in t for t, _ in list(w.messages.lines)[log:])
    shot("aoo_log")
    app.open_overlay("inventory")
    shot("inventory_combat")
    app.overlay, app.show_help = None, True
    shot("help_combat")
    app.show_help = False

    w.state, w.death_cause = "dead", "Killed by a screenshot sweep on floor 1"
    app.open_overlay("report")
    shot("report")
    app.overlay = None
    shot("death")
    w.state = "victory"
    shot("victory")

    assert tuple(done) == SWEEP
    out = os.environ.get("CRAWL_SCREENSHOTS")
    if out:
        pngs = [f for f in os.listdir(out) if f.startswith("sweep_") and f.endswith(".png")
                and os.path.getmtime(os.path.join(out, f)) >= started]    # this run's only
        assert len(pngs) == 2 * len(SWEEP)
        assert {f"sweep_{n}_{v}.png" for n in SWEEP for v in VIEWS} <= set(pngs)

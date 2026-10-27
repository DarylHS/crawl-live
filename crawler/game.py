"""pygame front end: scene state machine, input mapping and the main loop.

Rendering happens after input, since the game is turn-based, and on every frame
while the first-person camera is still gliding into place or a key is held. In the
first-person view, held keys (free look and walking) run in update(dt), which reads
the injectable set App.held so headless tests can hold keys. In combat the view is
locked to the grid: no free look or held walking, one step or 90 degree turn per key.
"""
import pygame

from . import config as C
from . import save, settings
from .attributes import ATTRS
from .character import BACKSTORIES, GENDERS
from .crafting import RECIPES
from .telemetry import RUNS_DIR, Telemetry, write_tables
from .entities import PETS
from .ui import menus, screens
from .ui.firstperson import FirstPersonView
from .ui.hud import MAP_RECT, Renderer
from .ui.report import draw_report
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
# First-person view: steps relative to where you look, and free turns.
# Keys not listed here (numpad) keep their absolute MOVES meaning.
FP_STEPS = {
    pygame.K_w: "forward", pygame.K_UP: "forward", pygame.K_s: "back", pygame.K_DOWN: "back",
    pygame.K_a: "left", pygame.K_d: "right",
}
FP_TURNS = {pygame.K_q: -1, pygame.K_LEFT: -1, pygame.K_e: 1, pygame.K_RIGHT: 1}
TURN_RATE = 180             # degrees a second while a turn key is held
HOLD_DELAY = 0.2            # seconds a turn key must be held before free look starts (a tap = 45)
NEXT_STEP = 0.15            # tiles of glide left when a held walk key issues the next step
STEP_GAP = 0.2              # seconds between held steps at least (about 4 tiles a second)
MAX_DT = 0.05               # a slow frame (new floor, save, window drag) counts as this at most


class App:
    def __init__(self, screen=None, seed=None, save_path=save.SAVE_FILE, runs_dir=RUNS_DIR,
                 settings_path=settings.SETTINGS_FILE):
        if not pygame.get_init():
            pygame.init()
        self.screen = screen or pygame.display.set_mode((C.SCREEN_W, C.SCREEN_H))
        pygame.display.set_caption("Crawl Live!")
        self.renderer = Renderer()
        self.seed = seed
        self.save_path = save_path
        self.runs_dir = runs_dir          # None turns off logging your runs
        self.telemetry = None
        self.settings_path = settings_path  # None turns off remembering settings
        self.settings = settings.load(settings_path)
        self.view = self.settings["view"]   # "fp" (first-person) | "top" (map)
        self.fp = FirstPersonView()
        self.scene = "title"        # "title" | "identity" | "backstory" | "pet_select" | "game"
        self.world: World | None = None
        self.show_help = False
        self.overlay = None         # None | "inventory" | "safe" | "reveal" | "craft" | "class"
        self.cursor = 0
        self.pet_idx, self.pet_name = 0, ""
        self.hero_name, self.gender_idx, self.backstory_idx = "", 0, 0
        self.class_step, self.class_race = "race", None
        self.box_tier, self.shop_mode = None, "buy"
        self.held = set()           # keys held down right now (run() fills it; tests set it)
        self._held_for = {}         # key -> seconds it has been held
        self._walk_wait = 0.0       # seconds until a held walk key may step again
        self._walk_stopped = set()  # walk keys that bumped a wall or attacked: wait for release
        self.running = True

    def start_run(self, pet=None):
        hero = dict(name=self.hero_name.strip() or "Crawler", gender=list(GENDERS)[self.gender_idx],
                    backstory=list(BACKSTORIES)[self.backstory_idx])
        self.world = World(self.seed, pet=pet, hero=hero)
        self._attach_telemetry()
        self.fp.reset(self.world)
        self.seed = None            # only the first run uses a fixed seed
        self.scene = "game"
        self.show_help = False
        self.overlay = None

    def load_run(self):
        try:
            self.world = save.load(self.save_path)
        except (OSError, ValueError, KeyError) as exc:
            print(f"Could not load save: {exc}")
            return
        self.scene, self.overlay, self.show_help = "game", None, False
        self._attach_telemetry()
        self.fp.reset(self.world)

    def _attach_telemetry(self):
        self.telemetry = Telemetry(self.world, source="player") if self.runs_dir else None

    def _log_run_if_over(self):
        """Write your finished run to runs/player_*.csv once, for the analysis notebooks."""
        tel = self.telemetry
        if tel and self.world.state != "playing":
            try:
                write_tables(tel.tables(), self.runs_dir, prefix="player_")
            except OSError as exc:
                print(f"Could not log run: {exc}")
            self.telemetry = None

    def toggle_view(self):
        """Tab: swap first-person and map, and remember the choice for next time."""
        self.view = "top" if self.view == "fp" else "fp"
        self.fp.reset_camera()              # snap, no stale hurt flash: you may have moved or been hit
        self.settings["view"] = self.view
        try:
            settings.save(self.settings, self.settings_path)
        except OSError as exc:
            print(f"Could not save settings: {exc}")

    def move_first_person(self, key):
        """W attacks what target_ahead picks (ahead, else 45 degrees either side); a tapped
        turn key turns 45 degrees, for free. Returns (moved, attacked)."""
        world, view = self.world, self.fp
        if key in FP_TURNS:
            if view.grid:
                view.turn(FP_TURNS[key])        # combat: a quarter turn per press
            else:
                view.tap_turn(FP_TURNS[key])
            return False, False
        move = FP_STEPS[key]
        target, step = view.target_ahead(world) if move == "forward" else (None, None)
        if not target:                      # any step (back, strafe) into a monster is a bump
            step = view.relative(move)
            target = world.monster_at(world.player.x + step[0], world.player.y + step[1])
        ok = world.move_player(*step)
        self._walk_wait = STEP_GAP
        return ok, bool(target)

    def sync_combat(self):
        """Lock the first-person view to the grid when a fight starts (and stop any held walk,
        so it can't spend your combat move before you've seen the tracker); free it after."""
        world = self.world
        fight = world is not None and world.combat is not None and world.state == "playing"
        if fight and not self.fp.grid:
            self.fp.set_combat(True)
            self._walk_stopped |= {k for k in self.held if k in FP_STEPS}
        elif not fight and self.fp.grid:
            self.fp.set_combat(False)

    def _fp_input_live(self):
        return (self.scene == "game" and self.view == "fp" and not self.overlay
                and not self.show_help and self.world is not None and self.world.state == "playing")

    def update(self, dt, held=None):
        """Per-frame work between key presses: free look and walking while keys are held in
        the first-person view, then the camera glide. dt is seconds; held overrides self.held.
        Returns True when something changed that needs a redraw."""
        dt = min(dt, MAX_DT)
        if held is not None:
            self.held = set(held)
        for k in list(self._held_for):
            if k not in self.held:
                del self._held_for[k]
        self._walk_stopped &= self.held
        self._walk_wait = max(0.0, self._walk_wait - dt)
        view, world = self.fp, self.world
        self.sync_combat()
        if not self._fp_input_live():
            self._held_for.clear()
            if self.scene == "game" and self.view == "fp" and world is not None:
                view.update_camera(world, dt)   # a menu or death mid-glide still lands on the tile
                return self.animating()
            return False
        if view.grid:                       # combat: keys act on press only (handle_key)
            view.update_camera(world, dt)
            return self.animating()
        changed = False
        for k in self.held:
            self._held_for[k] = self._held_for.get(k, 0.0) + dt
        spin = sum(FP_TURNS[k] for k in self.held if k in FP_TURNS
                   and self._held_for[k] > HOLD_DELAY)
        if spin:
            view.look(max(-1, min(1, spin)) * TURN_RATE * dt)
            changed = True
        walk = [k for k in self.held if k in FP_STEPS and k not in self._walk_stopped]
        view.update_camera(world, dt)
        if walk and self._walk_wait <= 0 and view.glide_left(world) < NEXT_STEP:
            key = min(walk, key=lambda k: self._held_for.get(k, 0.0))   # the latest pressed
            moved, attacked = self.move_first_person(key)
            if not moved or attacked:
                self._walk_stopped.add(key)     # a wall or a fight: stop until you let go
            self._after_action()
            changed = True
        return changed or self.animating()

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
                self.scene = "identity"
            elif key == pygame.K_l and save.has_save(self.save_path):
                self.load_run()
            elif key == pygame.K_ESCAPE:
                self.running = False
            return
        if self.scene == "identity":
            self.handle_identity_key(key, ch)
            return
        if self.scene == "backstory":
            n = len(BACKSTORIES)
            if key == pygame.K_ESCAPE:
                self.scene = "identity"
            elif key in (pygame.K_UP, pygame.K_w):
                self.backstory_idx = (self.backstory_idx - 1) % n
            elif key in (pygame.K_DOWN, pygame.K_s):
                self.backstory_idx = (self.backstory_idx + 1) % n
            elif key in DESCEND_KEYS:
                self.scene, self.pet_name = "pet_select", ""
            return
        if self.scene == "pet_select":
            self.handle_pet_select_key(key, ch)
            return

        world = self.world
        if self.overlay:
            self.handle_overlay_key(key)
        elif key == pygame.K_ESCAPE:
            self.scene = "title"
        elif world.state != "playing":
            if key in DESCEND_KEYS:
                self.scene = "identity"             # same character, ready to tweak
            elif key == pygame.K_r:
                self.open_overlay("report")
        elif key == pygame.K_TAB:
            self.toggle_view()
        elif ch == ">" or key in DESCEND_KEYS:
            world.descend()
        elif self.view == "fp" and (key in FP_STEPS or key in FP_TURNS):
            moved, attacked = self.move_first_person(key)
            self._walk_stopped.discard(key)
            if not moved or attacked:
                self._walk_stopped.add(key)         # holding on doesn't keep bumping or attacking
        elif key in MOVES:
            world.move_player(*MOVES[key])
        elif key in WAIT_KEYS:
            world.wait()
        elif key == pygame.K_r:
            world.rest()
        elif key == pygame.K_g:
            world.pickup()
        elif key == pygame.K_i:
            self.open_overlay("inventory")
        elif key == pygame.K_m:
            if world.in_safe_room:
                self.open_overlay("safe")
            else:
                world.messages.add("The menu is only available in a safe room.", C.TEXT_DIM)
        elif key == pygame.K_c:
            world.command_pet()
        elif key == pygame.K_k:
            self.open_overlay("skills")
        elif key == pygame.K_l:
            self.open_overlay("attributes")
        elif key == pygame.K_1:
            if world.use_skill() and world.remote_shop:
                self.overlay, self.cursor, self.shop_mode = "shop", 0, "buy"
        self._after_action()

    def _after_action(self):
        """After any key or held step in the game: log a finished run, face a new floor's open
        side, and open the class picker or a sponsor offer if one is waiting."""
        world = self.world
        self._log_run_if_over()
        self.fp.follow_floor(world)         # a new floor: face its most open direction
        self.sync_combat()
        if world.state == "playing" and not self.overlay:
            if world.pending_choice:
                self.open_overlay("class")
                self.class_step, self.class_race = "race", None
            elif world.pending_offer:
                self.open_overlay("contract")

    def handle_identity_key(self, key, ch):
        if key == pygame.K_ESCAPE:
            self.scene = "title"
        elif key in (pygame.K_LEFT, pygame.K_RIGHT, pygame.K_TAB):
            step = -1 if key == pygame.K_LEFT else 1
            self.gender_idx = (self.gender_idx + step) % len(GENDERS)
        elif key in DESCEND_KEYS:
            self.scene = "backstory"
        elif key == pygame.K_BACKSPACE:
            self.hero_name = self.hero_name[:-1]
        elif ch and (ch.isalnum() or ch in " -'") and len(self.hero_name) < 16:
            self.hero_name += ch

    def handle_pet_select_key(self, key, ch):
        species = list(PETS)
        if key == pygame.K_ESCAPE:
            self.scene = "backstory"
        elif key in (pygame.K_LEFT, pygame.K_RIGHT, pygame.K_TAB):
            step = -1 if key == pygame.K_LEFT else 1
            self.pet_idx = (self.pet_idx + step) % len(species)
        elif key in DESCEND_KEYS:
            self.start_run((species[self.pet_idx], self.pet_name.strip()))
        elif key == pygame.K_BACKSPACE:
            self.pet_name = self.pet_name[:-1]
        elif ch and (ch.isalnum() or ch in " -'") and len(self.pet_name) < 16:
            self.pet_name += ch

    def open_overlay(self, name):
        self.overlay, self.cursor = name, 0

    def handle_overlay_key(self, key):
        world = self.world
        if self.overlay == "attributes":
            keys = list(ATTRS)
            if key in (pygame.K_ESCAPE, pygame.K_l):
                self.overlay = None
            elif key in (pygame.K_UP, pygame.K_w):
                self.cursor = (self.cursor - 1) % len(keys)
            elif key in (pygame.K_DOWN, pygame.K_s):
                self.cursor = (self.cursor + 1) % len(keys)
            elif key in DESCEND_KEYS or key in (pygame.K_RIGHT, pygame.K_d):
                world.spend_point(keys[self.cursor])
            return
        if self.overlay in ("report", "skills"):
            if key in DESCEND_KEYS or key in (pygame.K_ESCAPE, pygame.K_k):
                self.overlay = None
            return
        if self.overlay == "contract":
            if key in (pygame.K_y, *DESCEND_KEYS):
                world.accept_contract()
            elif key in (pygame.K_n, pygame.K_ESCAPE):
                world.decline_contract()
            else:
                return
            self.overlay = None
            if world.pending_choice:
                self.open_overlay("class")
            return
        if self.overlay == "reveal":
            if key == pygame.K_r:
                world.reroll()
            elif key in DESCEND_KEYS or key == pygame.K_ESCAPE:
                self.overlay = "safe" if world.in_safe_room else None
            return
        if self.overlay == "box":
            if key == pygame.K_ESCAPE:
                self.overlay, self.cursor = "safe", 0
            elif key == pygame.K_t:
                world.trade_up(self.box_tier)
                if self.box_tier not in world.boxes:
                    self.overlay, self.cursor = "safe", 0
            elif key in DESCEND_KEYS and world.open_box(self.box_tier):
                self.overlay = "reveal"
            return
        if self.overlay == "shop":
            rows = menus.shop_rows(world, self.shop_mode)
            remote = not world.in_safe_room
            if key == pygame.K_ESCAPE:
                self.overlay, self.cursor = (None if remote else "safe"), 0
                world.remote_shop = False          # closing a Supply Drop ends it
            elif key == pygame.K_TAB and not remote:
                self.shop_mode = "sell" if self.shop_mode == "buy" else "buy"
                self.cursor = 0
            elif key in (pygame.K_UP, pygame.K_w) and rows:
                self.cursor = (self.cursor - 1) % len(rows)
            elif key in (pygame.K_DOWN, pygame.K_s) and rows:
                self.cursor = (self.cursor + 1) % len(rows)
            elif key in DESCEND_KEYS and rows:
                if self.shop_mode == "buy":
                    world.shop_buy(rows[self.cursor])
                    if remote and not world.remote_shop:
                        self.overlay = None
                else:
                    world.shop_sell(rows[self.cursor])
                    self.cursor = min(self.cursor, max(0, len(world.inventory) - 1))
            return
        if self.overlay == "class":
            self.handle_class_key(key)
            return
        if self.overlay == "craft":
            if key == pygame.K_ESCAPE:
                self.overlay, self.cursor = "safe", 0
            elif key in (pygame.K_UP, pygame.K_w):
                self.cursor = (self.cursor - 1) % len(RECIPES)
            elif key in (pygame.K_DOWN, pygame.K_s):
                self.cursor = (self.cursor + 1) % len(RECIPES)
            elif key in DESCEND_KEYS:
                world.craft(self.cursor)
            if world.state != "playing":
                self.overlay = None
            return
        if key in (pygame.K_ESCAPE, pygame.K_i, pygame.K_m):
            self.overlay = None
            return
        rows = (menus.inventory_rows(world) if self.overlay == "inventory"
                else menus.menu_options(world))
        if key in (pygame.K_UP, pygame.K_w) and rows:
            self.cursor = (self.cursor - 1) % len(rows)
        elif key in (pygame.K_DOWN, pygame.K_s) and rows:
            self.cursor = (self.cursor + 1) % len(rows)
        elif not rows or world.state != "playing":
            return
        elif self.overlay == "inventory":
            where, ref, _ = rows[self.cursor]
            if key in DESCEND_KEYS and where == "pack":
                world.use_item(ref)
            elif key == pygame.K_u and where == "equip":
                world.unequip(ref)
            elif key == pygame.K_d and where == "pack":
                world.drop(ref)
            self.cursor = min(self.cursor, max(0, len(menus.inventory_rows(world)) - 1))
        elif key in DESCEND_KEYS:
            action, tier, _ = rows[self.cursor]
            if action == "rest":
                world.rest()
                self.overlay = None
            elif action == "revive":
                world.revive_pet()
            elif action == "craft":
                self.overlay, self.cursor = "craft", 0
                return
            elif action == "box":
                self.overlay, self.box_tier = "box", tier
                return
            elif action == "shop":
                self.overlay, self.cursor, self.shop_mode = "shop", 0, "buy"
                return
            elif action == "save":
                save.save(world, self.save_path)
                self.scene, self.overlay = "title", None
                return
            self.cursor = min(self.cursor, len(menus.menu_options(world)) - 1)
        if world.state != "playing":
            self.overlay = None

    def handle_class_key(self, key):
        rows = menus.class_rows(self.class_step)
        if key in (pygame.K_UP, pygame.K_w):
            self.cursor = (self.cursor - 1) % len(rows)
        elif key in (pygame.K_DOWN, pygame.K_s):
            self.cursor = (self.cursor + 1) % len(rows)
        elif key in DESCEND_KEYS:
            if self.class_step == "race":
                self.class_race, self.class_step, self.cursor = rows[self.cursor], "class", 0
            else:
                self.world.choose_class(self.class_race, rows[self.cursor])
                self.overlay = None

    # --- Drawing -------------------------------------------------------

    def animating(self):
        """True while the first-person camera still needs frames to settle."""
        return self.scene == "game" and self.view == "fp" and self.fp.animating(self.world)

    def draw(self, dt=1.0):
        """Draw the current scene. dt is seconds of camera glide; 1 snaps (tests), and the main
        loop passes 0 since update(dt) has already moved the camera."""
        r, s = self.renderer, self.screen
        if self.scene == "title":
            screens.draw_title(r, s, save.has_save(self.save_path))
        elif self.scene == "identity":
            menus.draw_identity(r, s, self.hero_name, self.gender_idx)
        elif self.scene == "backstory":
            menus.draw_backstory(r, s, self.backstory_idx)
        elif self.scene == "pet_select":
            menus.draw_pet_select(r, s, self.pet_idx, self.pet_name)
        else:
            self.sync_combat()
            covered = bool(self.overlay or self.show_help or self.world.state != "playing")
            r.draw_game(s, self.world, self.fp if self.view == "fp" else None, dt, hud=not covered)
            if self.world.state == "dead":
                screens.draw_death(r, s, self.world)
            elif self.world.state == "victory":
                screens.draw_victory(r, s, self.world)
            if self.overlay == "inventory":
                menus.draw_inventory(r, s, self.world, self.cursor)
                if self.world.combat is not None:   # see the Bonus pip while picking a potion
                    r.draw_tracker(s, self.world, MAP_RECT)
            elif self.overlay == "safe":
                menus.draw_safe_menu(r, s, self.world, self.cursor)
            elif self.overlay == "reveal":
                menus.draw_reveal(r, s, self.world)
            elif self.overlay == "box":
                menus.draw_box_info(r, s, self.world, self.box_tier)
            elif self.overlay == "shop":
                menus.draw_shop(r, s, self.world, self.cursor, self.shop_mode)
            elif self.overlay == "contract":
                menus.draw_contract(r, s, self.world)
            elif self.overlay == "report":
                draw_report(r, s, self.world)
            elif self.overlay == "skills":
                menus.draw_practice(r, s, self.world)
            elif self.overlay == "attributes":
                menus.draw_attributes(r, s, self.world, self.cursor)
            elif self.overlay == "craft":
                menus.draw_craft(r, s, self.world, self.cursor)
            elif self.overlay == "class":
                menus.draw_class_select(r, s, self.world, self.class_step, self.class_race,
                                        self.cursor)
        if self.show_help:
            screens.draw_help(r, s, self.view)

    def run(self):
        clock = pygame.time.Clock()
        dirty = True
        watched = list(FP_STEPS) + list(FP_TURNS)
        while self.running:
            dt = min(clock.tick(C.FPS) / 1000, MAX_DT)
            for event in pygame.event.get():
                if event.type == pygame.QUIT:
                    self.running = False
                elif event.type == pygame.KEYDOWN:
                    self.handle_key(event)
                    dirty = True
                elif event.type in (pygame.WINDOWEXPOSED, pygame.VIDEOEXPOSE):
                    dirty = True
            pressed = pygame.key.get_pressed()
            self.held = {k for k in watched if pressed[k]}
            if self.update(dt) or dirty:
                self.draw(0)
                pygame.display.flip()
                dirty = False
        pygame.quit()


def main(seed=None):
    App(seed=seed).run()

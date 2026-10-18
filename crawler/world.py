"""The game world: all rules and state, with no pygame dependency.

Keeping this headless means tests and (later) the bot can play thousands of
turns without a window. Player actions return True when they used a turn.
"""
import random
from collections import deque

from . import config as C
from .ai import take_monster_turns
from .combat import attack
from .dungeon import STAIRS, compute_fov, generate_floor
from .entities import monster_table, new_player, spawn_monster
from .events import EventBus


class MessageLog:
    def __init__(self, maxlen=200):
        self.lines = deque(maxlen=maxlen)

    def add(self, text, colour=C.TEXT):
        self.lines.append((text, colour))

    def recent(self, n):
        return list(self.lines)[-n:]


class World:
    def __init__(self, seed=None):
        self.seed = seed if seed is not None else random.randrange(1 << 30)
        self.rng = random.Random(self.seed)
        self.events = EventBus()
        self.messages = MessageLog()
        self.player = new_player(0, 0)
        self.turn = 0
        self.state = "playing"          # "playing" | "dead" | "victory"
        self.death_cause = None
        self.depth = 0
        self.new_floor(1)

    # --- Floors --------------------------------------------------------

    def new_floor(self, depth):
        self.depth = depth
        self.floor = generate_floor(self.rng, depth)
        self.player.x, self.player.y = self.floor.start_room.centre
        self.timer_max = self.timer = C.floor_turns(depth)
        self._warnings_left = list(C.TIMER_WARNINGS)
        self.monsters = []
        self._spawn_monsters()
        self._was_safe = False
        self.update_fov()
        self.messages.add(f"Floor {depth}. It collapses in {self.timer_text()}. Find the stairs.",
                          C.ACCENT)
        self.events.emit("floor_start", depth=depth, turn=self.turn)

    def _spawn_monsters(self):
        keys, weights = monster_table(self.depth)
        floor = self.floor
        for room in floor.rooms:
            if room is floor.start_room or room is floor.safe_room:
                continue
            count = self.rng.randint(0, min(3, 1 + self.depth // 2))
            spots = [(x, y) for x, y in room.tiles() if floor.tiles[y][x] != STAIRS]
            for x, y in self.rng.sample(spots, min(count, len(spots))):
                self.monsters.append(spawn_monster(self.rng.choices(keys, weights)[0], x, y))

    def update_fov(self):
        self.visible = compute_fov(self.floor, self.player.x, self.player.y)
        explored = self.floor.explored
        for x, y in self.visible:
            explored[y][x] = True

    # --- Queries -------------------------------------------------------

    def monster_at(self, x, y):
        for m in self.monsters:
            if m.x == x and m.y == y:
                return m
        return None

    @property
    def in_safe_room(self):
        return self.floor.is_safe(self.player.x, self.player.y)

    @property
    def on_stairs(self):
        return self.floor.tiles[self.player.y][self.player.x] == STAIRS

    def timer_text(self, turns=None):
        t = self.timer if turns is None else turns
        return f"{t // 60}h {t % 60:02d}m"

    # --- Player actions ------------------------------------------------

    def move_player(self, dx, dy):
        if self.state != "playing":
            return False
        p = self.player
        tx, ty = p.x + dx, p.y + dy
        target = self.monster_at(tx, ty)
        if target:
            if self.in_safe_room:
                self.messages.add("The System forbids violence in safe rooms. Spoilsport.",
                                  C.TEXT_DIM)
                return False
            self._player_attack(target)
        elif self.floor.walkable(tx, ty):
            p.x, p.y = tx, ty
            self._on_enter_tile()
        else:
            return False
        self.end_turn()
        return True

    def wait(self):
        if self.state != "playing":
            return False
        self.end_turn()
        return True

    def descend(self):
        if self.state != "playing":
            return False
        if not self.on_stairs:
            self.messages.add("There are no stairs here.", C.TEXT_DIM)
            return False
        self.events.emit("descend", depth=self.depth, turn=self.turn,
                         timer_left=self.timer, timer_max=self.timer_max)
        if self.depth >= C.NUM_FLOORS:
            self.state = "victory"
            self.messages.add("You escaped the final floor!", C.GOOD)
            self.events.emit("victory", depth=self.depth, turn=self.turn)
        else:
            self.new_floor(self.depth + 1)
        return True

    def rest(self):
        """Heal to full in a safe room, spending floor time to do it."""
        if self.state != "playing":
            return False
        if not self.in_safe_room:
            self.messages.add("You can only rest in a safe room.", C.TEXT_DIM)
            return False
        p = self.player
        if p.hp >= p.max_hp:
            self.messages.add("You're already at full health.", C.TEXT_DIM)
            return False
        if self.timer <= C.REST_MIN_TIMER:
            self.messages.add("No time to rest. The floor is coming down!", C.DANGER)
            return False
        start_hp, start_turn = p.hp, self.turn
        while p.hp < p.max_hp and self.timer > C.REST_MIN_TIMER and self.state == "playing":
            p.heal(1)
            self._tick_clock()
        spent = self.turn - start_turn
        self.messages.add(f"You rest for {self.timer_text(spent)} and recover "
                          f"{p.hp - start_hp} HP.", C.GOOD)
        self.events.emit("rest", turns=spent, healed=p.hp - start_hp)
        self.update_fov()
        return True

    # --- Combat --------------------------------------------------------

    def _player_attack(self, target):
        p = self.player
        res = attack(p, target, self.rng)
        if not res.hit:
            self.messages.add(f"You miss the {target.name}.", C.TEXT_DIM)
            return
        crit = " Critical hit!" if res.crit else ""
        self.messages.add(f"You hit the {target.name} for {res.damage}.{crit}")
        self.events.emit("player_hit", target=target.key, damage=res.damage, crit=res.crit)
        if res.killed:
            self.monsters.remove(target)
            p.kills += 1
            self.messages.add(f"The {target.name} dies.", C.GOOD)
            self.events.emit("kill", monster=target.key, depth=self.depth, turn=self.turn,
                             player_hp=p.hp, player_max_hp=p.max_hp)
            for level in p.gain_xp(target.xp_value):
                self.messages.add(f"Level up! You are now level {level}.", C.ACCENT)
                self.events.emit("level_up", level=level)

    def monster_attack(self, monster):
        p = self.player
        res = attack(monster, p, self.rng)
        if not res.hit:
            self.messages.add(f"The {monster.name} misses you.", C.TEXT_DIM)
            return
        crit = " A brutal crit!" if res.crit else ""
        self.messages.add(f"The {monster.name} hits you for {res.damage}.{crit}", C.DANGER)
        self.events.emit("damage_taken", source=monster.key, damage=res.damage, hp=p.hp)
        if res.killed:
            self._kill_player(f"Killed by a {monster.name} on floor {self.depth}")

    def _kill_player(self, cause):
        self.state = "dead"
        self.death_cause = cause
        self.messages.add(cause + ".", C.DANGER)
        self.events.emit("player_death", cause=cause, depth=self.depth, turn=self.turn)

    # --- Turn flow -----------------------------------------------------

    def _on_enter_tile(self):
        safe = self.in_safe_room
        if safe and not self._was_safe:
            self.messages.add("Safe room. No combat allowed in here. Press R to rest.", C.GOOD)
        self._was_safe = safe
        if self.on_stairs:
            self.messages.add("A stairwell down. Press > or Enter to descend.", C.ACCENT)

    def _tick_clock(self):
        self.turn += 1
        self.timer -= 1
        p = self.player
        if self.turn % C.REGEN_INTERVAL == 0:
            p.heal(1)
        while self._warnings_left and self.timer <= self._warnings_left[0] * self.timer_max:
            self._warnings_left.pop(0)
            self.messages.add(f"WARNING: floor collapse in {self.timer_text()}.", C.DANGER)
            self.events.emit("timer_warning", timer_left=self.timer)
        if self.timer <= 0:
            self._kill_player(f"Crushed when floor {self.depth} collapsed")

    def end_turn(self):
        # FOV depends only on the player's position, so one update per turn
        # (before monsters act, since sight is what alerts them) is enough.
        self.update_fov()
        take_monster_turns(self)
        if self.state == "playing":
            self._tick_clock()

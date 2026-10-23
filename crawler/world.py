"""The game world: all rules and state, with no pygame dependency.

Keeping this headless means tests and (later) the bot can play thousands of
turns without a window. Player actions return True when they used a turn.
"""
import random
from collections import deque

from . import config as C
from .achievements import Achievements
from .ai import take_monster_turns
from .combat import attack
from .dungeon import STAIRS, compute_fov, generate_floor
from .entities import monster_table, new_player, spawn_monster
from .events import EventBus
from .items import ITEMS, STAT_BONUSES, floor_loot_table
from .loot import BOX_TIERS, roll_box
from .showrunner import Showrunner


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
        self.inventory = []             # item keys, unequipped
        self.equipment = {"weapon": None, "armour": None}
        self.boxes = []                 # unopened loot box tiers
        self.floor_items = {}           # (x, y) -> [item keys]
        self.loot_rng = random.Random(self.seed ^ 0x100F)
        self.last_reveal = None         # (tier, item key) of the latest box opened
        self.toasts = []                # (turn, text, tier)
        self.achievements = Achievements(self)
        self.showrunner = Showrunner(self)
        self.new_floor(1)

    @property
    def viewers(self):
        return self.showrunner.viewers

    # --- Floors --------------------------------------------------------

    def new_floor(self, depth):
        self.depth = depth
        self.floor = generate_floor(self.rng, depth)
        self.player.x, self.player.y = self.floor.start_room.centre
        self.timer_max = self.timer = C.floor_turns(depth)
        self._warnings_left = list(C.TIMER_WARNINGS)
        self.monsters = []
        self.floor_items = {}
        self._spawn_monsters()
        self._spawn_items()
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

    def _spawn_items(self):
        keys, weights = floor_loot_table(self.depth)
        floor = self.floor
        for room in floor.rooms:
            if room is floor.start_room or self.rng.random() >= C.FLOOR_ITEM_CHANCE:
                continue
            spots = [(x, y) for x, y in room.tiles() if floor.tiles[y][x] != STAIRS]
            self.floor_items.setdefault(self.rng.choice(spots), []).append(
                self.rng.choices(keys, weights)[0])

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

    # --- Items ---------------------------------------------------------

    def pickup(self):
        """Pick up everything on the player's tile that fits in the pack."""
        if self.state != "playing":
            return False
        here = self.floor_items.get((self.player.x, self.player.y))
        if not here:
            self.messages.add("Nothing here to pick up.", C.TEXT_DIM)
            return False
        took = False
        while here and len(self.inventory) < C.INVENTORY_SIZE:
            key = here.pop(0)
            self.inventory.append(key)
            took = True
            self.messages.add(f"You pick up the {ITEMS[key]['name']}.")
            self.events.emit("item_pickup", item=key)
        if not here:
            del self.floor_items[(self.player.x, self.player.y)]
        if not took:
            self.messages.add("Your pack is full.", C.DANGER)
            return False
        self.end_turn()
        return True

    def drop(self, index):
        if self.state != "playing" or not 0 <= index < len(self.inventory):
            return False
        key = self.inventory.pop(index)
        self.floor_items.setdefault((self.player.x, self.player.y), []).append(key)
        self.messages.add(f"You drop the {ITEMS[key]['name']}.", C.TEXT_DIM)
        self.events.emit("item_drop", item=key)
        return True

    def _apply_bonuses(self, key, sign):
        p = self.player
        for stat in STAT_BONUSES:
            setattr(p, stat, getattr(p, stat) + sign * ITEMS[key].get(stat, 0))

    def equip(self, index):
        """Wear or wield an inventory item; whatever was in the slot goes back to the pack."""
        if self.state != "playing" or not 0 <= index < len(self.inventory):
            return False
        key = self.inventory.pop(index)
        slot = ITEMS[key]["kind"]
        old = self.equipment[slot]
        if old:
            self._apply_bonuses(old, -1)
            self.inventory.append(old)
            self.events.emit("unequip", slot=slot, item=old)
        self.equipment[slot] = key
        self._apply_bonuses(key, +1)
        self.messages.add(f"You equip the {ITEMS[key]['name']}.", C.INFO)
        self.events.emit("equip", slot=slot, item=key)
        return True

    def unequip(self, slot):
        key = self.equipment.get(slot)
        if self.state != "playing" or not key or len(self.inventory) >= C.INVENTORY_SIZE:
            return False
        self._apply_bonuses(key, -1)
        self.equipment[slot] = None
        self.inventory.append(key)
        self.events.emit("unequip", slot=slot, item=key)
        return True

    def use_item(self, index):
        """Equip, drink or throw an item. Returns True if it took a turn."""
        if self.state != "playing" or not 0 <= index < len(self.inventory):
            return False
        key = self.inventory[index]
        item = ITEMS[key]
        kind = item["kind"]
        if kind in self.equipment:
            self.equip(index)
            return False
        if kind == "junk":
            self.messages.add(f"The {item['name']} is junk. Drop it.", C.TEXT_DIM)
            return False
        if kind == "potion":
            p = self.player
            if p.hp >= p.max_hp:
                self.messages.add("You're already at full health.", C.TEXT_DIM)
                return False
            self.inventory.pop(index)
            healed = p.heal(item["heal"])
            self.messages.add(f"You drink the {item['name']} and recover {healed} HP.", C.GOOD)
            self.events.emit("item_use", item=key, healed=healed)
        else:
            if not self._throw_bomb(index):
                return False
        self.end_turn()
        return True

    def _throw_bomb(self, index):
        p = self.player
        if self.in_safe_room:
            self.messages.add("The System forbids explosions in safe rooms.", C.TEXT_DIM)
            return False
        seen = [m for m in self.monsters if (m.x, m.y) in self.visible
                and max(abs(m.x - p.x), abs(m.y - p.y)) <= C.BOMB_RANGE]
        if not seen:
            self.messages.add("No target in range.", C.TEXT_DIM)
            return False
        key = self.inventory.pop(index)
        item = ITEMS[key]
        target = min(seen, key=lambda m: max(abs(m.x - p.x), abs(m.y - p.y)))
        self.messages.add(f"You throw the {item['name']}. BOOM.", C.ACCENT)
        killed = 0
        for m in list(self.monsters):
            if max(abs(m.x - target.x), abs(m.y - target.y)) <= item["radius"]:
                m.take_damage(item["damage"])
                m.alerted = True
                if not m.alive:
                    self._kill_monster(m, "bomb")
                    killed += 1
        self.events.emit("bomb", item=key, kills=killed)
        return True

    # --- Loot boxes ----------------------------------------------------

    def add_box(self, tier, source):
        self.boxes.append(tier)
        self.messages.add(f"You receive a {BOX_TIERS[tier]['name']} loot box ({source}). "
                          "Open it in a safe room.", BOX_TIERS[tier]["colour"])
        self.events.emit("box_gained", tier=tier, source=source)

    def open_box(self, tier):
        """Open one box of this tier. Safe rooms only; needs a free pack slot."""
        if self.state != "playing" or tier not in self.boxes:
            return False
        if not self.in_safe_room:
            self.messages.add("Loot boxes can only be opened in a safe room.", C.TEXT_DIM)
            return False
        if len(self.inventory) >= C.INVENTORY_SIZE:
            self.messages.add("Your pack is full. Drop something first.", C.DANGER)
            return False
        self.boxes.remove(tier)
        key = roll_box(tier, self.loot_rng)
        self.inventory.append(key)
        self.last_reveal = (tier, key)
        self.messages.add(f"The {BOX_TIERS[tier]['name']} box contains: {ITEMS[key]['name']}!",
                          BOX_TIERS[tier]["colour"])
        self.events.emit("box_opened", tier=tier, item=key)
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
            self._kill_monster(target, "melee")

    def _kill_monster(self, target, by):
        p = self.player
        self.monsters.remove(target)
        p.kills += 1
        self.messages.add(f"The {target.name} dies.", C.GOOD)
        self.events.emit("kill", monster=target.key, depth=self.depth, turn=self.turn, by=by,
                         player_hp=p.hp, player_max_hp=p.max_hp)
        if self.loot_rng.random() < C.ITEM_DROP_CHANCE:
            keys, weights = floor_loot_table(self.depth)
            self.floor_items.setdefault((target.x, target.y), []).append(
                self.loot_rng.choices(keys, weights)[0])
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
            self.messages.add("Safe room. No combat allowed in here. R rests, M opens the menu.", C.GOOD)
        self._was_safe = safe
        here = self.floor_items.get((self.player.x, self.player.y))
        if here:
            names = ", ".join(ITEMS[k]["name"] for k in here)
            self.messages.add(f"You see: {names}. Press G to pick up.", C.TEXT_DIM)
        if self.on_stairs:
            self.messages.add("A stairwell down. Press > or Enter to descend.", C.ACCENT)

    def _tick_clock(self):
        self.turn += 1
        self.timer -= 1
        self.events.emit("turn", turn=self.turn)
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

"""The game world: all rules and state, with no pygame dependency.

Keeping this headless means tests and (later) the bot can play thousands of
turns without a window. Player actions return True when they used a turn.
"""
import random
from collections import deque

from . import config as C
from .achievements import Achievements
from .ai import cheb, take_monster_turns, take_pet_turn
from .bosses import ACTS, BOSSES, MAP_RADIUS, PHASE_TWO, acts_per_floor, boss_depth, spawn_act, spawn_boss
from .character import BACKSTORIES, GENDERS
from .attributes import ATTRS, MAX_SCORE, mod, proficiency
from .classes import CHOICE_FLOOR, CLASSES, FLAT_BONUSES, RACES, SKILLS
from .combat import attack, hit_chance, saving_throw
from .contracts import CONTRACTS, OFFER_CHANCE, OFFER_FROM_FLOOR, effect
from .crafting import CRAFT_TURNS, RECIPES, can_craft
from .dice import fmt, roll
from .dungeon import NEIGHBOURS_8, STAIRS, compute_fov, generate_floor
from .entities import MONSTERS, PETS, monster_table, new_pet, new_player, spawn_monster
from .events import EventBus
from .funfacts import FunFacts
from .items import FISTS, ITEMS, floor_loot_table
from .loot import BOX_TIERS, TRADE_UP_COST, box_stats, next_tier, reroll_fee, roll_box
from .practice import SMALL_MONSTER_HP, Practice
from .shop import Shop
from .showrunner import Showrunner


class MessageLog:
    def __init__(self, maxlen=200):
        self.lines = deque(maxlen=maxlen)

    def add(self, text, colour=C.TEXT):
        self.lines.append((text, colour))

    def recent(self, n):
        return list(self.lines)[-n:]


class World:
    PET_MODES = ("follow", "attack", "stay")

    def __init__(self, seed=None, pet=None, hero=None):
        """pet is (species, name) or None for a run without a companion.
        hero is dict(name, gender, backstory) from character creation, or None."""
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
        self.box_reasons = {}           # tier -> why each unopened box of that tier was given
        self.last_reason = None         # why the box on the reveal screen was given
        self.floor_items = {}           # (x, y) -> [item keys]
        self.loot_rng = random.Random(self.seed ^ 0x100F)
        self.last_reveal = None         # (tier, item key) of the latest box opened
        self.toasts = []                # (turn, text, tier)
        hero = hero or {}
        self.race = self.cls = None
        self.hero_name = hero.get("name") or "Crawler"
        self.gender = hero.get("gender")
        self.backstory = hero.get("backstory")
        self.pet = new_pet(pet[0], pet[1], 0, 0) if pet else None
        if self.pet and self.trait("pet_head_start"):
            self.pet.max_hp += 4
            self.pet.hp += 4
            for _ in range(2):
                self.pet.gain_xp(self.pet.xp_to_next())
        self.hype_turns = 0             # Hype Man's Crowd Work time left
        self.riposte = 0                # Duellist's parries left
        self.remote_shop = False        # Quartermaster's Supply Drop is open
        self._plant_fed_floor = 0       # last floor a houseplant got its free safe-room heal
        self.pending_choice = False     # the UI shows the class picker while True
        self.skill_cooldown = 0
        self.scout_turns = 0            # Analyst's Scout Report display time left
        self.exit_sealed = False
        self.has_key = False            # a Headliner's stairwell key opens the stairs early
        self.stairs_open_turn = 0
        self._stairs_announced = False
        self._next_spawn = 0
        self._spawn_cap = 0
        self.gold = 0
        self.contract = None            # key of the sponsor contract active this floor
        self.pending_offer = None       # contract on offer; the UI asks while this is set
        self.floor_stats = []           # one dict per floor, for the post-run report
        self.box_log = []               # every box opened: tier, item, value, ev
        self.shop = Shop(random.Random(self.seed ^ 0x5A0F))
        self.deal_rng = random.Random(self.seed ^ 0xC0DE)
        self.training = Practice(self)
        self.refresh_stats()
        self.achievements = Achievements(self)
        self.showrunner = Showrunner(self)
        self.funfacts = FunFacts(self)
        self.new_floor(1)

    @property
    def viewers(self):
        return self.showrunner.viewers

    def trait(self, name, default=None):
        """A perk or modifier from the player's backstory, race or class."""
        for table, key in ((BACKSTORIES, self.backstory), (RACES, self.race), (CLASSES, self.cls)):
            if key and name in table[key]:
                return table[key][name]
        return default

    def _sources(self):
        """Data rows that modify the character: backstory, race and class."""
        return [table[key] for table, key in ((BACKSTORIES, self.backstory), (RACES, self.race),
                                              (CLASSES, self.cls)) if key]

    def bonus(self, name):
        """A flat bonus (max_hp, ac, hit, dr, crit_range) summed over backstory, race and class."""
        return sum(src.get(name, 0) for src in self._sources())

    def score(self, attr):
        """Effective attribute score: bought points plus backstory, race and class nudges."""
        return self.player.attrs[attr] + sum(src.get("attrs", {}).get(attr, 0)
                                             for src in self._sources())

    def mod(self, attr):
        return mod(self.score(attr))

    def weapon(self):
        key = self.equipment["weapon"]
        return ITEMS[key] if key else FISTS

    def refresh_stats(self):
        """Derive the player's combat numbers from attributes, level, gear, perks and practice.
        Called whenever any of those change; extra max HP arrives as healing."""
        p = self.player
        wpn = self.weapon()
        style = wpn["style"]
        armour = ITEMS[self.equipment["armour"]] if self.equipment["armour"] else {}
        use = max(self.mod("str"), self.mod("dex")) if style == "blade" else self.mod("str")
        p.attack = proficiency(p.level) + use + wpn.get("hit", 0) + self.bonus("hit")
        p.dmg_n, p.dmg_die = wpn["dice"]
        if style == "unarmed" and self.trait("martial_arts"):
            p.dmg_die = 8
        p.dmg_bonus = use + proficiency(p.level) + wpn.get("dmg", 0) + {
            "unarmed": self.practice("fisticuffs") // 2, "blade": self.practice("blades") // 3,
            "blunt": self.practice("bludgeoning") // 3}[style]
        p.ac = (10 + min(self.mod("dex"), armour.get("max_dex", 99)) + armour.get("ac", 0)
                + self.bonus("ac") + self.practice("dodging") // 4
                + proficiency(p.level) - 2)             # experience: +1 AC every 4 levels
        p.dr = self.bonus("dr")
        p.crit_range = 1 + self.bonus("crit_range") + self.practice("cheap_shots") // 5
        max_hp = (C.PLAYER_BASE_HP + C.HP_PER_LEVEL * (p.level - 1) + self.mod("con") * p.level
                  + self.bonus("max_hp") + self.practice("pain_tolerance"))
        max_hp = max(p.level, max_hp)
        gained = max_hp - p.max_hp
        p.max_hp = max_hp
        p.hp = max(1, min(max_hp, p.hp + max(0, gained)))

    def spend_point(self, attr):
        """Put one attribute point into attr. Free action; returns True if spent."""
        p = self.player
        if attr not in ATTRS or p.stat_points <= 0 or p.attrs[attr] >= MAX_SCORE:
            return False
        p.attrs[attr] += 1
        p.stat_points -= 1
        self.refresh_stats()
        self.events.emit("attribute_up", attr=attr, score=self.score(attr))
        return True

    def save_dc(self):
        """DC monsters roll against for your bombs: 8 + proficiency + DEX modifier."""
        return 8 + proficiency(self.player.level) + self.mod("dex")

    @property
    def address(self):
        """What the System calls you."""
        return self.trait("address") or GENDERS.get(self.gender, {}).get("address", "crawler")

    def practice(self, key):
        """Level (0-15) of a practice skill."""
        return self.training.levels[key]

    def weapon_style(self):
        weapon = self.equipment["weapon"]
        return ITEMS[weapon].get("style", "blunt") if weapon else "unarmed"

    def notice_range(self):
        """How close a monster must be to notice you (Sneaking shortens it)."""
        return C.FOV_RADIUS - self.practice("sneaking") // 4

    def buy_price(self, key):
        mult = (self.trait("buy_mult", 1) * (1 - 0.02 * self.practice("haggling"))
                * (1 - 0.03 * self.mod("cha")))
        return max(1, round(self.shop.price(key) * mult))

    def sell_price(self, key):
        mult = (self.trait("sell_mult", 1) * (1 + 0.03 * self.practice("haggling"))
                * (1 + 0.03 * self.mod("cha")))
        return max(1, round(self.shop.sell_price(key) * mult))

    def reroll_fee(self, tier):
        return max(1, round(reroll_fee(tier) * (1 - 0.05 * self.practice("gambling"))))

    @property
    def active_pet(self):
        """The pet if it's on the map and able to act."""
        return self.pet if self.pet and not self.pet.downed else None

    @property
    def skill(self):
        return CLASSES[self.cls]["skill"] if self.cls else None

    # --- Floors --------------------------------------------------------

    def new_floor(self, depth):
        if self.depth:
            self.shop.end_of_floor(self.depth)
            self.events.emit("shop_restock", depth=self.depth)
        self.contract = self.pending_offer = None
        self.depth = depth
        self.floor = generate_floor(self.rng, depth)
        self.player.x, self.player.y = self.floor.start_room.centre
        self.timer_max = self.timer = (C.floor_turns(depth) + self.trait("timer_bonus", 0)
                                       + 2 * self.practice("cardio"))
        if self.skill == "supply_drop":
            self.skill_cooldown = 0             # once per floor
        self.remote_shop = False
        self._warnings_left = list(C.TIMER_WARNINGS)
        self.monsters = []
        self.floor_items = {}
        self._spawn_monsters()
        self._spawn_items()
        self._spawn_boss()
        self._spawn_acts()
        self._spawn_cap = round(sum(not m.boss for m in self.monsters) * C.RESPAWN_CAP)
        self._next_spawn = self.turn + C.RESPAWN_START
        self.exit_sealed = depth == C.NUM_FLOORS
        self.has_key = False
        self.stairs_open_turn = self.turn + C.floor_turns(depth) // 2
        self._stairs_announced = self.exit_sealed
        self._place_pet()
        self._was_safe = False
        self.update_fov()
        self.messages.add(f"Floor {depth}. It collapses in {self.timer_text()}. Find the stairs.",
                          C.ACCENT)
        if self.exit_sealed:
            self.messages.add(f"The exits are sealed until {BOSSES[depth]['name']} falls.",
                              C.DANGER)
        else:
            self.messages.add(f"The stairwells unlock in {self.timer_text(self.stairs_wait)}, "
                              f"or sooner if you take the Headliner's key.", C.TEXT_DIM)
        if depth >= CHOICE_FLOOR and not self.cls:
            self.pending_choice = True
        self.floor_stats.append(dict(depth=depth, damage_taken=0, gold=0, kills=0,
                                     viewers_start=self.viewers, viewers_end=self.viewers,
                                     contract=None))
        if depth >= OFFER_FROM_FLOOR and self.deal_rng.random() < OFFER_CHANCE:
            self.pending_offer = self.deal_rng.choice(sorted(CONTRACTS))
            self.events.emit("contract_offered", contract=self.pending_offer, depth=depth)
        self.events.emit("floor_start", depth=depth, turn=self.turn)

    def _close_floor_stats(self):
        if self.floor_stats:
            self.floor_stats[-1]["viewers_end"] = self.viewers

    # --- Sponsor contracts ---------------------------------------------

    def accept_contract(self):
        key = self.pending_offer
        if not key:
            return False
        c = CONTRACTS[key]
        self.contract, self.pending_offer = key, None
        self.floor_stats[-1]["contract"] = key
        for m in self.monsters:
            self._contract_buff(m)
        if "timer_mult" in c:
            self.timer = round(self.timer * c["timer_mult"])
            self.timer_max = round(self.timer_max * c["timer_mult"])
        self.messages.add(f"Contract signed with {c['sponsor']}: {c['name']}.", C.ACCENT)
        if "bonus_box" in c:
            self.add_box(c["bonus_box"], f"Signing bonus from {c['sponsor']} for {c['name']}.")
        self.events.emit("contract_accepted", contract=key, depth=self.depth)
        return True

    def _contract_buff(self, m):
        """Apply the active contract's monster changes to one monster."""
        c = CONTRACTS.get(self.contract) if self.contract else None
        if not c:
            return
        m.dmg_bonus += c.get("monster_damage", 0)
        if "monster_hp_mult" in c:
            m.max_hp = m.hp = round(m.max_hp * c["monster_hp_mult"])

    def decline_contract(self):
        if not self.pending_offer:
            return False
        self.events.emit("contract_declined", contract=self.pending_offer, depth=self.depth)
        self.pending_offer = None
        return True

    def _earn_gold(self, amount, source):
        amount = max(0, round(amount))
        self.gold += amount
        if self.floor_stats:
            self.floor_stats[-1]["gold"] += amount
        self.events.emit("gold", amount=amount, source=source, total=self.gold)
        return amount

    def _spawn_monsters(self):
        keys, weights = monster_table(self.depth)
        floor = self.floor
        for room in floor.rooms:
            if room is floor.start_room or room is floor.safe_room:
                continue
            count = self.rng.randint(0, min(2, 1 + self.depth // 3))
            spots = [(x, y) for x, y in room.tiles() if floor.tiles[y][x] != STAIRS]
            for x, y in self.rng.sample(spots, min(count, len(spots))):
                self.monsters.append(spawn_monster(self.rng.choices(keys, weights)[0], x, y))

    def _spawn_items(self):
        keys, weights = floor_loot_table(self.depth)
        floor = self.floor
        for room in floor.rooms:
            chance = C.FLOOR_ITEM_CHANCE + 0.02 * self.practice("scavenging")
            if room is floor.start_room or self.rng.random() >= chance:
                continue
            spots = [(x, y) for x, y in room.tiles() if floor.tiles[y][x] != STAIRS]
            self.floor_items.setdefault(self.rng.choice(spots), []).append(
                self.rng.choices(keys, weights)[0])

    def _spawn_boss(self):
        """The boss waits beside the furthest stairwell."""
        floor = self.floor
        sx, sy = floor.stairs[-1]
        room = next(r for r in floor.rooms if r.contains(sx, sy))
        taken = {(m.x, m.y) for m in self.monsters}
        spots = [(x, y) for x, y in room.tiles()
                 if floor.tiles[y][x] != STAIRS and (x, y) not in taken]
        x, y = min(spots, key=lambda s: (max(abs(s[0] - sx), abs(s[1] - sy)), s))
        self.monsters.append(spawn_boss(self.depth, x, y))

    def _act_rooms(self):
        """Rooms where Acts can wait: not the start, the safe room or a stairwell room,
        and not right next to the start."""
        f = self.floor
        sx, sy = f.start_room.centre
        return [r for r in f.rooms if r is not f.start_room and r is not f.safe_room
                and not any(r.contains(x, y) for x, y in f.stairs)
                and max(abs(r.centre[0] - sx), abs(r.centre[1] - sy)) > 12]

    def _free_spot(self, room):
        taken = {(m.x, m.y) for m in self.monsters}
        spots = [(x, y) for x, y in room.tiles()
                 if self.floor.walkable(x, y) and (x, y) not in taken]
        return self.rng.choice(spots) if spots else None

    def _spawn_acts(self):
        keys, weights = monster_table(self.depth)
        rooms = self._act_rooms()
        self.rng.shuffle(rooms)
        n_open, n_feat = acts_per_floor(self.depth)
        for tier in ["featured"] * n_feat + ["opening"] * n_open:
            if not rooms:
                return
            spot = self._free_spot(rooms.pop())
            if spot:
                self.monsters.append(spawn_act(tier, self.rng.choices(keys, weights)[0], *spot))

    def _respawn(self):
        """Wandering monsters arrive out of sight, more often as the floor wears on.
        Weaker monsters are likelier; Acts and the Headliner never come back."""
        f, p = self.floor, self.player
        elapsed = 1 - self.timer / max(1, self.timer_max)
        gap = C.RESPAWN_START - (C.RESPAWN_START - C.RESPAWN_END) * elapsed
        self._next_spawn = self.turn + max(C.RESPAWN_END, round(gap))
        if sum(not m.boss for m in self.monsters) >= self._spawn_cap:
            return
        keys, weights = monster_table(self.depth)
        weights = [w / MONSTERS[k]["xp"] ** 0.5 for k, w in zip(keys, weights)]
        rooms = [r for r in f.rooms if r is not f.safe_room and r is not f.start_room]
        for _ in range(10):
            spot = self._free_spot(self.rng.choice(rooms))
            if spot and spot not in self.visible and max(abs(spot[0] - p.x), abs(spot[1] - p.y)) > 10 \
                    and not f.is_safe(*spot) and f.tiles[spot[1]][spot[0]] != STAIRS:
                m = spawn_monster(self.rng.choices(keys, weights)[0], *spot)
                self._contract_buff(m)
                self.monsters.append(m)
                self.events.emit("monster_spawned", monster=m.key, depth=self.depth)
                return

    @property
    def stairs_wait(self):
        """Turns until the stairwells unlock by themselves (0 once open)."""
        return max(0, self.stairs_open_turn - self.turn)

    @property
    def stairs_locked(self):
        if self.depth >= C.NUM_FLOORS:
            return False                        # the final floor is sealed by its Headliner instead
        return not self.has_key and self.stairs_wait > 0

    def _place_pet(self):
        pet = self.active_pet
        if not pet:
            return
        p = self.player
        for dx, dy in NEIGHBOURS_8:
            x, y = p.x + dx, p.y + dy
            if self.floor.walkable(x, y) and not self.monster_at(x, y):
                pet.x, pet.y = x, y
                return
        pet.x, pet.y = p.x, p.y          # boxed in: share the tile until it can move

    def update_fov(self):
        self.visible = compute_fov(self.floor, self.player.x, self.player.y)
        explored = self.floor.explored
        for x, y in self.visible:
            explored[y][x] = True

    # --- Queries -------------------------------------------------------

    def pet_at(self, x, y):
        pet = self.active_pet
        return pet if pet and (pet.x, pet.y) == (x, y) else None

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
        elif self.pet_at(tx, ty):
            pet = self.pet
            pet.x, pet.y, p.x, p.y = p.x, p.y, tx, ty       # swap places
            self._on_enter_tile()
        elif self.floor.walkable(tx, ty):
            p.x, p.y = tx, ty
            sneaky = any(not m.alerted and cheb(m, p) <= 4 for m in self.monsters)
            self.events.emit("step", sneaky=sneaky)
            self._on_enter_tile()
        else:
            return False
        self.end_turn()
        return True

    def wait(self):
        if self.state != "playing":
            return False
        if self.trait("photosynthesis"):
            self.player.heal(1)                 # houseplants heal while standing still
        self.end_turn()
        return True

    def descend(self):
        if self.state != "playing":
            return False
        if not self.on_stairs:
            self.messages.add("There are no stairs here.", C.TEXT_DIM)
            return False
        if self.exit_sealed:
            self.messages.add(f"The exit is sealed. Defeat {BOSSES[self.depth]['name']} first.",
                              C.DANGER)
            return False
        if self.stairs_locked:
            self.messages.add(f"The stairwell is locked for another "
                              f"{self.timer_text(self.stairs_wait)}. The Headliner has a key.",
                              C.DANGER)
            return False
        self.events.emit("descend", depth=self.depth, turn=self.turn,
                         timer_left=self.timer, timer_max=self.timer_max,
                         early=self.depth < C.NUM_FLOORS and self.stairs_wait > 0)
        self._close_floor_stats()
        if self.depth >= C.NUM_FLOORS:
            self.state = "victory"
            self._close_floor_stats()
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
        per_turn = (effect(self, "rest_mult") * self.trait("rest_mult", 1)
                    * (1 + 0.1 * self.practice("power_napping")))
        owed = 0.0
        while p.hp < p.max_hp and self.timer > C.REST_MIN_TIMER and self.state == "playing":
            owed += per_turn
            p.heal(int(owed))
            owed -= int(owed)
            self._tick_clock()
        spent = self.turn - start_turn
        if self.active_pet:
            self.pet.hp = self.pet.max_hp
        self.messages.add(f"You rest for {self.timer_text(spent)} and recover "
                          f"{p.hp - start_hp} HP.", C.GOOD)
        self.events.emit("rest", turns=spent, healed=p.hp - start_hp)
        self.update_fov()
        return True

    def _spend_turns(self, n):
        """Pass time without monsters acting (safe-room activities)."""
        for _ in range(n):
            if self.state != "playing":
                return
            self._tick_clock()

    def _safe_room_activity_ok(self, turns):
        if self.state != "playing":
            return False
        if not self.in_safe_room:
            self.messages.add("You can only do that in a safe room.", C.TEXT_DIM)
            return False
        if self.timer <= turns + C.REST_MIN_TIMER:
            self.messages.add("No time for that. The floor is coming down!", C.DANGER)
            return False
        return True

    def craft(self, index):
        """Craft recipe RECIPES[index] at the safe-room bench."""
        recipe = RECIPES[index]
        turns = max(1, round(CRAFT_TURNS * self.trait("craft_mult", 1)
                             * (1 - 0.08 * self.practice("tinkering"))))
        if not self._safe_room_activity_ok(turns):
            return False
        if not can_craft(recipe, self.inventory):
            self.messages.add(f"You're missing parts for {recipe['name']}.", C.TEXT_DIM)
            return False
        for key in recipe["needs"]:
            self.inventory.remove(key)
        self.inventory.append(recipe["makes"])
        if (self.loot_rng.random() < 0.04 * self.practice("tinkering")
                and len(self.inventory) < C.INVENTORY_SIZE):
            self.inventory.append(recipe["makes"])
            self.messages.add("Tinkering pays off: you get a spare.", C.GOOD)
        self._spend_turns(turns)
        self.messages.add(f"You craft {recipe['name']}: {ITEMS[recipe['makes']]['name']}.",
                          C.GOOD)
        self.events.emit("craft", recipe=recipe["key"], item=recipe["makes"])
        return True

    # --- Shop ----------------------------------------------------------

    def shop_buy(self, key):
        if not self._in_safe_room_msg():
            return False
        price = self.buy_price(key)
        if self.gold < price:
            self.messages.add(f"You need {price} gold for that.", C.TEXT_DIM)
            return False
        if len(self.inventory) >= C.INVENTORY_SIZE:
            self.messages.add("Your pack is full.", C.DANGER)
            return False
        if not self.shop.buy(key):
            self.messages.add(f"Sold out of {ITEMS[key]['name']}.", C.DANGER)
            self.events.emit("shop_sold_out", item=key, depth=self.depth)
            return False
        self.gold -= price
        self.inventory.append(key)
        if not self.in_safe_room:
            self.remote_shop = False            # Supply Drop is good for one purchase
        self.messages.add(f"You buy a {ITEMS[key]['name']} for {price} gold.", C.GOOD)
        self.events.emit("shop_buy", item=key, price=price, depth=self.depth)
        return True

    def shop_sell(self, index):
        if not self.in_safe_room or not self._in_safe_room_msg() \
                or not 0 <= index < len(self.inventory):
            return False
        key = self.inventory.pop(index)
        price = self.sell_price(key)
        self.gold += price
        self.shop.take_back(key)
        self.messages.add(f"You sell the {ITEMS[key]['name']} for {price} gold.", C.TEXT_DIM)
        self.events.emit("shop_sell", item=key, price=price, depth=self.depth,
                         item_kind=ITEMS[key]["kind"])
        return True

    def _in_safe_room_msg(self):
        if self.state != "playing":
            return False
        if not self.in_safe_room and not self.remote_shop:
            self.messages.add("The shop is only open in safe rooms.", C.TEXT_DIM)
            return False
        return True

    # --- Companion -----------------------------------------------------

    def command_pet(self):
        """Cycle the pet's mode. Free action."""
        pet = self.pet
        if not pet:
            return False
        pet.mode = self.PET_MODES[(self.PET_MODES.index(pet.mode) + 1) % len(self.PET_MODES)]
        what = {"follow": "will follow you and defend itself",
                "attack": "will hunt anything you can see",
                "stay": "will hold its position"}[pet.mode]
        self.messages.add(f"{pet.name} {what}.", C.INFO)
        return True

    def revive_pet(self):
        pet = self.pet
        if not pet or not pet.downed:
            return False
        if not self._safe_room_activity_ok(C.PET_REVIVE_TURNS):
            return False
        self._spend_turns(C.PET_REVIVE_TURNS)
        pet.downed, pet.hp, pet.cooldown, pet.mode = False, pet.max_hp, 0, "follow"
        self._place_pet()
        self.messages.add(f"{pet.name} is back on its feet and annoyed about it.", C.GOOD)
        self.events.emit("pet_revived", pet=pet.name)
        return True

    def pet_attack(self, target, mult=1, verb="hits"):
        pet = self.pet
        mult *= ((2 if pet.enraged else 1) * (1.5 if self.hype_turns else 1)
                 * (1 + 0.05 * self.practice("pet_bonding")))
        res = attack(pet, target, self.rng, mult=mult)
        if not res.hit:
            self.messages.add(f"{pet.name} misses {target.the}.", C.TEXT_DIM)
            return
        self.messages.add(f"{pet.name} {verb} {target.the} for {res.damage}.", pet.colour)
        self.events.emit("pet_hit", pet=pet.name, damage=res.damage)
        self._after_hit(target, "pet")

    def pet_pounce(self, target):
        pet = self.pet
        pet.cooldown = PETS[pet.species]["cooldown"]
        self.events.emit("pet_ability", pet=pet.name, species=pet.species, ability="Pounce")
        self.pet_attack(target, mult=2, verb="pounces on")

    def pet_lick(self):
        pet, p = self.pet, self.player
        pet.cooldown = PETS[pet.species]["cooldown"]
        healed = p.heal(6 + 2 * pet.level)
        self.messages.add(f"{pet.name} licks your wounds. You recover {healed} HP. Gross.",
                          C.GOOD)
        self.events.emit("pet_ability", pet=pet.name, species=pet.species, ability="Lick Wounds")

    def pet_squawk(self, targets):
        pet = self.pet
        pet.cooldown = PETS[pet.species]["cooldown"]
        for m in targets:
            m.stunned = 1 if m.boss else 2          # bosses shake it off faster
        self.messages.add(f"{pet.name} lets out an ear-splitting squawk! "
                          f"{len(targets)} monster{'s' if len(targets) != 1 else ''} reel.",
                          pet.colour)
        self.events.emit("pet_ability", pet=pet.name, species=pet.species,
                         ability="Ear-Splitting Squawk")

    def pet_dirty_trick(self, target):
        pet = self.pet
        pet.cooldown = PETS[pet.species]["cooldown"]
        self.events.emit("pet_ability", pet=pet.name, species=pet.species, ability="Dirty Trick")
        self.pet_attack(target, mult=3, verb="sneak-stabs")

    def pet_flees(self):
        self.events.emit("pet_flee", pet=self.pet.name, species=self.pet.species)

    def monster_attack_pet(self, monster):
        pet = self.pet
        res = attack(monster, pet, self.rng)
        if not res.hit:
            return
        self.messages.add(f"{monster.The} hits {pet.name} for {res.damage}.", C.DANGER)
        if res.killed:
            pet.downed = True
            self.messages.add(f"{pet.name} is down! Revive them in a safe room.", C.DANGER)
            self.events.emit("pet_downed", pet=pet.name, species=pet.species, depth=self.depth)

    # --- Class & skills ------------------------------------------------

    def choose_class(self, race, cls):
        if race not in RACES or cls not in CLASSES or self.cls:
            return False
        self.race, self.cls, self.pending_choice = race, cls, False
        if self.trait("no_armour") and self.equipment["armour"]:
            key = self.equipment["armour"]
            self.equipment["armour"] = None
            if len(self.inventory) < C.INVENTORY_SIZE:
                self.inventory.append(key)
            else:
                self.floor_items.setdefault((self.player.x, self.player.y), []).append(key)
            self.messages.add(f"Your new bark won't fit in the {ITEMS[key]['name']}.", C.TEXT_DIM)
        self.refresh_stats()
        name = f"{RACES[race]['name']} {CLASSES[cls]['name']}"
        article = "an" if name[0] in "AEIOU" else "a"
        self.messages.add(f"You are now {article} {name}. Press 1 for "
                          f"{SKILLS[self.skill]['name']}.", C.ACCENT)
        self.events.emit("class_chosen", race=race, cls=cls, title=name)
        return True

    def use_skill(self):
        if self.state != "playing":
            return False
        if not self.cls:
            self.messages.add(f"You get a class on floor {CHOICE_FLOOR}.", C.TEXT_DIM)
            return False
        key = self.skill
        spec = SKILLS[key]
        if self.skill_cooldown:
            self.messages.add(f"{spec['name']} is recharging ({self.skill_cooldown} turns).",
                              C.TEXT_DIM)
            return False
        if key in ("haymaker", "arc_bolt", "pocket_popper", "riposte") and self.in_safe_room:
            self.messages.add("The System forbids violence in safe rooms.", C.TEXT_DIM)
            return False
        p = self.player
        if key == "haymaker":
            adjacent = [m for m in self.monsters if cheb(m, p) == 1]
            if not adjacent:
                self.messages.add("Nobody close enough to punch.", C.TEXT_DIM)
                return False
            target = min(adjacent, key=lambda m: m.hp)
            res = attack(p, target, self.rng, mult=2, sure=True)
            self.messages.add(f"HAYMAKER! {target.The} takes {res.damage} "
                              f"({fmt(p.dmg_n, p.dmg_die, p.dmg_bonus)}, doubled).", C.ACCENT)
            self._after_hit(target, "skill")
        elif key == "arc_bolt":
            seen = [m for m in self.monsters if (m.x, m.y) in self.visible
                    and cheb(m, p) <= spec["range"]]
            if not seen:
                self.messages.add("No target in range.", C.TEXT_DIM)
                return False
            target = min(seen, key=lambda m: cheb(m, p))
            dmg = target.take_damage(max(1, 6 + 2 * p.level + self.mod("int")))
            self.messages.add(f"Arc Bolt crackles into {target.the} for {dmg}.", C.INFO)
            self._after_hit(target, "skill")
        elif key == "scout_report":
            self.scout_turns = spec["duration"]
            self.messages.add("Scout Report: odds are on the panel for the next 20 turns.",
                              C.INFO)
        elif key == "field_brew":
            junk = [i for i, k in enumerate(self.inventory) if ITEMS[k]["kind"] == "junk"]
            if not junk:
                self.messages.add("No junk to brew with. Even you have standards.", C.TEXT_DIM)
                return False
            old = self.inventory.pop(junk[0])
            new = self.loot_rng.choices(("tonic", "brew", "elixir"), (6, 3, 1))[0]
            self.inventory.append(new)
            self.messages.add(f"You brew the {ITEMS[old]['name']} into a {ITEMS[new]['name']}. "
                              f"Don't think about it.", C.GOOD)
        elif key == "rile_up":
            pet = self.active_pet
            if not pet:
                self.messages.add("You have nobody to rile up.", C.TEXT_DIM)
                return False
            pet.enraged = spec["duration"]
            self.messages.add(f"{pet.name} is FURIOUS. Double damage for {spec['duration']} turns.",
                              pet.colour)
        elif key == "crowd_work":
            self.hype_turns = spec["duration"]
            self.messages.add("You work the crowd. Kills earn triple viewers for 10 turns.",
                              C.ACCENT)
        elif key == "pocket_popper":
            target = self._bomb_target(spec["range"])
            if not target:
                return False
            self._explode("popper", target)
        elif key == "supply_drop":
            self.remote_shop = True
            self.messages.add("A sponsor drone lowers a shop crate. One purchase, then it leaves.",
                              C.ACCENT)
        elif key == "riposte":
            self.riposte = spec["charges"]
            self.messages.add(f"En garde. You'll parry the next {spec['charges']} attacks.", C.INFO)
        self.skill_cooldown = max(spec["cooldown"] // 2, spec["cooldown"] - self.mod("int"))
        self.events.emit("skill", skill=key)
        self.end_turn()
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

    def equip(self, index):
        """Wear or wield an inventory item; whatever was in the slot goes back to the pack."""
        if self.state != "playing" or not 0 <= index < len(self.inventory):
            return False
        slot = ITEMS[self.inventory[index]]["kind"]
        if slot == "armour" and self.trait("no_armour"):
            self.messages.add("Houseplants don't wear armour. You'd snap a stem.", C.TEXT_DIM)
            return False
        key = self.inventory.pop(index)
        old = self.equipment[slot]
        if old:
            self.inventory.append(old)
            self.events.emit("unequip", slot=slot, item=old)
        self.equipment[slot] = key
        self.refresh_stats()
        self.messages.add(f"You equip the {ITEMS[key]['name']}.", C.INFO)
        self.events.emit("equip", slot=slot, item=key)
        return True

    def unequip(self, slot):
        key = self.equipment.get(slot)
        if self.state != "playing" or not key or len(self.inventory) >= C.INVENTORY_SIZE:
            return False
        self.equipment[slot] = None
        self.inventory.append(key)
        self.refresh_stats()
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
            healed = p.heal(round(item["heal"] * self.trait("potion_mult", 1)
                                  * self.trait("class_potion_mult", 1)
                                  * (1 + 0.08 * self.practice("first_aid"))
                                  * (1 + 0.05 * self.mod("int"))))
            self.messages.add(f"You drink the {item['name']} and recover {healed} HP.", C.GOOD)
            self.events.emit("item_use", item=key, healed=healed)
        else:
            if not self._throw_bomb(index):
                return False
        self.end_turn()
        return True

    def _throw_bomb(self, index):
        if self.in_safe_room:
            self.messages.add("The System forbids explosions in safe rooms.", C.TEXT_DIM)
            return False
        target = self._bomb_target(C.BOMB_RANGE)
        if not target:
            return False
        self._explode(self.inventory.pop(index), target)
        return True

    def _bomb_target(self, reach):
        p = self.player
        seen = [m for m in self.monsters if (m.x, m.y) in self.visible and cheb(m, p) <= reach]
        if not seen:
            self.messages.add("No target in range.", C.TEXT_DIM)
            return None
        return min(seen, key=lambda m: cheb(m, p))

    def _explode(self, key, target):
        item = ITEMS[key]
        damage = round(roll(self.rng, *item["dice"]) * self.trait("bomb_mult", 1)
                       * (1 + 0.08 * self.practice("lobbing")))
        dc = self.save_dc()
        self.messages.add(f"You throw the {item['name']}. BOOM: {damage} damage "
                          f"({fmt(*item['dice'])}). Dexterity save DC {dc} for half.", C.ACCENT)
        killed = 0
        for m in list(self.monsters):
            if cheb(m, target) <= item["radius"]:
                saved, face = saving_throw(self.rng, m.save, dc)
                dealt = m.take_damage(max(1, damage // 2) if saved else damage)
                if saved:
                    self.messages.add(f"{m.The} dives aside (d20 {face}{m.save:+d} vs DC {dc}) "
                                      f"and takes {dealt}.", C.TEXT_DIM)
                m.alerted = True
                killed += not m.alive
                self._after_hit(m, "bomb")
        self.events.emit("bomb", item=key, kills=killed)

    # --- Loot boxes ----------------------------------------------------

    def add_box(self, tier, reason):
        """Loot boxes come from achievements and sponsors; each remembers why it was given."""
        self.boxes.append(tier)
        self.box_reasons.setdefault(tier, []).append(reason)
        self.messages.add(f"You receive a {BOX_TIERS[tier]['name']} loot box. Open it in a "
                          f"safe room.", BOX_TIERS[tier]["colour"])
        self.events.emit("box_gained", tier=tier, source=reason)

    def _take_reason(self, tier):
        reasons = self.box_reasons.get(tier)
        return reasons.pop(0) if reasons else "A gift from the System. It won't say why."

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
        self.last_reason = self._take_reason(tier)
        self._reveal(tier)
        return True

    def _reveal(self, tier, rerolled=False):
        key = roll_box(tier, self.loot_rng)
        self.inventory.append(key)
        self.last_reveal = (tier, key)
        self.box_log.append(dict(tier=tier, item=key, value=ITEMS[key]["value"],
                                 ev=round(box_stats(tier)[0], 2), rerolled=rerolled,
                                 turn=self.turn, reason=self.last_reason or ""))
        self.messages.add(f"The {BOX_TIERS[tier]['name']} box contains: {ITEMS[key]['name']}!",
                          BOX_TIERS[tier]["colour"])
        self.events.emit("box_opened", tier=tier, item=key, rerolled=rerolled)

    def reroll(self):
        """Hand back the item from the last box and roll that box again, for a fee."""
        if self.state != "playing" or not self.last_reveal or not self.in_safe_room:
            return False
        tier, key = self.last_reveal
        fee = self.reroll_fee(tier)
        if key not in self.inventory:
            return False
        if self.gold < fee:
            self.messages.add(f"A reroll costs {fee} gold.", C.TEXT_DIM)
            return False
        self.gold -= fee
        self.inventory.remove(key)
        self.events.emit("box_reroll", tier=tier, item=key, fee=fee)
        self._reveal(tier, rerolled=True)
        return True

    def trade_up(self, tier):
        """Swap TRADE_UP_COST boxes of a tier for one of the next tier. Free action."""
        to = next_tier(tier)
        if self.state != "playing" or not to or self.boxes.count(tier) < TRADE_UP_COST:
            return False
        if not self.in_safe_room:
            self.messages.add("Trades happen in safe rooms.", C.TEXT_DIM)
            return False
        for _ in range(TRADE_UP_COST):
            self.boxes.remove(tier)
            self._take_reason(tier)
        self.boxes.append(to)
        self.box_reasons.setdefault(to, []).append(
            f"Traded up from {TRADE_UP_COST} {BOX_TIERS[tier]['name']} boxes.")
        self.messages.add(f"Traded {TRADE_UP_COST} {BOX_TIERS[tier]['name']} boxes for a "
                          f"{BOX_TIERS[to]['name']} box.", BOX_TIERS[to]["colour"])
        self.events.emit("box_trade", tier=tier, to=to)
        return True

    # --- Combat --------------------------------------------------------

    def _player_attack(self, target):
        p = self.player
        chance = hit_chance(p, target)
        small = not target.boss and target.max_hp <= SMALL_MONSTER_HP
        bonus = self.practice("stomping") // 2 if small else 0
        mult = 1 + 0.03 * self.practice("giant_killer") if target.boss else 1
        res = attack(p, target, self.rng, mult=mult, bonus=bonus)
        self.events.emit("player_attack", target=target.key, chance=chance, hit=res.hit,
                         crit=res.crit, small=small, boss=target.boss, roll=res.roll)
        if not res.hit:
            self.messages.add(f"You miss {target.the}. ({res.dice_text()})", C.TEXT_DIM)
            self._announce_natural(res, target)
            return
        crit = "CRITICAL! " if res.crit else ""
        self.messages.add(f"{crit}You hit {target.the} for {res.damage}. ({res.dice_text()})")
        self._announce_natural(res, target)
        self.events.emit("player_hit", target=target.key, damage=res.damage, crit=res.crit)
        self._after_hit(target, "melee")

    def _announce_natural(self, res, foe, by_player=True):
        """Natural 20s and 1s get their own event, so the System can react."""
        if res.natural:
            kind = ("nat20" if res.roll == 20 else "nat1") if by_player else \
                ("foe_nat20" if res.roll == 20 else "foe_nat1")
            self.events.emit(kind, foe=foe.the, Foe=foe.The)

    def _after_hit(self, target, by):
        """Kill the monster if it's dead, otherwise check for a boss phase change."""
        if target not in self.monsters:
            return
        if not target.alive:
            self._kill_monster(target, by)
        elif target.tier == "headliner" and target.phase == 1 and target.hp <= target.max_hp // 2 \
                and BOSSES[boss_depth(target)].get("final"):
            self._boss_phase_two(target)

    def _boss_phase_two(self, boss):
        boss.phase = 2
        boss.dmg_bonus += PHASE_TWO["damage_bonus"]
        boss.ranged = PHASE_TWO["ranged"]
        taken = {(m.x, m.y) for m in self.monsters} | {(self.player.x, self.player.y)}
        if self.active_pet:
            taken.add((self.pet.x, self.pet.y))
        spots = [(boss.x + dx, boss.y + dy) for dx, dy in NEIGHBOURS_8
                 if self.floor.walkable(boss.x + dx, boss.y + dy)
                 and not self.floor.is_safe(boss.x + dx, boss.y + dy)
                 and (boss.x + dx, boss.y + dy) not in taken]
        for key, (x, y) in zip(PHASE_TWO["adds"], spots):
            add = spawn_monster(key, x, y)
            add.alerted = True
            self.monsters.append(add)
        self.messages.add(f"{boss.name} roars: 'Security! Get me SECURITY!'", C.DANGER)
        self.events.emit("boss_phase", boss=boss.name, phase=2)

    def _kill_monster(self, target, by):
        p = self.player
        self.monsters.remove(target)
        p.kills += 1
        if self.floor_stats:
            self.floor_stats[-1]["kills"] += 1
        gold = target.xp_value * C.GOLD_PER_XP * self.loot_rng.uniform(0.6, 1.4) \
            * effect(self, "gold_mult") * (2 if target.tier == "headliner" else 1) \
            * (1 + 0.05 * self.practice("pickpocketing"))
        self.messages.add(f"{target.The} dies. +{self._earn_gold(gold, 'kill')} gold.", C.GOOD)
        self.events.emit("kill", monster=target.key, monster_name=target.name, xp=target.xp_value,
                         style=self.weapon_style() if by == "melee" else by,
                         boss=target.boss, small=not target.boss and target.max_hp <= SMALL_MONSTER_HP,
                         depth=self.depth, turn=self.turn, by=by,
                         player_hp=p.hp, player_max_hp=p.max_hp)
        pet = self.active_pet
        if pet:
            if by == "pet":
                pet.kills += 1
                self.events.emit("pet_kill", pet=pet.name, species=pet.species,
                                 monster_name=target.name, boss=target.boss)
            for level in pet.gain_xp(target.xp_value if by == "pet" else target.xp_value // 2):
                self.messages.add(f"{pet.name} is now level {level}.", pet.colour)
                self.events.emit("pet_level_up", pet=pet.name, species=pet.species, level=level)
        if target.tier == "headliner":
            b = BOSSES[boss_depth(target)]
            self.events.emit("boss_kill", boss=target.name, depth=self.depth)
            if b.get("final"):
                self.exit_sealed = False
                self.messages.add("The exits unseal. Get out!", C.GOOD)
            else:
                self.has_key = True
                self.messages.add(f"{target.name} drops a stairwell key. The stairs are open "
                                  f"to you.", C.ACCENT)
            self._drop(target, self.loot_rng.choice(C.HEADLINER_DROPS))
        elif target.tier:
            self._act_reward(target)
        if not target.boss and self.loot_rng.random() < C.ITEM_DROP_CHANCE:
            self._drop(target, self.loot_rng.choice(MONSTERS[target.key]["drops"]))
        levels = p.gain_xp(target.xp_value)
        if levels:
            self.refresh_stats()
        for level in levels:
            self.messages.add(f"Level up! You are now level {level}. Spend your attribute "
                              f"points with L ({p.stat_points} to spend).", C.ACCENT)
            self.events.emit("level_up", level=level)

    def _drop(self, where, key):
        self.floor_items.setdefault((where.x, where.y), []).append(key)

    def _act_reward(self, act):
        """Opening Acts drop a map of the area; Featured Acts drop a better haul."""
        self.events.emit("act_kill", tier=act.tier, monster_name=act.name, depth=self.depth)
        if act.tier == "opening":
            f = self.floor
            for y in range(max(0, act.y - MAP_RADIUS), min(f.height, act.y + MAP_RADIUS + 1)):
                for x in range(max(0, act.x - MAP_RADIUS), min(f.width, act.x + MAP_RADIUS + 1)):
                    if f.tiles[y][x] != 0 or any(f.tiles[y + dy][x + dx] != 0
                                                 for dx, dy in NEIGHBOURS_8
                                                 if f.in_bounds(x + dx, y + dy)):
                        f.explored[y][x] = True
            self.messages.add(f"{act.name} drops a map. The area around you is marked out.",
                              C.INFO)
            self.events.emit("map_found", depth=self.depth)
        else:
            keys, weights = floor_loot_table(min(C.NUM_FLOORS, self.depth + 2))
            for _ in range(2):
                self._drop(act, self.loot_rng.choices(keys, weights)[0])
            self.messages.add(f"{act.name} leaves behind a haul. Press G to collect.", C.ACCENT)

    def monster_attack(self, monster, ranged=False):
        p = self.player
        if self.riposte:
            self.riposte -= 1
            self.messages.add(f"You parry {monster.the}!", C.INFO)
            if not ranged and cheb(monster, p) == 1:
                res = attack(p, monster, self.rng)
                if res.hit:
                    self.messages.add(f"Riposte! {monster.The} takes {res.damage}. "
                                      f"({res.dice_text()})", C.ACCENT)
                    self._after_hit(monster, "skill")
            self.events.emit("riposte", monster=monster.key)
            return
        res = attack(monster, p, self.rng)
        how = "shoots" if ranged else "hits"
        if not res.hit:
            self.messages.add(f"{monster.The} {'shoots and ' if ranged else ''}misses you. "
                              f"({res.dice_text()})", C.TEXT_DIM)
            self._announce_natural(res, monster, by_player=False)
            self.events.emit("dodged", source=monster.key)
            return
        crit = "CRITICAL! " if res.crit else ""
        self.messages.add(f"{crit}{monster.The} {how} you for {res.damage}. ({res.dice_text()})",
                          C.DANGER)
        self._announce_natural(res, monster, by_player=False)
        self.floor_stats[-1]["damage_taken"] += res.damage
        self.events.emit("damage_taken", source=monster.key, damage=res.damage, hp=p.hp,
                         ranged=ranged)
        if res.killed:
            self._kill_player(f"Killed by {monster.a} on floor {self.depth}")

    def _kill_player(self, cause):
        self._close_floor_stats()
        self.state = "dead"
        self.death_cause = cause
        self.messages.add(cause + ".", C.DANGER)
        self.events.emit("player_death", cause=cause, depth=self.depth, turn=self.turn)

    # --- Turn flow -----------------------------------------------------

    def _on_enter_tile(self):
        safe = self.in_safe_room
        if safe and not self._was_safe:
            self.messages.add("Safe room. No combat allowed in here. R rests, M opens the menu.", C.GOOD)
            if self.trait("photosynthesis") and self._plant_fed_floor != self.depth:
                self._plant_fed_floor = self.depth
                healed = self.player.heal(self.player.max_hp)
                if healed:
                    self.messages.add(f"The grow lights restore {healed} HP. Bliss.", C.GOOD)
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
        if self.turn % max(2, (C.REGEN_INTERVAL - self.mod("con")) // self.trait("regen_mult", 1)) == 0:
            p.heal(1)
        if self.turn % C.REGEN_INTERVAL == 0 and self.active_pet:
            self.pet.heal(1)
        if self.hype_turns:
            self.hype_turns -= 1
        if self.pet and self.pet.enraged:
            self.pet.enraged -= 1
        if self.skill_cooldown:
            self.skill_cooldown -= 1
        if self.scout_turns:
            self.scout_turns -= 1
        if not self._stairs_announced and not self.stairs_wait:
            self._stairs_announced = True
            self.messages.add("The stairwells have unlocked. Clock's still ticking.", C.ACCENT)
            self.events.emit("stairs_open", depth=self.depth, timer_left=self.timer)
        if self.turn >= self._next_spawn:
            self._respawn()
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
        take_pet_turn(self)
        take_monster_turns(self)
        if self.state == "playing":
            self._tick_clock()

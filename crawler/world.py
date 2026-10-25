"""The game world: all rules and state, with no pygame dependency.

Keeping this headless means tests and (later) the bot can play thousands of
turns without a window. Player actions return True when they used a turn.
"""
import random
from collections import deque

from . import config as C
from .achievements import Achievements
from .ai import cheb, take_monster_turns, take_pet_turn
from .bosses import BOSSES, PHASE_TWO, boss_depth, spawn_boss
from .character import BACKSTORIES, GENDERS
from .classes import CHOICE_FLOOR, CLASSES, RACES, SKILLS, apply_choice, apply_stats
from .combat import attack, hit_chance
from .contracts import CONTRACTS, OFFER_CHANCE, OFFER_FROM_FLOOR, effect
from .crafting import CRAFT_TURNS, RECIPES, can_craft
from .dungeon import NEIGHBOURS_8, STAIRS, compute_fov, generate_floor
from .entities import PETS, monster_table, new_pet, new_player, spawn_monster
from .events import EventBus
from .funfacts import FunFacts
from .items import ITEMS, STAT_BONUSES, floor_loot_table
from .loot import BOX_TIERS, TRADE_UP_COST, box_stats, next_tier, reroll_fee, roll_box
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
        self.floor_items = {}           # (x, y) -> [item keys]
        self.loot_rng = random.Random(self.seed ^ 0x100F)
        self.last_reveal = None         # (tier, item key) of the latest box opened
        self.toasts = []                # (turn, text, tier)
        hero = hero or {}
        self.race = self.cls = None
        self.hero_name = hero.get("name") or "Crawler"
        self.gender = hero.get("gender")
        self.backstory = hero.get("backstory")
        if self.backstory:
            apply_stats(self.player, BACKSTORIES[self.backstory])
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
        self.gold = 0
        self.contract = None            # key of the sponsor contract active this floor
        self.pending_offer = None       # contract on offer; the UI asks while this is set
        self.floor_stats = []           # one dict per floor, for the post-run report
        self.box_log = []               # every box opened: tier, item, value, ev
        self.shop = Shop(random.Random(self.seed ^ 0x5A0F))
        self.deal_rng = random.Random(self.seed ^ 0xC0DE)
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

    @property
    def address(self):
        """What the System calls you."""
        return self.trait("address") or GENDERS.get(self.gender, {}).get("address", "crawler")

    def buy_price(self, key):
        return max(1, round(self.shop.price(key) * self.trait("buy_mult", 1)))

    def sell_price(self, key):
        return max(1, round(self.shop.sell_price(key) * self.trait("sell_mult", 1)))

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
        self.timer_max = self.timer = C.floor_turns(depth) + self.trait("timer_bonus", 0)
        if self.skill == "supply_drop":
            self.skill_cooldown = 0             # once per floor
        self.remote_shop = False
        self._warnings_left = list(C.TIMER_WARNINGS)
        self.monsters = []
        self.floor_items = {}
        self._spawn_monsters()
        self._spawn_items()
        self._spawn_boss()
        self.exit_sealed = depth == C.NUM_FLOORS
        self._place_pet()
        self._was_safe = False
        self.update_fov()
        self.messages.add(f"Floor {depth}. It collapses in {self.timer_text()}. Find the stairs.",
                          C.ACCENT)
        if self.exit_sealed:
            self.messages.add(f"The exits are sealed until {BOSSES[depth]['name']} falls.",
                              C.DANGER)
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
            m.power += c.get("monster_power", 0)
            if "monster_hp_mult" in c:
                m.max_hp = m.hp = round(m.max_hp * c["monster_hp_mult"])
        if "timer_mult" in c:
            self.timer = round(self.timer * c["timer_mult"])
            self.timer_max = round(self.timer_max * c["timer_mult"])
        self.messages.add(f"Contract signed with {c['sponsor']}: {c['name']}.", C.ACCENT)
        if "bonus_box" in c:
            self.add_box(c["bonus_box"], "signing bonus")
        self.events.emit("contract_accepted", contract=key, depth=self.depth)
        return True

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
        self.events.emit("descend", depth=self.depth, turn=self.turn,
                         timer_left=self.timer, timer_max=self.timer_max)
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
        per_turn = effect(self, "rest_mult") * self.trait("rest_mult", 1)
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
        turns = max(1, round(CRAFT_TURNS * self.trait("craft_mult", 1)))
        if not self._safe_room_activity_ok(turns):
            return False
        if not can_craft(recipe, self.inventory):
            self.messages.add(f"You're missing parts for {recipe['name']}.", C.TEXT_DIM)
            return False
        for key in recipe["needs"]:
            self.inventory.remove(key)
        self.inventory.append(recipe["makes"])
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
        self.events.emit("shop_sell", item=key, price=price, depth=self.depth)
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
        mult *= (2 if pet.enraged else 1) * (1.5 if self.hype_turns else 1)
        res = attack(pet, target, self.rng, mult=mult)
        if not res.hit:
            self.messages.add(f"{pet.name} misses {target.the}.", C.TEXT_DIM)
            return
        self.messages.add(f"{pet.name} {verb} {target.the} for {res.damage}.", pet.colour)
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
        apply_choice(self.player, race, cls)
        self.race, self.cls, self.pending_choice = race, cls, False
        if self.trait("no_armour") and self.equipment["armour"]:
            key = self.equipment["armour"]
            self._apply_bonuses(key, -1)
            self.equipment["armour"] = None
            if len(self.inventory) < C.INVENTORY_SIZE:
                self.inventory.append(key)
            else:
                self.floor_items.setdefault((self.player.x, self.player.y), []).append(key)
            self.messages.add(f"Your new bark won't fit in the {ITEMS[key]['name']}.", C.TEXT_DIM)
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
            self.messages.add(f"HAYMAKER! {target.The} takes {res.damage}.", C.ACCENT)
            self._after_hit(target, "skill")
        elif key == "arc_bolt":
            seen = [m for m in self.monsters if (m.x, m.y) in self.visible
                    and cheb(m, p) <= spec["range"]]
            if not seen:
                self.messages.add("No target in range.", C.TEXT_DIM)
                return False
            target = min(seen, key=lambda m: cheb(m, p))
            dmg = target.take_damage(8 + 2 * p.level)
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
        self.skill_cooldown = spec["cooldown"]
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

    def _apply_bonuses(self, key, sign):
        p = self.player
        for stat in STAT_BONUSES:
            setattr(p, stat, getattr(p, stat) + sign * ITEMS[key].get(stat, 0))

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
            healed = p.heal(round(item["heal"] * self.trait("potion_mult", 1)
                                  * self.trait("class_potion_mult", 1)))
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
        damage = round(item["damage"] * self.trait("bomb_mult", 1))
        self.messages.add(f"You throw the {item['name']}. BOOM.", C.ACCENT)
        killed = 0
        for m in list(self.monsters):
            if cheb(m, target) <= item["radius"]:
                m.take_damage(damage)
                m.alerted = True
                killed += not m.alive
                self._after_hit(m, "bomb")
        self.events.emit("bomb", item=key, kills=killed)

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
        self._reveal(tier)
        return True

    def _reveal(self, tier, rerolled=False):
        key = roll_box(tier, self.loot_rng)
        self.inventory.append(key)
        self.last_reveal = (tier, key)
        self.box_log.append(dict(tier=tier, item=key, value=ITEMS[key]["value"],
                                 ev=round(box_stats(tier)[0], 2), rerolled=rerolled,
                                 turn=self.turn))
        self.messages.add(f"The {BOX_TIERS[tier]['name']} box contains: {ITEMS[key]['name']}!",
                          BOX_TIERS[tier]["colour"])
        self.events.emit("box_opened", tier=tier, item=key, rerolled=rerolled)

    def reroll(self):
        """Hand back the item from the last box and roll that box again, for a fee."""
        if self.state != "playing" or not self.last_reveal or not self.in_safe_room:
            return False
        tier, key = self.last_reveal
        fee = reroll_fee(tier)
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
        self.boxes.append(to)
        self.messages.add(f"Traded {TRADE_UP_COST} {BOX_TIERS[tier]['name']} boxes for a "
                          f"{BOX_TIERS[to]['name']} box.", BOX_TIERS[to]["colour"])
        self.events.emit("box_trade", tier=tier, to=to)
        return True

    # --- Combat --------------------------------------------------------

    def _player_attack(self, target):
        p = self.player
        chance = hit_chance(p, target)
        res = attack(p, target, self.rng)
        self.events.emit("player_attack", target=target.key, chance=chance, hit=res.hit,
                         crit=res.crit)
        if not res.hit:
            self.messages.add(f"You miss {target.the}.", C.TEXT_DIM)
            return
        crit = " Critical hit!" if res.crit else ""
        self.messages.add(f"You hit {target.the} for {res.damage}.{crit}")
        self.events.emit("player_hit", target=target.key, damage=res.damage, crit=res.crit)
        self._after_hit(target, "melee")

    def _after_hit(self, target, by):
        """Kill the monster if it's dead, otherwise check for a boss phase change."""
        if target not in self.monsters:
            return
        if not target.alive:
            self._kill_monster(target, by)
        elif target.boss and target.phase == 1 and target.hp <= target.max_hp // 2 \
                and BOSSES[boss_depth(target)].get("final"):
            self._boss_phase_two(target)

    def _boss_phase_two(self, boss):
        boss.phase = 2
        boss.power += PHASE_TWO["power_bonus"]
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
            * effect(self, "gold_mult") * (2 if target.boss else 1)
        self.messages.add(f"{target.The} dies. +{self._earn_gold(gold, 'kill')} gold.", C.GOOD)
        self.events.emit("kill", monster=target.key, monster_name=target.name, xp=target.xp_value,
                         boss=target.boss, depth=self.depth, turn=self.turn, by=by,
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
        if target.boss:
            b = BOSSES[boss_depth(target)]
            self.events.emit("boss_kill", boss=target.name, depth=self.depth)
            self.add_box(b["box"], "boss")
            if b.get("final"):
                self.exit_sealed = False
                self.messages.add("The exits unseal. Get out!", C.GOOD)
        if self.loot_rng.random() < C.ITEM_DROP_CHANCE:
            keys, weights = floor_loot_table(self.depth)
            self.floor_items.setdefault((target.x, target.y), []).append(
                self.loot_rng.choices(keys, weights)[0])
        for level in p.gain_xp(target.xp_value):
            self.messages.add(f"Level up! You are now level {level}.", C.ACCENT)
            self.events.emit("level_up", level=level)

    def monster_attack(self, monster, ranged=False):
        p = self.player
        if self.riposte:
            self.riposte -= 1
            self.messages.add(f"You parry {monster.the}!", C.INFO)
            if not ranged and cheb(monster, p) == 1:
                res = attack(p, monster, self.rng)
                if res.hit:
                    self.messages.add(f"Riposte! {monster.The} takes {res.damage}.", C.ACCENT)
                    self._after_hit(monster, "skill")
            self.events.emit("riposte", monster=monster.key)
            return
        res = attack(monster, p, self.rng)
        how = "shoots" if ranged else "hits"
        if not res.hit:
            self.messages.add(f"{monster.The} {'shoots and ' if ranged else ''}misses you.",
                              C.TEXT_DIM)
            return
        crit = " A brutal crit!" if res.crit else ""
        self.messages.add(f"{monster.The} {how} you for {res.damage}.{crit}", C.DANGER)
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
        if self.turn % max(1, C.REGEN_INTERVAL // self.trait("regen_mult", 1)) == 0:
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

class_name World
extends RefCounted
## The game world: all rules and state, with no Node or scene dependency (crawler/world.py).
##
## Keeping this headless means tests and the bot can play thousands of turns without a window.
## Player actions return true when they used a turn. Out of combat every action is a whole turn:
## you act, then the pet, the monsters and the clock. In combat (`combat`, an Encounter) each round
## is one turn in which you get a move, an action and a bonus action, and the fighters act in
## initiative order around you.
##
## LAYOUT (one file, three slices; see docs/port-plan.md 9.1; S6 and S7 are done):
##   S6 (this slice, world.py lines 1-466): state and init, traits, refresh_stats, attributes,
##       prices, floors and spawns, contracts, queries, timer_text.
##   S7 appends below the marked "S7" section: attacks, kills, drops, Acts, combat mode, opportunity
##       attacks, turn flow (world.py 1084-1557) and ai.gd.
##   S8 appends below the marked "S8" section: move, wait, descend, rest, safe-room activities,
##       craft, shop trades, pet methods, class and skills, items, bombs, boxes (world.py 468-1080).
## A few small methods from those slices are already here because S6 code or the S6 tests need them
## (listed under "Pulled forward"), and S7 pulled move_player, wait and the pet methods forward from the
## S8 range for the `walk` trace (listed under "Pulled forward from S8 by S7"); S8 must not port
## them a second time.
##
## Python module imports that S6 does not need are not mirrored here (Ai.CHASE_RADIUS, Bosses.MAP_RADIUS
## and PHASE_TWO, Crafting.CRAFT_TURNS, Loot.TRADE_UP_COST, Practice.SMALL_MONSTER_HP are read from their
## own classes by the later slices).
##
## Back-references (port plan section 3): World creates Practice, Achievements, Showrunner and
## FunFacts in _init, in Python's order, and keeps them for life; they hold WeakRefs to the world.
##
## Python values that can be None stay `null` here (race, cls, gender, backstory, contract,
## pending_offer, death_cause, last_reason, last_reveal), so those members are Variants.
## `floor` and `seed` shadow Godot's global functions of the same names (kept so call sites read
## like Python); nothing in this class calls those functions.

## The pet modes the C key cycles through (config "world").
static var PET_MODES: Array = Content.config("world")["PET_MODES"]
## The floor at which the class picker appears (config "classes").
static var CHOICE_FLOOR: int = Content.config("classes")["CHOICE_FLOOR"]

var seed: int
var rng: PyRandom
var events: EventBus
var messages: MessageLog
var player: Player
var turn: int = 0
var state: String = "playing"          ## "playing" | "dead" | "victory"
var death_cause: Variant = null
var depth: int = 0
var inventory: Array = []              ## item keys, unequipped
var equipment: Dictionary = {"weapon": null, "armour": null}
var boxes: Array = []                  ## unopened loot box tiers
var box_reasons: Dictionary = {}       ## tier -> why each unopened box of that tier was given
var last_reason: Variant = null        ## why the box on the reveal screen was given
var floor_items: Dictionary = {}       ## Vector2i -> Array of item keys
var loot_rng: PyRandom
var last_reveal: Variant = null        ## [tier, item key] of the latest box opened
var toasts: Array = []                 ## [turn, text, tier] or [turn, text, tier, sub]
var race: Variant = null
var cls: Variant = null
var hero_name: String
var gender: Variant = null
var backstory: Variant = null
var pet: Pet = null
var hype_turns: int = 0                ## Hype Man's Crowd Work time left
var riposte: int = 0                   ## Duellist's parries left
var remote_shop: bool = false          ## Quartermaster's Supply Drop is open
var _plant_fed_floor: int = 0          ## last floor a houseplant got its free safe-room heal
var pending_choice: bool = false       ## the UI shows the class picker while true
var skill_cooldown: int = 0
var scout_turns: int = 0               ## Analyst's Scout Report display time left
var exit_sealed: bool = false
var has_key: bool = false              ## a Headliner's stairwell key opens the stairs early
var stairs_open_turn: int = 0
var _stairs_announced: bool = false
var _next_spawn: int = 0
var _spawn_cap: int = 0
var gold: int = 0
var contract: Variant = null           ## key of the sponsor contract active this floor
var pending_offer: Variant = null      ## contract on offer; the UI asks while this is set
var floor_stats: Array = []            ## one Dictionary per floor, for the post-run report
var box_log: Array = []                ## every box opened: tier, item, value, ev
var shop: Shop
var deal_rng: PyRandom
var training: Practice
var achievements: Achievements
var showrunner: Showrunner
var funfacts: FunFacts
var combat: Encounter = null           ## an Encounter while a fight is on
var _acted: Dictionary = {}            ## set of combatants that have had their go this round
var _hold_combat: bool = false         ## true while one act resolves: don't end the fight yet

# Set by new_floor in Python (not in __init__ before the first floor).
var floor: DungeonFloor = null
var timer: int = 0
var timer_max: int = 0
var _warnings_left: Array = []
var monsters: Array = []
var visible: Dictionary = {}           ## set of Vector2i in view (membership only)
var _was_safe: bool = false


## pet is [species, name] or null for a run without a companion (a name of "" or null uses the
## species' default). hero is {name, gender, backstory} from character creation, or null. seed_value
## null draws a random seed (not parity-relevant).
##
## Trace seams (port plan 6.2, no rule reads them): tap_events / tap_messages are assigned to
## events.tap / messages.tap before floor 1 is built, and `tracer`, when it has an attach_world(world)
## method, is given the world (it must hold it weakly) before floor 1, so the floor_start record can
## read the world state.
func _init(seed_value: Variant = null, pet_value: Variant = null, hero_value: Variant = null,
		tap_events: Callable = Callable(), tap_messages: Callable = Callable(),
		tracer: Object = null) -> void:
	seed = seed_value if seed_value != null else (randi() & 0x3FFFFFFF)
	rng = PyRandom.new(seed)
	events = EventBus.new()
	messages = MessageLog.new()
	events.tap = tap_events
	messages.tap = tap_messages
	player = Entities.new_player(0, 0)
	loot_rng = PyRandom.new(seed ^ 0x100F)
	var hero: Dictionary = hero_value if PyMath.truthy(hero_value) else {}
	hero_name = hero["name"] if PyMath.truthy(hero.get("name")) else "Crawler"
	gender = hero.get("gender")
	backstory = hero.get("backstory")
	if PyMath.truthy(pet_value):
		var pet_name: Variant = pet_value[1]
		pet = Entities.new_pet(pet_value[0], "" if pet_name == null else pet_name, 0, 0)
	if pet != null and PyMath.truthy(get_trait("pet_head_start")):
		pet.max_hp += 4
		pet.hp += 4
		for _i in range(2):
			pet.gain_xp(pet.xp_to_next())
	shop = Shop.new(PyRandom.new(seed ^ 0x5A0F))
	deal_rng = PyRandom.new(seed ^ 0xC0DE)
	training = Practice.new(self)
	refresh_stats()
	achievements = Achievements.new(self)
	showrunner = Showrunner.new(self)
	funfacts = FunFacts.new(self)
	if tracer != null and tracer.has_method("attach_world"):
		tracer.attach_world(self)
	new_floor(1)


## A banner over the view for TOAST_TURNS turns (tier picks the colour). Expired ones are dropped
## here, so the list stays short in memory and in the save.
func add_toast(text: String, tier: String, sub: Variant = null, turn_value: Variant = null) -> void:
	var t: int = turn if turn_value == null else turn_value
	var kept: Array = []
	for old in toasts:
		if turn - old[0] < GameConfig.TOAST_TURNS:
			kept.append(old)
	toasts = kept
	if PyMath.truthy(sub):
		toasts.append([t, text, tier, sub])
	else:
		toasts.append([t, text, tier])


## Current viewer count (the Showrunner's).
var viewers: int:
	get:
		return showrunner.viewers


## A perk or modifier from the player's backstory, race or class (the first that has it).
func get_trait(trait_name: String, default: Variant = null) -> Variant:
	var tables: Array = [Content.table("backstories"), Content.table("races"), Content.table("classes")]
	var keys: Array = [backstory, race, cls]
	for i in range(3):
		var key: Variant = keys[i]
		if PyMath.truthy(key) and (tables[i][key] as Dictionary).has(trait_name):
			return tables[i][key][trait_name]
	return default


## Data rows that modify the character: backstory, race and class.
func _sources() -> Array:
	var out: Array = []
	var tables: Array = [Content.table("backstories"), Content.table("races"), Content.table("classes")]
	var keys: Array = [backstory, race, cls]
	for i in range(3):
		if PyMath.truthy(keys[i]):
			out.append(tables[i][keys[i]])
	return out


## A flat bonus (max_hp, ac, hit, dr, crit_range) summed over backstory, race and class.
func bonus(bonus_name: String) -> int:
	var total := 0
	for src in _sources():
		total += src.get(bonus_name, 0)
	return total


## Effective attribute score: bought points plus backstory, race and class nudges.
func score(attr: String) -> int:
	var total: int = player.attrs[attr]
	var nudge := 0
	for src in _sources():
		nudge += src.get("attrs", {}).get(attr, 0)
	return total + nudge


## Ability modifier of the effective score: (score - 10) // 2.
func mod(attr: String) -> int:
	return Attributes.mod(score(attr))


## The equipped weapon's item row, or Items.FISTS when unarmed.
func weapon() -> Dictionary:
	var key: Variant = equipment["weapon"]
	return Items.items()[key] if PyMath.truthy(key) else Items.FISTS


## Derive the player's combat numbers from attributes, level, gear, perks and practice. Called
## whenever any of those change; extra max HP arrives as healing.
func refresh_stats() -> void:
	var p := player
	var wpn := weapon()
	var style: String = wpn["style"]
	var armour: Dictionary = {}
	if PyMath.truthy(equipment["armour"]):
		armour = Items.items()[equipment["armour"]]
	var use: int = maxi(mod("str"), mod("dex")) if style == "blade" else mod("str")
	p.attack = Attributes.proficiency(p.level) + use + wpn.get("hit", 0) + bonus("hit")
	p.dmg_n = wpn["dice"][0]
	p.dmg_die = wpn["dice"][1]
	if style == "unarmed" and PyMath.truthy(get_trait("martial_arts")):
		p.dmg_die = 8
	var skill_bonus := 0
	match style:
		"unarmed":
			skill_bonus = PyMath.floordiv(practice("fisticuffs"), 2)
		"blade":
			skill_bonus = PyMath.floordiv(practice("blades"), 3)
		"blunt":
			skill_bonus = PyMath.floordiv(practice("bludgeoning"), 3)
	p.dmg_bonus = use + Attributes.proficiency(p.level) + wpn.get("dmg", 0) + skill_bonus
	p.ac = (10 + mini(mod("dex"), armour.get("max_dex", 99)) + armour.get("ac", 0)
			+ bonus("ac") + PyMath.floordiv(practice("dodging"), 4)
			+ Attributes.proficiency(p.level) - 2)             # experience: +1 AC every 4 levels
	p.dr = bonus("dr")
	p.crit_range = 1 + bonus("crit_range") + PyMath.floordiv(practice("cheap_shots"), 5)
	var max_hp: int = (GameConfig.PLAYER_BASE_HP + GameConfig.HP_PER_LEVEL * (p.level - 1)
			+ mod("con") * p.level + bonus("max_hp") + practice("pain_tolerance"))
	max_hp = maxi(p.level, max_hp)
	var gained := max_hp - p.max_hp
	p.max_hp = max_hp
	p.hp = maxi(1, mini(max_hp, p.hp + maxi(0, gained)))


## Put one attribute point into attr. Free action; returns true if spent.
func spend_point(attr: String) -> bool:
	var p := player
	if not Attributes.table().has(attr) or p.stat_points <= 0 or p.attrs[attr] >= Attributes.MAX_SCORE:
		return false
	p.attrs[attr] += 1
	p.stat_points -= 1
	refresh_stats()
	events.emit("attribute_up", {"attr": attr, "score": score(attr)})
	return true


## DC monsters roll against for your bombs: 8 + proficiency + DEX modifier.
func save_dc() -> int:
	return 8 + Attributes.proficiency(player.level) + mod("dex")


## What the System calls you.
var address: String:
	get:
		var t: Variant = get_trait("address")
		if PyMath.truthy(t):
			return t
		return Content.table("genders").get(gender, {}).get("address", "crawler")


## Level (0-15) of a practice skill.
func practice(key: String) -> int:
	return training.levels[key]


## "unarmed", or the equipped weapon's style (default "blunt").
func weapon_style() -> String:
	var weapon_key: Variant = equipment["weapon"]
	if PyMath.truthy(weapon_key):
		return Items.items()[weapon_key].get("style", "blunt")
	return "unarmed"


## How close a monster must be to notice you (Sneaking shortens it).
func notice_range() -> int:
	return GameConfig.FOV_RADIUS - PyMath.floordiv(practice("sneaking"), 4)


## What the shop charges you: shop price times perks, Haggling and CHA, at least 1.
func buy_price(key: String) -> int:
	var mult: float = (float(get_trait("buy_mult", 1)) * (1 - 0.02 * practice("haggling"))
			* (1 - 0.03 * mod("cha")))
	return maxi(1, PyMath.round_half_even(shop.price(key) * mult))


## What the shop pays you: sell price times perks, Haggling and CHA, at least 1.
func sell_price(key: String) -> int:
	var mult: float = (float(get_trait("sell_mult", 1)) * (1 + 0.03 * practice("haggling"))
			* (1 + 0.03 * mod("cha")))
	return maxi(1, PyMath.round_half_even(Shop.sell_price(key) * mult))


## Fee to reroll a box of this tier, cut by Gambling, at least 1.
func reroll_fee(tier: String) -> int:
	return maxi(1, PyMath.round_half_even(Loot.reroll_fee(tier) * (1 - 0.05 * practice("gambling"))))


## The pet if it's on the map and able to act, else null.
var active_pet: Pet:
	get:
		return pet if pet != null and not pet.downed else null


## The class skill key (String), or null without a class.
var skill: Variant:
	get:
		return Content.table("classes")[cls]["skill"] if PyMath.truthy(cls) else null


# --- Floors ---------------------------------------------------------------------

## Build floor `new_depth`: end any fight, turn the shop over, generate the map, spawn monsters,
## items, the Headliner and Acts (main stream, in Python's order), set timers, place the pet, announce
## the floor, maybe offer a contract (deal stream) and emit floor_start.
func new_floor(new_depth: int) -> void:
	_end_combat("floor")
	if depth != 0:
		shop.end_of_floor(depth)
		events.emit("shop_restock", {"depth": depth})
	contract = null
	pending_offer = null
	depth = new_depth
	floor = Dungeon.generate_floor(rng, new_depth)
	var start := floor.start_room.centre()
	player.x = start.x
	player.y = start.y
	timer = (GameConfig.floor_turns(new_depth) + int(get_trait("timer_bonus", 0))
			+ 2 * practice("cardio"))
	timer_max = timer
	if skill == "supply_drop":
		skill_cooldown = 0                 # once per floor
	remote_shop = false
	_warnings_left = GameConfig.TIMER_WARNINGS.duplicate()
	monsters = []
	floor_items = {}
	_spawn_monsters()
	_spawn_items()
	_spawn_boss()
	_spawn_acts()
	var non_boss := 0
	for m in monsters:
		if not m.boss:
			non_boss += 1
	_spawn_cap = PyMath.round_half_even(non_boss * GameConfig.RESPAWN_CAP)
	_next_spawn = turn + GameConfig.RESPAWN_START
	exit_sealed = new_depth == GameConfig.NUM_FLOORS
	has_key = false
	stairs_open_turn = turn + PyMath.floordiv(GameConfig.floor_turns(new_depth), 2)
	_stairs_announced = exit_sealed
	_place_pet()
	_was_safe = false
	update_fov()
	messages.add("Floor %d. It collapses in %s. Find the stairs." % [new_depth, timer_text()],
			GameConfig.ACCENT)
	if exit_sealed:
		messages.add("The exits are sealed until %s falls." % Content.boss(new_depth)["name"],
				GameConfig.DANGER)
	else:
		messages.add("The stairwells unlock in %s, or sooner if you take the Headliner's key."
				% timer_text(stairs_wait), GameConfig.TEXT_DIM)
	if new_depth >= CHOICE_FLOOR and not PyMath.truthy(cls):
		pending_choice = true
	floor_stats.append({"depth": new_depth, "damage_taken": 0, "gold": 0, "kills": 0,
			"viewers_start": viewers, "viewers_end": viewers, "contract": null})
	if new_depth >= Contracts.OFFER_FROM_FLOOR and deal_rng.random() < Contracts.OFFER_CHANCE:
		var keys: Array = Contracts.contracts().keys()
		keys.sort()
		pending_offer = deal_rng.choice(keys)
		events.emit("contract_offered", {"contract": pending_offer, "depth": new_depth})
	events.emit("floor_start", {"depth": new_depth, "turn": turn})


func _close_floor_stats() -> void:
	if not floor_stats.is_empty():
		floor_stats[-1]["viewers_end"] = viewers


# --- Sponsor contracts ----------------------------------------------------------

## Sign the pending contract: buff this floor's monsters, scale the timer, pay the signing bonus.
## Returns false when nothing is on offer.
func accept_contract() -> bool:
	var key: Variant = pending_offer
	if not PyMath.truthy(key):
		return false
	var c: Dictionary = Contracts.contracts()[key]
	contract = key
	pending_offer = null
	floor_stats[-1]["contract"] = key
	for m in monsters:
		_contract_buff(m)
	if c.has("timer_mult"):
		timer = PyMath.round_half_even(timer * c["timer_mult"])
		timer_max = PyMath.round_half_even(timer_max * c["timer_mult"])
	messages.add("Contract signed with %s: %s." % [c["sponsor"], c["name"]], GameConfig.ACCENT)
	if c.has("bonus_box"):
		add_box(c["bonus_box"], "Signing bonus from %s for %s." % [c["sponsor"], c["name"]])
	events.emit("contract_accepted", {"contract": key, "depth": depth})
	return true


## Apply the active contract's monster changes to one monster.
func _contract_buff(m: Monster) -> void:
	var c: Dictionary = {}
	if PyMath.truthy(contract):
		c = Contracts.contracts().get(contract, {})
	if c.is_empty():
		return
	m.dmg_bonus += c.get("monster_damage", 0)
	if c.has("monster_hp_mult"):
		m.max_hp = PyMath.round_half_even(m.max_hp * c["monster_hp_mult"])
		m.hp = m.max_hp


## Turn down the pending contract. Returns false when nothing is on offer.
func decline_contract() -> bool:
	if not PyMath.truthy(pending_offer):
		return false
	events.emit("contract_declined", {"contract": pending_offer, "depth": depth})
	pending_offer = null
	return true


func _earn_gold(amount: float, source: String) -> int:
	var got := maxi(0, PyMath.round_half_even(amount))
	gold += got
	if not floor_stats.is_empty():
		floor_stats[-1]["gold"] += got
	events.emit("gold", {"amount": got, "source": source, "total": gold})
	return got


# --- Spawning -------------------------------------------------------------------

func _spawn_monsters() -> void:
	var table := Entities.monster_table(depth)
	var keys: Array = table[0]
	var weights: Array = table[1]
	var fl := floor
	for room in fl.rooms:
		if is_same(room, fl.start_room) or is_same(room, fl.safe_room):
			continue
		var count := rng.randint(0, mini(2, 1 + PyMath.floordiv(depth, 3)))
		var spots: Array = []
		for t in room.tiles():
			if fl.tiles[t.y][t.x] != DungeonFloor.STAIRS:
				spots.append(t)
		for spot in rng.sample(spots, mini(count, spots.size())):
			monsters.append(Entities.spawn_monster(rng.choices(keys, weights)[0], spot.x, spot.y))


func _spawn_items() -> void:
	var table := Items.floor_loot_table(depth)
	var keys: Array = table[0]
	var weights: Array = table[1]
	var fl := floor
	for room in fl.rooms:
		var chance: float = GameConfig.FLOOR_ITEM_CHANCE + 0.02 * practice("scavenging")
		if is_same(room, fl.start_room) or rng.random() >= chance:
			continue
		var spots: Array = []
		for t in room.tiles():
			if fl.tiles[t.y][t.x] != DungeonFloor.STAIRS:
				spots.append(t)
		var where: Vector2i = rng.choice(spots)
		if not floor_items.has(where):
			floor_items[where] = []
		floor_items[where].append(rng.choices(keys, weights)[0])


## The boss waits beside the furthest stairwell.
func _spawn_boss() -> void:
	var fl := floor
	var s: Vector2i = fl.stairs[-1]
	var room: DungeonRoom = null
	for r in fl.rooms:
		if r.contains(s.x, s.y):
			room = r
			break
	if room == null:
		push_error("World._spawn_boss: no room holds the furthest stairs (Python raises StopIteration)")
		return
	var taken := {}
	for m in monsters:
		taken[Vector2i(m.x, m.y)] = true
	var best: Variant = null
	var best_d := 0
	for t in room.tiles():
		if fl.tiles[t.y][t.x] == DungeonFloor.STAIRS or taken.has(t):
			continue
		var d := maxi(absi(t.x - s.x), absi(t.y - s.y))
		# min() over (distance, (x, y)): lowest distance, then lowest x, then lowest y
		if best == null or d < best_d or (d == best_d and (t.x < best.x or (t.x == best.x and t.y < best.y))):
			best = t
			best_d = d
	monsters.append(Bosses.spawn_boss(depth, best.x, best.y))


## Rooms where Acts can wait: not the start, the safe room or a stairwell room, and not right next
## to the start.
func _act_rooms() -> Array:
	var f := floor
	var sc := f.start_room.centre()
	var out: Array = []
	for r in f.rooms:
		if is_same(r, f.start_room) or is_same(r, f.safe_room):
			continue
		var has_stairs := false
		for s in f.stairs:
			if r.contains(s.x, s.y):
				has_stairs = true
				break
		if has_stairs:
			continue
		var c := r.centre()
		if maxi(absi(c.x - sc.x), absi(c.y - sc.y)) > 12:
			out.append(r)
	return out


## A random free walkable tile in the room (Vector2i), or null.
func _free_spot(room: DungeonRoom) -> Variant:
	var taken := {}
	for m in monsters:
		taken[Vector2i(m.x, m.y)] = true
	var spots: Array = []
	for t in room.tiles():
		if floor.walkable(t.x, t.y) and not taken.has(t):
			spots.append(t)
	return rng.choice(spots) if not spots.is_empty() else null


func _spawn_acts() -> void:
	var table := Entities.monster_table(depth)
	var keys: Array = table[0]
	var weights: Array = table[1]
	var rooms := _act_rooms()
	rng.shuffle(rooms)
	var n := Bosses.acts_per_floor(depth)
	var tiers: Array = []
	for _i in range(n.y):
		tiers.append("featured")
	for _i in range(n.x):
		tiers.append("opening")
	for tier in tiers:
		if rooms.is_empty():
			return
		var spot: Variant = _free_spot(rooms.pop_back())
		if spot != null:
			monsters.append(Bosses.spawn_act(tier, rng.choices(keys, weights)[0], spot.x, spot.y))


## Wandering monsters arrive out of sight, more often as the floor wears on. Weaker monsters are
## likelier; Acts and the Headliner never come back.
func _respawn() -> void:
	var f := floor
	var p := player
	var elapsed: float = 1 - float(timer) / maxi(1, timer_max)
	var gap: float = GameConfig.RESPAWN_START - (GameConfig.RESPAWN_START - GameConfig.RESPAWN_END) * elapsed
	_next_spawn = turn + maxi(GameConfig.RESPAWN_END, PyMath.round_half_even(gap))
	var non_boss := 0
	for m in monsters:
		if not m.boss:
			non_boss += 1
	if non_boss >= _spawn_cap:
		return
	var table := Entities.monster_table(depth)
	var keys: Array = table[0]
	var raw: Array = table[1]
	var weights: Array = []
	for i in range(keys.size()):
		weights.append(float(raw[i]) / pow(Entities.monsters()[keys[i]]["xp"], 0.5))
	var rooms: Array = []
	for r in f.rooms:
		if not is_same(r, f.safe_room) and not is_same(r, f.start_room):
			rooms.append(r)
	for _i in range(10):
		var spot: Variant = _free_spot(rng.choice(rooms))
		if spot != null and not visible.has(spot) \
				and maxi(absi(spot.x - p.x), absi(spot.y - p.y)) > 10 \
				and not f.is_safe(spot.x, spot.y) and f.tiles[spot.y][spot.x] != DungeonFloor.STAIRS:
			var m := Entities.spawn_monster(rng.choices(keys, weights)[0], spot.x, spot.y)
			_contract_buff(m)
			monsters.append(m)
			events.emit("monster_spawned", {"monster": m.key, "depth": depth})
			return


## Turns until the stairwells unlock by themselves (0 once open).
var stairs_wait: int:
	get:
		return maxi(0, stairs_open_turn - turn)


## True while the stairwells are shut: before the unlock time and without the Headliner's key (never on the last floor).
var stairs_locked: bool:
	get:
		if depth >= GameConfig.NUM_FLOORS:
			return false                   # the final floor is sealed by its Headliner instead
		return not has_key and stairs_wait > 0


func _place_pet() -> void:
	var pt := active_pet
	if pt == null:
		return
	var p := player
	for n in DungeonFloor.NEIGHBOURS_8:
		var x := p.x + n.x
		var y := p.y + n.y
		if floor.walkable(x, y) and monster_at(x, y) == null:
			pt.x = x
			pt.y = y
			return
	pt.x = p.x                             # boxed in: share the tile until it can move
	pt.y = p.y


## Recompute `visible` from the player's tile and mark those tiles explored.
func update_fov() -> void:
	visible = Dungeon.compute_fov(floor, player.x, player.y)
	var explored := floor.explored
	for v in visible:
		explored[v.y][v.x] = 1


# --- Queries --------------------------------------------------------------------

## The active pet standing on (x, y), or null.
func pet_at(x: int, y: int) -> Pet:
	var pt := active_pet
	return pt if pt != null and pt.x == x and pt.y == y else null


## The first monster standing on (x, y), or null.
func monster_at(x: int, y: int) -> Monster:
	for m in monsters:
		if m.x == x and m.y == y:
			return m
	return null


## True when the player stands in the safe room or its doorway.
var in_safe_room: bool:
	get:
		return floor.is_safe(player.x, player.y)


## True when the player stands on a stairs tile.
var on_stairs: bool:
	get:
		return floor.tiles[player.y][player.x] == DungeonFloor.STAIRS


## "<h>h <mm>m" for `turns` (default: the floor timer).
func timer_text(turns: Variant = null) -> String:
	var t: int = timer if turns == null else turns
	return "%dh %sm" % [PyMath.floordiv(t, 60), PyFmt.zero_pad(PyMath.mod(t, 60), 2)]


# --- Pulled forward (needed by S6 code or S6 tests; do not port again) ----------

## Loot boxes come from achievements and sponsors; each remembers why it was given.
## (S8, world.py 1008; accept_contract calls it.)
func add_box(tier: String, reason: String) -> void:
	boxes.append(tier)
	if not box_reasons.has(tier):
		box_reasons[tier] = []
	box_reasons[tier].append(reason)
	messages.add("You receive a %s loot box. Open it in a safe room." % Content.box(tier)["name"],
			Content.box(tier)["colour"])
	events.emit("box_gained", {"tier": tier, "source": reason})


## (S8, world.py 759; the S6 attribute and floor tests choose a class.)
func choose_class(race_key: String, cls_key: String) -> bool:
	if not Content.table("races").has(race_key) or not Content.table("classes").has(cls_key) \
			or PyMath.truthy(cls):
		return false
	race = race_key
	cls = cls_key
	pending_choice = false
	if PyMath.truthy(get_trait("no_armour")) and PyMath.truthy(equipment["armour"]):
		var key: String = equipment["armour"]
		equipment["armour"] = null
		if inventory.size() < GameConfig.INVENTORY_SIZE:
			inventory.append(key)
		else:
			var where := Vector2i(player.x, player.y)
			if not floor_items.has(where):
				floor_items[where] = []
			floor_items[where].append(key)
		messages.add("Your new bark won't fit in the %s." % Items.items()[key]["name"], GameConfig.TEXT_DIM)
	refresh_stats()
	var title := "%s %s" % [Content.race(race_key)["name"], Content.klass(cls_key)["name"]]
	var article := "an" if title[0] in "AEIOU" else "a"
	messages.add("You are now %s %s. Press 1 for %s." % [article, title, Content.skill(skill)["name"]],
			GameConfig.ACCENT)
	events.emit("class_chosen", {"race": race_key, "cls": cls_key, "title": title})
	return true


## Wear or wield an inventory item; whatever was in the slot goes back to the pack.
## (S8, world.py 900; the S6 attribute tests equip gear.)
func equip(index: int) -> bool:
	if state != "playing" or not (0 <= index and index < inventory.size()):
		return false
	var slot: String = Items.items()[inventory[index]]["kind"]
	if slot == "armour" and PyMath.truthy(get_trait("no_armour")):
		messages.add("Houseplants don't wear armour. You'd snap a stem.", GameConfig.TEXT_DIM)
		return false
	var key: String = inventory.pop_at(index)
	var old: Variant = equipment[slot]
	if PyMath.truthy(old):
		inventory.append(old)
		events.emit("unequip", {"slot": slot, "item": old})
	equipment[slot] = key
	refresh_stats()
	messages.add("You equip the %s." % Items.items()[key]["name"], GameConfig.INFO)
	events.emit("equip", {"slot": slot, "item": key})
	return true


## reason: cleared, lost_track, safe_room, floor, death or victory.
## (S7, world.py 1421; new_floor calls it.)
func _end_combat(reason: String) -> void:
	var enc := combat
	if enc == null:
		return
	combat = null
	if reason == "cleared":
		messages.add("The fight is over.", GameConfig.GOOD)
	elif reason == "lost_track":
		messages.add("Nobody's chasing you any more. The fight is over.", GameConfig.TEXT_DIM)
	events.emit("combat_end", {"cause": reason, "turns": enc.round, "depth": depth, "turn": turn})


# --- Pulled forward from S8 by S7 (the `walk` trace needs the player to move and wait; S8 must not port these again) ----

## Step or bump-attack. Returns true when a turn was used. (S8 range, world.py 468; pulled forward.)
func move_player(dx: int, dy: int) -> bool:
	if state != "playing":
		return false
	var p := player
	var tx := p.x + dx
	var ty := p.y + dy
	var target := monster_at(tx, ty)
	if target != null:
		if in_safe_room:
			messages.add("The System forbids violence in safe rooms. Spoilsport.", GameConfig.TEXT_DIM)
			return false
		if not _can_spend("action"):
			return false
		_player_attack(target)
		_spend("action")
		return true
	var swap := pet_at(tx, ty)
	if swap == null and not floor.walkable(tx, ty):
		return false
	if not _can_spend("move"):
		return false
	if swap != null:                                        # never provokes
		pet.x = p.x                                         # swap places
		pet.y = p.y
		p.x = tx
		p.y = ty
		_on_enter_tile()
	else:
		if not opportunity_attacks(p, tx, ty):
			return true                                     # cut down on the way out
		p.x = tx
		p.y = ty
		var sneaky := false
		for m in monsters:
			if not m.alerted and Ai.cheb(m, p) <= 4:
				sneaky = true
				break
		events.emit("step", {"sneaky": sneaky})
		_on_enter_tile()
	_spend("move")
	return true


## Pass a turn; in combat, end your turn early. (S8 range, world.py 503; pulled forward.)
func wait() -> bool:
	if state != "playing":
		return false
	if PyMath.truthy(get_trait("photosynthesis")):
		player.heal(1)                     # houseplants heal while standing still
	end_turn()
	return true


## (S8 range, world.py 696; pulled forward: Ai calls it.)
func pet_attack(target: Monster, mult: float = 1, verb: String = "hits") -> bool:
	var pt := pet
	mult *= ((2 if pt.enraged != 0 else 1) * (1.5 if hype_turns != 0 else 1)
			* (1 + 0.05 * practice("pet_bonding")))
	var res := Combat.attack(pt, target, rng, mult)
	if not res.hit:
		messages.add("%s misses %s." % [pt.name, target.the], GameConfig.TEXT_DIM)
		return false
	messages.add("%s %s %s for %d." % [pt.name, verb, target.the, res.damage], pt.colour)
	events.emit("pet_hit", {"pet": pt.name, "damage": res.damage})
	_after_hit(target, "pet")
	return true


## (S8 range, world.py 709; pulled forward.)
func pet_pounce(target: Monster) -> void:
	var pt := pet
	pt.cooldown = Entities.pets()[pt.species]["cooldown"]
	events.emit("pet_ability", {"pet": pt.name, "species": pt.species, "ability": "Pounce"})
	pet_attack(target, 2, "pounces on")


## (S8 range, world.py 715; pulled forward.)
func pet_lick() -> void:
	var pt := pet
	var p := player
	pt.cooldown = Entities.pets()[pt.species]["cooldown"]
	var healed := p.heal(6 + 2 * pt.level)
	messages.add("%s licks your wounds. You recover %d HP. Gross." % [pt.name, healed], GameConfig.GOOD)
	events.emit("pet_ability", {"pet": pt.name, "species": pt.species, "ability": "Lick Wounds"})


## (S8 range, world.py 723; pulled forward.)
func pet_squawk(targets: Array) -> void:
	var pt := pet
	pt.cooldown = Entities.pets()[pt.species]["cooldown"]
	for m in targets:
		m.stunned = 1 if m.boss else 2             # bosses shake it off faster
	messages.add("%s lets out an ear-splitting squawk! %d monster%s reel."
			% [pt.name, targets.size(), "s" if targets.size() != 1 else ""], pt.colour)
	events.emit("pet_ability", {"pet": pt.name, "species": pt.species, "ability": "Ear-Splitting Squawk"})


## (S8 range, world.py 734; pulled forward.)
func pet_dirty_trick(target: Monster) -> void:
	var pt := pet
	pt.cooldown = Entities.pets()[pt.species]["cooldown"]
	events.emit("pet_ability", {"pet": pt.name, "species": pt.species, "ability": "Dirty Trick"})
	pet_attack(target, 3, "sneak-stabs")


## (S8 range, world.py 740; pulled forward.)
func pet_flees() -> void:
	events.emit("pet_flee", {"pet": pet.name, "species": pet.species})


## (S8 range, world.py 743; pulled forward.)
func monster_attack_pet(monster: Monster) -> bool:
	var pt := pet
	var res := Combat.attack(monster, pt, rng)
	if not res.hit:
		return false
	messages.add("%s hits %s for %d." % [monster.The, pt.name, res.damage], GameConfig.DANGER)
	if res.killed:
		pt.downed = true
		if combat != null:
			combat.remove(pt)
		messages.add("%s is down! Revive them in a safe room." % pt.name, GameConfig.DANGER)
		events.emit("pet_downed", {"pet": pt.name, "species": pt.species, "depth": depth})
	return true


# --- S7 (attacks, kills, drops, Acts, combat mode, opportunity attacks, turn flow) ----
# world.py lines 1084-1557 (_end_combat sits above, from S6). Combat first.

## Cached chase distance map for Ai.chase_map: [floor, x, y, dist], empty until first used.
var _chase_cache: Array = []


func _player_attack(target: Monster) -> bool:
	var p := player
	var chance := Combat.hit_chance(p, target)
	var small := not target.boss and target.max_hp <= Practice.SMALL_MONSTER_HP
	var bonus: int = PyMath.floordiv(practice("stomping"), 2) if small else 0
	var mult: float = 1 + 0.03 * practice("giant_killer") if target.boss else 1
	var res := Combat.attack(p, target, rng, mult, false, bonus)
	events.emit("player_attack", {"target": target.key, "chance": chance, "hit": res.hit,
			"crit": res.crit, "small": small, "boss": target.boss, "roll": res.roll})
	if not res.hit:
		messages.add("You miss %s. (%s)" % [target.the, res.dice_text()], GameConfig.TEXT_DIM)
		_announce_natural(res, target)
		_engage([target])
		return false
	var crit_text := "CRITICAL! " if res.crit else ""
	messages.add("%sYou hit %s for %d. (%s)" % [crit_text, target.the, res.damage, res.dice_text()])
	_announce_natural(res, target)
	events.emit("player_hit", {"target": target.key, "damage": res.damage, "crit": res.crit})
	_after_hit(target, "melee")
	_engage([target])
	return true


## Natural 20s and 1s get their own event, so the System can react.
func _announce_natural(res: AttackResult, foe: Monster, by_player: bool = true) -> void:
	if res.natural() != "":
		var kind: String
		if by_player:
			kind = "nat20" if res.roll == 20 else "nat1"
		else:
			kind = "foe_nat20" if res.roll == 20 else "foe_nat1"
		events.emit(kind, {"foe": foe.the, "Foe": foe.The})


## Kill the monster if it's dead, otherwise check for a boss phase change.
func _after_hit(target: Monster, by: String) -> void:
	if not monsters.has(target):
		return
	if not target.alive:
		_kill_monster(target, by)
	elif target.tier == "headliner" and target.phase == 1 and target.hp <= PyMath.floordiv(target.max_hp, 2) \
			and PyMath.truthy(Content.boss(Bosses.boss_depth(target)).get("final")):
		_boss_phase_two(target)


func _boss_phase_two(boss: Monster) -> void:
	boss.phase = 2
	boss.dmg_bonus += Bosses.PHASE_TWO["damage_bonus"]
	boss.ranged = Bosses.PHASE_TWO["ranged"]
	var taken := {}
	for m in monsters:
		taken[Vector2i(m.x, m.y)] = true
	taken[Vector2i(player.x, player.y)] = true
	if active_pet != null:
		taken[Vector2i(pet.x, pet.y)] = true
	var spots: Array = []
	for n in DungeonFloor.NEIGHBOURS_8:
		var sx := boss.x + n.x
		var sy := boss.y + n.y
		if floor.walkable(sx, sy) and not floor.is_safe(sx, sy) and not taken.has(Vector2i(sx, sy)):
			spots.append(Vector2i(sx, sy))
	var adds: Array = Bosses.PHASE_TWO["adds"]
	for i in range(mini(adds.size(), spots.size())):
		var add := Entities.spawn_monster(adds[i], spots[i].x, spots[i].y)
		add.alerted = true
		monsters.append(add)
	messages.add("%s roars: 'Security! Get me SECURITY!'" % boss.name, GameConfig.DANGER)
	events.emit("boss_phase", {"boss": boss.name, "phase": 2})


func _kill_monster(target: Monster, by: String) -> void:
	var p := player
	monsters.erase(target)
	leave_combat(target)
	p.kills += 1
	if not floor_stats.is_empty():
		floor_stats[-1]["kills"] += 1
	var gold_amount: float = target.xp_value * GameConfig.GOLD_PER_XP * loot_rng.uniform(0.6, 1.4) \
			* Contracts.effect(self, "gold_mult") * (2 if target.tier == "headliner" else 1) \
			* (1 + 0.05 * practice("pickpocketing"))
	messages.add("%s dies. +%d gold." % [target.The, _earn_gold(gold_amount, "kill")], GameConfig.GOOD)
	events.emit("kill", {"monster": target.key, "monster_name": target.name, "xp": target.xp_value,
			"style": weapon_style() if by == "melee" else by,
			"boss": target.boss, "small": not target.boss and target.max_hp <= Practice.SMALL_MONSTER_HP,
			"depth": depth, "turn": turn, "by": by,
			"player_hp": p.hp, "player_max_hp": p.max_hp})
	var pt := active_pet
	if pt != null:
		if by == "pet":
			pt.kills += 1
			events.emit("pet_kill", {"pet": pt.name, "species": pt.species,
					"monster_name": target.name, "boss": target.boss})
		for level in pt.gain_xp(target.xp_value if by == "pet" else PyMath.floordiv(target.xp_value, 2)):
			messages.add("%s is now level %d." % [pt.name, level], pt.colour)
			events.emit("pet_level_up", {"pet": pt.name, "species": pt.species, "level": level})
	if target.tier == "headliner":
		var b: Dictionary = Content.boss(Bosses.boss_depth(target))
		events.emit("boss_kill", {"boss": target.name, "depth": depth})
		if PyMath.truthy(b.get("final")):
			exit_sealed = false
			messages.add("The exits unseal. Get out!", GameConfig.GOOD)
		else:
			has_key = true
			messages.add("%s drops a stairwell key. The stairs are open to you." % target.name,
					GameConfig.ACCENT)
		_drop(target, loot_rng.choice(GameConfig.HEADLINER_DROPS))
	elif target.tier != "":
		_act_reward(target)
	if not target.boss and loot_rng.random() < GameConfig.ITEM_DROP_CHANCE:
		_drop(target, loot_rng.choice(Entities.monsters()[target.key]["drops"]))
	var levels := p.gain_xp(target.xp_value)
	if not levels.is_empty():
		refresh_stats()
	for level in levels:
		messages.add("Level up! You are now level %d. Spend your attribute points with L (%d to spend)."
				% [level, p.stat_points], GameConfig.ACCENT)
		events.emit("level_up", {"level": level})


func _drop(where: Entity, key: String) -> void:
	var at := Vector2i(where.x, where.y)
	if not floor_items.has(at):
		floor_items[at] = []
	floor_items[at].append(key)


## Opening Acts drop a map of the area; Featured Acts drop a better haul.
func _act_reward(act: Monster) -> void:
	events.emit("act_kill", {"tier": act.tier, "monster_name": act.name, "depth": depth})
	if act.tier == "opening":
		var f := floor
		for y in range(maxi(0, act.y - Bosses.MAP_RADIUS), mini(f.height, act.y + Bosses.MAP_RADIUS + 1)):
			for x in range(maxi(0, act.x - Bosses.MAP_RADIUS), mini(f.width, act.x + Bosses.MAP_RADIUS + 1)):
				var mark: bool = f.tiles[y][x] != 0
				if not mark:
					for n in DungeonFloor.NEIGHBOURS_8:
						if f.in_bounds(x + n.x, y + n.y) and f.tiles[y + n.y][x + n.x] != 0:
							mark = true
							break
				if mark:
					f.explored[y][x] = 1
		messages.add("%s drops a map. The area around you is marked out." % act.name, GameConfig.INFO)
		events.emit("map_found", {"depth": depth})
	else:
		var table := Items.floor_loot_table(mini(GameConfig.NUM_FLOORS, depth + 2))
		var keys: Array = table[0]
		var weights: Array = table[1]
		for _i in range(2):
			_drop(act, loot_rng.choices(keys, weights)[0])
		messages.add("%s leaves behind a haul. Press G to collect." % act.name, GameConfig.ACCENT)


## A monster swings at you (ranged: shoots). Returns true when it hit. A riposte eats the attack.
func monster_attack(monster: Monster, ranged: bool = false) -> bool:
	var p := player
	if riposte != 0:
		riposte -= 1
		messages.add("You parry %s!" % monster.the, GameConfig.INFO)
		if not ranged and Ai.cheb(monster, p) == 1:
			var rres := Combat.attack(p, monster, rng)
			if rres.hit:
				messages.add("Riposte! %s takes %d. (%s)" % [monster.The, rres.damage, rres.dice_text()],
						GameConfig.ACCENT)
				_after_hit(monster, "skill")
		events.emit("riposte", {"monster": monster.key})
		return false
	var res := Combat.attack(monster, p, rng)
	var how := "shoots" if ranged else "hits"
	if not res.hit:
		messages.add("%s %smisses you. (%s)" % [monster.The, "shoots and " if ranged else "", res.dice_text()],
				GameConfig.TEXT_DIM)
		_announce_natural(res, monster, false)
		events.emit("dodged", {"source": monster.key})
		return false
	var crit_text := "CRITICAL! " if res.crit else ""
	messages.add("%s%s %s you for %d. (%s)" % [crit_text, monster.The, how, res.damage, res.dice_text()],
			GameConfig.DANGER)
	_announce_natural(res, monster, false)
	floor_stats[-1]["damage_taken"] += res.damage
	events.emit("damage_taken", {"source": monster.key, "damage": res.damage, "hp": p.hp,
			"ranged": ranged})
	if res.killed:
		_kill_player("Killed by %s on floor %d" % [monster.a, depth])
	return true


func _kill_player(cause: String) -> void:
	_close_floor_stats()
	state = "dead"
	death_cause = cause
	_end_combat("death")
	messages.add(cause + ".", GameConfig.DANGER)
	events.emit("player_death", {"cause": cause, "depth": depth, "turn": turn})


# --- Turn flow ------------------------------------------------------------------

func _on_enter_tile() -> void:
	var safe := in_safe_room
	if safe:
		_end_combat("safe_room")
	if safe and not _was_safe:
		messages.add("Safe room. No combat allowed in here. R rests, M opens the menu.", GameConfig.GOOD)
		if PyMath.truthy(get_trait("photosynthesis")) and _plant_fed_floor != depth:
			_plant_fed_floor = depth
			var healed := player.heal(player.max_hp)
			if healed != 0:
				messages.add("The grow lights restore %d HP. Bliss." % healed, GameConfig.GOOD)
	_was_safe = safe
	var here: Variant = floor_items.get(Vector2i(player.x, player.y))
	if here != null and not (here as Array).is_empty():
		var names := PackedStringArray()
		for k in here:
			names.append(Items.items()[k]["name"])
		messages.add("You see: %s. Press G to pick up." % ", ".join(names), GameConfig.TEXT_DIM)
	if on_stairs:
		messages.add("A stairwell down. Press > or Enter to descend.", GameConfig.ACCENT)


## One turn of the clock: regeneration, cooldowns, stairs unlock, respawns, collapse warnings.
func _tick_clock() -> void:
	_acted.clear()                          # a tick closes the round
	turn += 1
	timer -= 1
	events.emit("turn", {"turn": turn})
	var p := player
	var regen_div: int = get_trait("regen_mult", 1)
	if PyMath.mod(turn, maxi(2, PyMath.floordiv(GameConfig.REGEN_INTERVAL - mod("con"), regen_div))) == 0:
		p.heal(1)
	if PyMath.mod(turn, GameConfig.REGEN_INTERVAL) == 0 and active_pet != null:
		pet.heal(1)
	if hype_turns != 0:
		hype_turns -= 1
	if pet != null and pet.enraged != 0:
		pet.enraged -= 1
	if skill_cooldown != 0:
		skill_cooldown -= 1
	if scout_turns != 0:
		scout_turns -= 1
	if not _stairs_announced and stairs_wait == 0:
		_stairs_announced = true
		messages.add("The stairwells have unlocked. Clock's still ticking.", GameConfig.ACCENT)
		events.emit("stairs_open", {"depth": depth, "timer_left": timer})
	if turn >= _next_spawn:
		_respawn()
	while not _warnings_left.is_empty() and timer <= _warnings_left[0] * timer_max:
		_warnings_left.pop_front()
		messages.add("WARNING: floor collapse in %s." % timer_text(), GameConfig.DANGER)
		events.emit("timer_warning", {"timer_left": timer})
	if timer <= 0:
		_kill_player("Crushed when floor %d collapsed" % depth)


## Out of combat: the pet, the monsters and the clock each take their turn. In combat this ends
## your turn and plays out the rest of the round.
func end_turn() -> void:
	if combat != null:
		_finish_round()
		return
	# FOV depends only on the player's position, so one update per turn
	# (before monsters act, since sight is what alerts them) is enough.
	update_fov()
	if pet == null or not _acted.has(pet):      # it may have had its go before a fight ended
		Ai.take_pet_turn(self)
	Ai.take_monster_turns(self)
	if state == "playing":
		_tick_clock()
	_begin_round()                              # a monster noticed you: the fight starts


# --- Combat mode ----------------------------------------------------------------

## Whether this part of your turn (move, action, bonus) is still free; refuses with a log line if
## not. Always true out of combat.
func _can_spend(part: String) -> bool:
	var enc := combat
	if enc == null or enc.has(part):
		return true
	messages.add("You've used your %s this turn. Space ends your turn." % Encounter.PART_NAMES[part],
			GameConfig.TEXT_DIM)
	return false


## Every player act that takes time goes through here. Out of combat (or if the fight just ended)
## it is a whole turn; in combat it spends one part of your turn, which ends once the move and the
## action are both gone.
func _spend(part: String) -> void:
	var enc := combat
	if enc == null:
		end_turn()
		return
	enc.spend(part)
	update_fov()
	if enc.turn_over:
		end_turn()


## Roll d20 + modifier for a combatant and place it in the order; returns log text.
func _roll_initiative(ent: Entity) -> String:
	var face: int = Dice.d20(rng)[0]
	var who: String
	var bonus: int
	var key: String
	if is_same(ent, player):
		who = "you"
		bonus = mod("dex")
		key = "player"
	else:
		who = ent.name
		bonus = Entities.init_mod(ent)
		key = (ent as Monster).key if not is_same(ent, pet) else (ent as Pet).species
	combat.add(ent, face, bonus)
	events.emit("initiative", {"who": who, "monster": key, "roll": face, "bonus": bonus,
			"total": face + bonus})
	if bonus != 0:
		return "%s %d%s=%d" % [who, face, PyFmt.signed_int(bonus), face + bonus]
	return "%s %d" % [who, face]


func _start_combat(fighters: Array, by: String) -> Encounter:
	var enc := Encounter.new(player)
	combat = enc
	events.emit("combat_start", {"by": by, "monsters": fighters.size(), "depth": depth, "turn": turn})
	var rolls: Array = [_roll_initiative(player)]
	if active_pet != null:
		rolls.append(_roll_initiative(pet))
	for m in fighters:
		rolls.append(_roll_initiative(m))
	messages.add("COMBAT! Initiative: " + ", ".join(PackedStringArray(rolls)) + ".", GameConfig.ACCENT)
	# A monster starts the fight just before the clock ticks: stamp the banner with the
	# turn your first combat turn falls on, so it shows for two of your rounds either way.
	add_toast("COMBAT: roll for initiative", "combat", null, turn + (1 if by == "monster" else 0))
	return enc


## A monster has noticed you: start combat, or roll it into the current one. Never while you stand
## in a safe room. Returns true if the monster is now fighting.
func join_combat(monster: Monster) -> bool:
	if state != "playing" or in_safe_room or not monsters.has(monster):
		return false
	monster.alerted = true                      # anything in a fight is after you
	if combat == null:
		_start_combat([monster], "monster")
	elif not combat.has_entity(monster):
		var text := _roll_initiative(monster)
		messages.add("%s joins the fight. Initiative: %s." % [monster.The, text], GameConfig.DANGER)
	return true


## You attacked, bombed or zapped these monsters. Out of combat this starts a fight in which that
## attack is your first turn's action; in combat they join if they weren't in it already.
func _engage(targets: Array) -> void:
	var live: Array = []
	for m in targets:
		if monsters.has(m) and m.alive:
			live.append(m)
	if live.is_empty() or state != "playing" or in_safe_room:
		return
	for m in live:
		m.alerted = true
		m.unseen_turns = 0
	if combat == null:
		var enc := _start_combat(live, "player")
		enc.round = 1                               # your turn, right now
	else:
		for m in live:
			join_combat(m)


## A monster is dead or has lost track of you; the fight ends when nobody in it is alive and alerted.
func leave_combat(monster: Monster) -> void:
	var enc := combat
	if enc == null or not enc.has_entity(monster):
		return
	enc.remove(monster)
	if not _hold_combat:
		_check_combat_over("cleared" if not monster.alive else "lost_track")


## End the fight once no monster is alive and alerted, counting those still on their way to join
## it (alerted within chase range: phase-two adds, respawns).
func _check_combat_over(reason: String) -> void:
	var enc := combat
	var p := player
	if enc == null:
		return
	for m in monsters:
		if m.alerted and (enc.has_entity(m) or Ai.cheb(m, p) <= Ai.CHASE_RADIUS):
			return
	_end_combat(reason)


# --- Attacks of opportunity -----------------------------------------------------

func _can_react(ent: Entity) -> bool:
	var enc := combat
	var stunned := (ent as Monster).stunned if ent is Monster else 0
	return (enc != null and enc.can_react(ent) and stunned == 0
			and (not is_same(ent, pet) or active_pet != null)
			and (monsters.has(ent) or not (ent is Monster)))


## Hostile fighters next to you that still have their reaction: stepping out of their reach (other
## than by swapping with your pet) provokes an attack of opportunity. Empty once your move is spent
## (you can't step anyway) or across a safe-room edge.
func threats() -> Array:
	var enc := combat
	var p := player
	var f := floor
	var out: Array = []
	if enc == null or not enc.has("move") or f.is_safe(p.x, p.y):
		return out
	for m in enc.monsters:
		if Ai.cheb(m, p) == 1 and _can_react(m) and not f.is_safe(m.x, m.y):
			out.append(m)
	return out


## The monsters that would get an attack of opportunity if you stepped (dx, dy).
func provokers(dx: int, dy: int) -> Array:
	var p := player
	var nx := p.x + dx
	var ny := p.y + dy
	var out: Array = []
	if (dx == 0 and dy == 0) or monster_at(nx, ny) != null or pet_at(nx, ny) != null \
			or not floor.walkable(nx, ny) or floor.is_safe(nx, ny):
		return out
	for m in threats():
		if maxi(absi(m.x - nx), absi(m.y - ny)) > 1:
			out.append(m)
	return out


## mover (you, your pet or a monster in the fight) steps to (nx, ny): everyone hostile it leaves
## the reach of, with a reaction left, gets one melee attack first (ranged attacks never count).
## Returns false if the mover is no longer able to move.
func opportunity_attacks(mover: Entity, nx: int, ny: int) -> bool:
	var enc := combat
	var p := player
	var f := floor
	if enc == null or not enc.has_entity(mover):
		return true
	if f.is_safe(mover.x, mover.y) or f.is_safe(nx, ny):
		return true                     # no attacks into or out of safe rooms
	var pt := active_pet

	var leaving := func(a: Entity) -> bool:
		return (Ai.cheb(a, mover) == 1 and maxi(absi(a.x - nx), absi(a.y - ny)) > 1
				and not f.is_safe(a.x, a.y))

	var attackers: Array = []
	if is_same(mover, p) or is_same(mover, pt):
		for m in enc.monsters:
			if leaving.call(m) and _can_react(m):
				attackers.append(m)
	else:
		for e in [p, pt]:
			if e != null and leaving.call(e) and _can_react(e):
				attackers.append(e)
	for a in attackers:
		if not _able(mover):
			break
		enc.react(a)
		var hit: bool
		if is_same(a, p):
			messages.add("Attack of opportunity: you swing at %s as it pulls away." % (mover as Monster).the,
					GameConfig.WARN)
			hit = _player_attack(mover)
		elif is_same(a, pt):
			messages.add("Attack of opportunity: %s snaps at %s." % [pt.name, (mover as Monster).the],
					GameConfig.WARN)
			hit = pet_attack(mover)
		elif is_same(mover, p):
			messages.add("Attack of opportunity: %s lashes out as you pull away." % (a as Monster).the,
					GameConfig.WARN)
			hit = monster_attack(a)
		else:
			messages.add("Attack of opportunity: %s lashes out at %s." % [(a as Monster).the, pt.name],
					GameConfig.WARN)
			hit = monster_attack_pet(a)
		events.emit("opportunity_attack", {"attacker": _who(a), "target": _who(mover), "hit": hit})
	return _able(mover)


func _who(ent: Entity) -> String:
	if is_same(ent, player):
		return "player"
	if is_same(ent, pet):
		return "pet"
	return (ent as Monster).key


func _able(ent: Entity) -> bool:
	if is_same(ent, player):
		return state == "playing"
	if is_same(ent, pet):
		return active_pet != null and state == "playing"
	return monsters.has(ent) and state == "playing"


func _combat_act(ent: Entity) -> void:
	_acted[ent] = true
	combat.ready(ent)                   # its reaction comes back as its turn starts
	if is_same(ent, pet):
		if active_pet != null:
			Ai.take_pet_turn(self, true)
		else:
			combat.remove(ent)
	else:
		Ai.take_combat_turn(self, ent)


## Your turn is over: the fighters after you act, then everything not in the fight, then the clock
## ticks (one round is one turn) and the next round begins.
func _finish_round() -> void:
	var enc := combat
	update_fov()
	for ent in enc.after(player):
		if not is_same(combat, enc) or state != "playing":
			break
		if enc.has_entity(ent):
			_combat_act(ent)
	if state != "playing":
		return
	Ai.take_monster_turns(self)             # monsters outside the fight act as before
	if state == "playing":
		_tick_clock()
	_begin_round()


## Start the next round: the fighters ahead of you act, then your turn begins.
func _begin_round() -> void:
	_check_combat_over("lost_track")        # e.g. the last alerted outsider gave up
	var enc := combat
	if enc == null or state != "playing":
		return
	enc.round += 1
	for ent in enc.before(player):
		if not is_same(combat, enc) or state != "playing":
			return
		if enc.has_entity(ent):
			_combat_act(ent)
	if is_same(combat, enc):
		enc.reset_budget()
		enc.ready(player)
		update_fov()


# --- S8 (move, wait, descend, rest, safe room, craft, shop, pet, class skills, items, bombs, boxes) ----
# world.py lines 468-1080 (add_box, choose_class, equip, move_player, wait and the pet methods sit above).

## Take the stairs down (or win on the last floor). Needs open stairs and a free action.
func descend() -> bool:
	if state != "playing":
		return false
	if not on_stairs:
		messages.add("There are no stairs here.", GameConfig.TEXT_DIM)
		return false
	if exit_sealed:
		messages.add("The exit is sealed. Defeat %s first." % Content.boss(depth)["name"], GameConfig.DANGER)
		return false
	if stairs_locked:
		messages.add("The stairwell is locked for another %s. The Headliner has a key." % timer_text(stairs_wait),
				GameConfig.DANGER)
		return false
	if not _can_spend("action"):
		return false
	events.emit("descend", {"depth": depth, "turn": turn, "timer_left": timer, "timer_max": timer_max,
			"early": depth < GameConfig.NUM_FLOORS and stairs_wait > 0})
	_close_floor_stats()
	if depth >= GameConfig.NUM_FLOORS:
		state = "victory"
		_end_combat("victory")
		_close_floor_stats()
		messages.add("You escaped the final floor!", GameConfig.GOOD)
		events.emit("victory", {"depth": depth, "turn": turn})
	else:
		new_floor(depth + 1)
	return true


## Heal to full in a safe room, spending floor time to do it.
func rest() -> bool:
	if state != "playing":
		return false
	if not in_safe_room:
		messages.add("You can only rest in a safe room.", GameConfig.TEXT_DIM)
		return false
	var p := player
	if p.hp >= p.max_hp:
		messages.add("You're already at full health.", GameConfig.TEXT_DIM)
		return false
	if combat != null:                          # can't happen (safe rooms end fights), but be sure
		messages.add("Not while you're fighting.", GameConfig.DANGER)
		return false
	if timer <= GameConfig.REST_MIN_TIMER:
		messages.add("No time to rest. The floor is coming down!", GameConfig.DANGER)
		return false
	var start_hp := p.hp
	var start_turn := turn
	var per_turn: float = (float(Contracts.effect(self, "rest_mult")) * float(get_trait("rest_mult", 1))
			* (1 + 0.1 * practice("power_napping")))
	var owed := 0.0
	while p.hp < p.max_hp and timer > GameConfig.REST_MIN_TIMER and state == "playing":
		owed += per_turn
		p.heal(int(owed))
		owed -= int(owed)
		_tick_clock()
	var spent := turn - start_turn
	if active_pet != null:
		pet.hp = pet.max_hp
	messages.add("You rest for %s and recover %d HP." % [timer_text(spent), p.hp - start_hp], GameConfig.GOOD)
	events.emit("rest", {"turns": spent, "healed": p.hp - start_hp})
	update_fov()
	return true


## Pass time without monsters acting (safe-room activities).
func _spend_turns(n: int) -> void:
	if combat != null:                          # safe rooms end fights; never tick past one
		return
	for _i in range(n):
		if state != "playing":
			return
		_tick_clock()


func _safe_room_activity_ok(turns: int) -> bool:
	if state != "playing":
		return false
	if combat != null:
		messages.add("Not while you're fighting.", GameConfig.DANGER)
		return false
	if not in_safe_room:
		messages.add("You can only do that in a safe room.", GameConfig.TEXT_DIM)
		return false
	if timer <= turns + GameConfig.REST_MIN_TIMER:
		messages.add("No time for that. The floor is coming down!", GameConfig.DANGER)
		return false
	return true


## Craft recipe Crafting.recipes()[index] at the safe-room bench.
func craft(index: int) -> bool:
	var recipe: Dictionary = Crafting.recipes()[index]
	var turns := maxi(1, PyMath.round_half_even(Crafting.CRAFT_TURNS * float(get_trait("craft_mult", 1))
			* (1 - 0.08 * practice("tinkering"))))
	if not _safe_room_activity_ok(turns):
		return false
	if not Crafting.can_craft(recipe, inventory):
		messages.add("You're missing parts for %s." % recipe["name"], GameConfig.TEXT_DIM)
		return false
	for key in recipe["needs"]:
		inventory.erase(key)
	inventory.append(recipe["makes"])
	if (loot_rng.random() < 0.04 * practice("tinkering")
			and inventory.size() < GameConfig.INVENTORY_SIZE):
		inventory.append(recipe["makes"])
		messages.add("Tinkering pays off: you get a spare.", GameConfig.GOOD)
	_spend_turns(turns)
	messages.add("You craft %s: %s." % [recipe["name"], Items.items()[recipe["makes"]]["name"]], GameConfig.GOOD)
	events.emit("craft", {"recipe": recipe["key"], "item": recipe["makes"]})
	return true


# --- Shop ---

## Buy one of `key` from the shop (safe room, or the Supply Drop crate).
func shop_buy(key: String) -> bool:
	if not _in_safe_room_msg():
		return false
	var price := buy_price(key)
	if gold < price:
		messages.add("You need %d gold for that." % price, GameConfig.TEXT_DIM)
		return false
	if inventory.size() >= GameConfig.INVENTORY_SIZE:
		messages.add("Your pack is full.", GameConfig.DANGER)
		return false
	if shop.buy(key) == "":
		messages.add("Sold out of %s." % Items.items()[key]["name"], GameConfig.DANGER)
		events.emit("shop_sold_out", {"item": key, "depth": depth})
		return false
	gold -= price
	inventory.append(key)
	if not in_safe_room:
		remote_shop = false                     # Supply Drop is good for one purchase
	messages.add("You buy a %s for %d gold." % [Items.items()[key]["name"], price], GameConfig.GOOD)
	events.emit("shop_buy", {"item": key, "price": price, "depth": depth})
	return true


## Sell inventory item `index` to the shop (safe rooms only).
func shop_sell(index: int) -> bool:
	if not in_safe_room or not _in_safe_room_msg() or not (0 <= index and index < inventory.size()):
		return false
	var key: String = inventory.pop_at(index)
	var price := sell_price(key)
	gold += price
	shop.take_back(key)
	messages.add("You sell the %s for %d gold." % [Items.items()[key]["name"], price], GameConfig.TEXT_DIM)
	events.emit("shop_sell", {"item": key, "price": price, "depth": depth,
			"item_kind": Items.items()[key]["kind"]})
	return true


func _in_safe_room_msg() -> bool:
	if state != "playing":
		return false
	if not in_safe_room and not remote_shop:
		messages.add("The shop is only open in safe rooms.", GameConfig.TEXT_DIM)
		return false
	return true


# --- Companion ---

## Cycle the pet's mode. Free action.
func command_pet() -> bool:
	var pt := pet
	if pt == null:
		return false
	pt.mode = PET_MODES[PyMath.mod(PET_MODES.find(pt.mode) + 1, PET_MODES.size())]
	var what: String = {"follow": "will follow you and defend itself",
			"attack": "will hunt anything you can see",
			"stay": "will hold its position"}[pt.mode]
	messages.add("%s %s." % [pt.name, what], GameConfig.INFO)
	return true


## Bring a downed pet back on its feet in a safe room.
func revive_pet() -> bool:
	var pt := pet
	if pt == null or not pt.downed:
		return false
	if not _safe_room_activity_ok(GameConfig.PET_REVIVE_TURNS):
		return false
	_spend_turns(GameConfig.PET_REVIVE_TURNS)
	pt.downed = false
	pt.hp = pt.max_hp
	pt.cooldown = 0
	pt.mode = "follow"
	_place_pet()
	messages.add("%s is back on its feet and annoyed about it." % pt.name, GameConfig.GOOD)
	events.emit("pet_revived", {"pet": pt.name})
	return true


# --- Class and skills ---

## Use the class skill (key 1). Returns true when a turn was used.
func use_skill() -> bool:
	if state != "playing":
		return false
	if not PyMath.truthy(cls):
		messages.add("You get a class on floor %d." % CHOICE_FLOOR, GameConfig.TEXT_DIM)
		return false
	var key: String = skill
	var spec: Dictionary = Content.skill(key)
	if skill_cooldown != 0:
		messages.add("%s is recharging (%d turns)." % [spec["name"], skill_cooldown], GameConfig.TEXT_DIM)
		return false
	if not _can_spend("action"):
		return false
	if key in ["haymaker", "arc_bolt", "pocket_popper", "riposte"] and in_safe_room:
		messages.add("The System forbids violence in safe rooms.", GameConfig.TEXT_DIM)
		return false
	var p := player
	if key == "haymaker":
		var adjacent: Array = []
		for m in monsters:
			if Ai.cheb(m, p) == 1:
				adjacent.append(m)
		if adjacent.is_empty():
			messages.add("Nobody close enough to punch.", GameConfig.TEXT_DIM)
			return false
		var target: Monster = PyMath.min_by(adjacent, func(m: Monster) -> int: return m.hp)
		var res := Combat.attack(p, target, rng, 2, true)
		messages.add("HAYMAKER! %s takes %d (%s, doubled)." % [target.The, res.damage,
				Dice.fmt(p.dmg_n, p.dmg_die, p.dmg_bonus)], GameConfig.ACCENT)
		_after_hit(target, "skill")
		_engage([target])
	elif key == "arc_bolt":
		var seen: Array = []
		for m in monsters:
			if visible.has(Vector2i(m.x, m.y)) and Ai.cheb(m, p) <= spec["range"]:
				seen.append(m)
		if seen.is_empty():
			messages.add("No target in range.", GameConfig.TEXT_DIM)
			return false
		var target: Monster = PyMath.min_by(seen, func(m: Monster) -> int: return Ai.cheb(m, p))
		var dmg := target.take_damage(maxi(1, 6 + 2 * p.level + mod("int")))
		messages.add("Arc Bolt crackles into %s for %d." % [target.the, dmg], GameConfig.INFO)
		_after_hit(target, "skill")
		_engage([target])
	elif key == "scout_report":
		scout_turns = spec["duration"]
		messages.add("Scout Report: odds are on the panel for the next 20 turns.", GameConfig.INFO)
	elif key == "field_brew":
		var junk: Array = []
		for i in range(inventory.size()):
			if Items.items()[inventory[i]]["kind"] == "junk":
				junk.append(i)
		if junk.is_empty():
			messages.add("No junk to brew with. Even you have standards.", GameConfig.TEXT_DIM)
			return false
		var old: String = inventory.pop_at(junk[0])
		var made: String = loot_rng.choices(["tonic", "brew", "elixir"], [6, 3, 1])[0]
		inventory.append(made)
		messages.add("You brew the %s into a %s. Don't think about it."
				% [Items.items()[old]["name"], Items.items()[made]["name"]], GameConfig.GOOD)
	elif key == "rile_up":
		var pt := active_pet
		if pt == null:
			messages.add("You have nobody to rile up.", GameConfig.TEXT_DIM)
			return false
		pt.enraged = spec["duration"]
		messages.add("%s is FURIOUS. Double damage for %d turns." % [pt.name, spec["duration"]], pt.colour)
	elif key == "crowd_work":
		hype_turns = spec["duration"]
		messages.add("You work the crowd. Kills earn triple viewers for 10 turns.", GameConfig.ACCENT)
	elif key == "pocket_popper":
		var target: Variant = _bomb_target(spec["range"])
		if target == null:
			return false
		_explode("popper", target)
	elif key == "supply_drop":
		remote_shop = true
		if inventory.size() < GameConfig.INVENTORY_SIZE:
			inventory.append("tonic")
		messages.add("A sponsor drone lowers a shop crate, with a free Fizzy Tonic taped to the lid. One purchase, then it leaves.",
				GameConfig.ACCENT)
	elif key == "riposte":
		riposte = spec["charges"]
		messages.add("En garde. You'll parry the next %d attacks." % spec["charges"], GameConfig.INFO)
	skill_cooldown = maxi(PyMath.floordiv(spec["cooldown"], 2), spec["cooldown"] - mod("int"))
	events.emit("skill", {"skill": key})
	_spend("action")
	return true


# --- Items ---

## Pick up everything on the player's tile that fits in the pack.
func pickup() -> bool:
	if state != "playing":
		return false
	var where := Vector2i(player.x, player.y)
	var here: Variant = floor_items.get(where)
	if here == null or (here as Array).is_empty():
		messages.add("Nothing here to pick up.", GameConfig.TEXT_DIM)
		return false
	if not _can_spend("action"):
		return false
	var took := false
	while not (here as Array).is_empty() and inventory.size() < GameConfig.INVENTORY_SIZE:
		var key: String = (here as Array).pop_front()
		inventory.append(key)
		took = true
		messages.add("You pick up the %s." % Items.items()[key]["name"])
		events.emit("item_pickup", {"item": key})
	if (here as Array).is_empty():
		floor_items.erase(where)
	if not took:
		messages.add("Your pack is full.", GameConfig.DANGER)
		return false
	_spend("action")
	return true


## Drop inventory item `index` on the player's tile. Free action.
func drop(index: int) -> bool:
	if state != "playing" or not (0 <= index and index < inventory.size()):
		return false
	var key: String = inventory.pop_at(index)
	var where := Vector2i(player.x, player.y)
	if not floor_items.has(where):
		floor_items[where] = []
	floor_items[where].append(key)
	messages.add("You drop the %s." % Items.items()[key]["name"], GameConfig.TEXT_DIM)
	events.emit("item_drop", {"item": key})
	return true


## Take off whatever is in `slot` and put it in the pack.
func unequip(slot: String) -> bool:
	var key: Variant = equipment.get(slot)
	if state != "playing" or not PyMath.truthy(key) or inventory.size() >= GameConfig.INVENTORY_SIZE:
		return false
	equipment[slot] = null
	inventory.append(key)
	refresh_stats()
	events.emit("unequip", {"slot": slot, "item": key})
	return true


## Equip, drink or throw an item. Returns true if it took a turn.
func use_item(index: int) -> bool:
	if state != "playing" or not (0 <= index and index < inventory.size()):
		return false
	var key: String = inventory[index]
	var item: Dictionary = Items.items()[key]
	var kind: String = item["kind"]
	if equipment.has(kind):
		equip(index)
		return false
	if kind == "junk":
		messages.add("The %s is junk. Drop it." % item["name"], GameConfig.TEXT_DIM)
		return false
	var part := "bonus" if kind == "potion" else "action"
	if kind == "potion":
		var p := player
		if p.hp >= p.max_hp:
			messages.add("You're already at full health.", GameConfig.TEXT_DIM)
			return false
		if not _can_spend(part):
			return false
		inventory.pop_at(index)
		var healed := p.heal(PyMath.round_half_even(item["heal"] * float(get_trait("potion_mult", 1))
				* float(get_trait("class_potion_mult", 1))
				* (1 + 0.08 * practice("first_aid"))
				* (1 + 0.05 * mod("int"))))
		messages.add("You drink the %s and recover %d HP." % [item["name"], healed], GameConfig.GOOD)
		events.emit("item_use", {"item": key, "healed": healed})
	else:
		if not _can_spend(part) or not _throw_bomb(index):
			return false
	_spend(part)
	return true


func _throw_bomb(index: int) -> bool:
	if in_safe_room:
		messages.add("The System forbids explosions in safe rooms.", GameConfig.TEXT_DIM)
		return false
	var target: Variant = _bomb_target(GameConfig.BOMB_RANGE)
	if target == null:
		return false
	_explode(inventory.pop_at(index), target)
	return true


## The nearest visible monster within `reach` (first on ties), or null with a log line.
func _bomb_target(reach: int) -> Variant:
	var p := player
	var seen: Array = []
	for m in monsters:
		if visible.has(Vector2i(m.x, m.y)) and Ai.cheb(m, p) <= reach:
			seen.append(m)
	if seen.is_empty():
		messages.add("No target in range.", GameConfig.TEXT_DIM)
		return null
	return PyMath.min_by(seen, func(m: Monster) -> int: return Ai.cheb(m, p))


func _explode(key: String, target: Monster) -> void:
	var item: Dictionary = Items.items()[key]
	var dice: Array = item["dice"]
	var damage := PyMath.round_half_even(Dice.roll(rng, dice[0], dice[1]) * float(get_trait("bomb_mult", 1))
			* (1 + 0.08 * practice("lobbing")))
	var dc := save_dc()
	messages.add("You throw the %s. BOOM: %d damage (%s). Dexterity save DC %d for half."
			% [item["name"], damage, Dice.fmt(dice[0], dice[1]), dc], GameConfig.ACCENT)
	var killed := 0
	var hit: Array = []
	_hold_combat = true         # a blast that kills the last fighter but catches a
	for m in monsters.duplicate():  # bystander carries on the same fight
		if Ai.cheb(m, target) <= item["radius"]:
			var st := Combat.saving_throw(rng, m.save, dc)
			var saved: bool = st[0]
			var face: int = st[1]
			var dealt: int = m.take_damage(maxi(1, PyMath.floordiv(damage, 2)) if saved else damage)
			if saved:
				messages.add("%s dives aside (d20 %d%s vs DC %d) and takes %d."
						% [m.The, face, PyFmt.signed_int(m.save), dc, dealt], GameConfig.TEXT_DIM)
			m.alerted = true
			killed += int(not m.alive)
			hit.append(m)
			_after_hit(m, "bomb")
	events.emit("bomb", {"item": key, "kills": killed})
	_engage(hit)
	_hold_combat = false
	_check_combat_over("cleared")


# --- Loot boxes ---

func _take_reason(tier: String) -> String:
	var reasons: Variant = box_reasons.get(tier)
	if reasons != null and not (reasons as Array).is_empty():
		return (reasons as Array).pop_front()
	return "A gift from the System. It won't say why."


## Open one box of this tier. Safe rooms only; needs a free pack slot.
func open_box(tier: String) -> bool:
	if state != "playing" or not boxes.has(tier):
		return false
	if not in_safe_room:
		messages.add("Loot boxes can only be opened in a safe room.", GameConfig.TEXT_DIM)
		return false
	if inventory.size() >= GameConfig.INVENTORY_SIZE:
		messages.add("Your pack is full. Drop something first.", GameConfig.DANGER)
		return false
	boxes.erase(tier)
	last_reason = _take_reason(tier)
	_reveal(tier)
	return true


func _reveal(tier: String, rerolled: bool = false) -> void:
	var key := Loot.roll_box(tier, loot_rng)
	inventory.append(key)
	last_reveal = [tier, key]
	box_log.append({"tier": tier, "item": key, "value": Items.items()[key]["value"],
			"ev": PyMath.round_n(Loot.box_stats(tier)[0], 2), "rerolled": rerolled,
			"turn": turn, "reason": last_reason if PyMath.truthy(last_reason) else ""})
	messages.add("The %s box contains: %s!" % [Content.box(tier)["name"], Items.items()[key]["name"]],
			Content.box(tier)["colour"])
	events.emit("box_opened", {"tier": tier, "item": key, "rerolled": rerolled})


## Hand back the item from the last box and roll that box again, for a fee.
func reroll() -> bool:
	if state != "playing" or not PyMath.truthy(last_reveal) or not in_safe_room:
		return false
	var tier: String = last_reveal[0]
	var key: String = last_reveal[1]
	var fee := reroll_fee(tier)
	if not inventory.has(key):
		return false
	if gold < fee:
		messages.add("A reroll costs %d gold." % fee, GameConfig.TEXT_DIM)
		return false
	gold -= fee
	inventory.erase(key)
	events.emit("box_reroll", {"tier": tier, "item": key, "fee": fee})
	_reveal(tier, true)
	return true


## Swap TRADE_UP_COST boxes of a tier for one of the next tier. Free action.
func trade_up(tier: String) -> bool:
	var up := Loot.next_tier(tier)
	if state != "playing" or up == "" or boxes.count(tier) < Loot.TRADE_UP_COST:
		return false
	if not in_safe_room:
		messages.add("Trades happen in safe rooms.", GameConfig.TEXT_DIM)
		return false
	for _i in range(Loot.TRADE_UP_COST):
		boxes.erase(tier)
		_take_reason(tier)
	boxes.append(up)
	if not box_reasons.has(up):
		box_reasons[up] = []
	box_reasons[up].append("Traded up from %d %s boxes." % [Loot.TRADE_UP_COST, Content.box(tier)["name"]])
	messages.add("Traded %d %s boxes for a %s box." % [Loot.TRADE_UP_COST, Content.box(tier)["name"],
			Content.box(up)["name"]], Content.box(up)["colour"])
	events.emit("box_trade", {"tier": tier, "to": up})
	return true

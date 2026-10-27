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
## LAYOUT (one file, three slices; see docs/port-plan.md 9.1):
##   S6 (this slice, world.py lines 1-466): state and init, traits, refresh_stats, attributes,
##       prices, floors and spawns, contracts, queries, timer_text.
##   S7 appends below the marked "S7" section: attacks, kills, drops, Acts, combat mode, opportunity
##       attacks, turn flow (world.py 1084-1557) and ai.gd.
##   S8 appends below the marked "S8" section: move, wait, descend, rest, safe-room activities,
##       craft, shop trades, pet methods, class and skills, items, bombs, boxes (world.py 468-1080).
## A few small methods from those slices are already here because S6 code or the S6 tests need them
## (listed under "Pulled forward"); S7 and S8 must not port them a second time.
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


func mod(attr: String) -> int:
	return Attributes.mod(score(attr))


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


func weapon_style() -> String:
	var weapon_key: Variant = equipment["weapon"]
	if PyMath.truthy(weapon_key):
		return Items.items()[weapon_key].get("style", "blunt")
	return "unarmed"


## How close a monster must be to notice you (Sneaking shortens it).
func notice_range() -> int:
	return GameConfig.FOV_RADIUS - PyMath.floordiv(practice("sneaking"), 4)


func buy_price(key: String) -> int:
	var mult: float = (float(get_trait("buy_mult", 1)) * (1 - 0.02 * practice("haggling"))
			* (1 - 0.03 * mod("cha")))
	return maxi(1, PyMath.round_half_even(shop.price(key) * mult))


func sell_price(key: String) -> int:
	var mult: float = (float(get_trait("sell_mult", 1)) * (1 + 0.03 * practice("haggling"))
			* (1 + 0.03 * mod("cha")))
	return maxi(1, PyMath.round_half_even(Shop.sell_price(key) * mult))


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


func update_fov() -> void:
	visible = Dungeon.compute_fov(floor, player.x, player.y)
	var explored := floor.explored
	for v in visible:
		explored[v.y][v.x] = 1


# --- Queries --------------------------------------------------------------------

func pet_at(x: int, y: int) -> Pet:
	var pt := active_pet
	return pt if pt != null and pt.x == x and pt.y == y else null


func monster_at(x: int, y: int) -> Monster:
	for m in monsters:
		if m.x == x and m.y == y:
			return m
	return null


var in_safe_room: bool:
	get:
		return floor.is_safe(player.x, player.y)


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


# --- S7 (attacks, kills, drops, Acts, combat mode, opportunity attacks, turn flow) ----
# Append world.py lines 1084-1557 here (minus _end_combat, above).


# --- S8 (move, wait, descend, rest, safe room, craft, shop, pet, class skills, items, bombs, boxes) ----
# Append world.py lines 468-1080 here (minus add_box, choose_class and equip, above).

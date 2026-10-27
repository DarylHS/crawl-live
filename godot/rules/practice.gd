class_name Practice
extends RefCounted
## Practice skills: things you get better at by doing them (crawler/practice.py).
##
## Every skill starts at level 0 and is hidden until first used. Using it earns practice XP; each
## level needs more than the last, up to MAX_LEVEL. The rules read the effects through
## World.practice(key); the ones that change the character sheet are folded in by
## World.refresh_stats. Skill data (name, group, what trains it, what each level gives) is
## Content.table("practice_skills"); the constants are the config.json "practice" section. The
## listeners map game events to skill XP and are subscribed in a fixed order.
##
## Seam (S5, the World is not ported yet): `world` is duck-typed. Practice uses only
## world.events (EventBus), world.messages (MessageLog), world.refresh_stats(),
## world.add_toast(text, tier) and world.weapon_style() -> String. Practice holds the world
## through a WeakRef: the event bus (owned by the world) holds callables bound to this object, so a
## strong reference back would be a reference cycle and leak both. The world owns its Practice
## (World.training), so the weak reference never dangles in play.
## Unknown skill keys were a KeyError in Python and are an engine error here; no caller passes one.

static var MAX_LEVEL: int = Content.config("practice")["MAX_LEVEL"]
## Stomping trains on monsters this small or smaller (max HP).
static var SMALL_MONSTER_HP: int = Content.config("practice")["SMALL_MONSTER_HP"]
## Steps per point of Cardio practice.
static var CARDIO_STEPS: int = Content.config("practice")["CARDIO_STEPS"]

var levels: Dictionary = {}   ## skill key -> level (int)
var xp: Dictionary = {}       ## skill key -> XP towards the next level (int)
var used: Dictionary = {}     ## set of skill keys practised at least once (key -> true)
var steps: int = 0
var world: Object:
	get:
		return _world_ref.get_ref()

var _world_ref: WeakRef


func _init(world_value: Object) -> void:
	_world_ref = weakref(world_value)
	for k in skills():
		levels[k] = 0
	for k in skills():
		xp[k] = 0
	var ev: EventBus = world_value.events
	var subs: Array = [
		["player_attack", _attack], ["kill", _kill], ["damage_taken", _hurt], ["dodged", _dodged],
		["bomb", _bomb], ["item_use", _item_use], ["rest", _rest], ["step", _step],
		["item_pickup", _pickup], ["shop_buy", _shop], ["shop_sell", _shop], ["box_opened", _box],
		["craft", _craft], ["viewers_gained", _viewers], ["pet_hit", _pet]]
	for s in subs:
		ev.subscribe(s[0], s[1])


## SKILLS: key -> {name, group, trains, effect}; order is the K screen and telemetry row order.
static func skills() -> Dictionary:
	return Content.table("practice_skills")


## Practice needed to go from `level` to level + 1 (gentle at first, steep later).
static func xp_to_next(level: int) -> int:
	return ceili(8 * pow(1.45, level))


# --- Core -----------------------------------------------------------------

func level(key: String) -> int:
	return levels[key]


func gain(key: String, amount: int = 1) -> void:
	if amount <= 0:
		return
	used[key] = true
	if levels[key] >= MAX_LEVEL:
		return
	xp[key] += amount
	while levels[key] < MAX_LEVEL and xp[key] >= xp_to_next(levels[key]):
		xp[key] -= xp_to_next(levels[key])
		levels[key] += 1
		_level_up(key, levels[key])


func _level_up(key: String, lvl: int) -> void:
	var w: Object = world
	w.refresh_stats()   # Pain Tolerance, Dodging and the weapon skills show up
	var skill_name: String = skills()[key]["name"]
	w.add_toast("Skill up: %s %d" % [skill_name, lvl], "silver")
	w.messages.add("%s is now level %d. %s." % [skill_name, lvl, skills()[key]["effect"]], GameConfig.ACCENT)
	var many := 0
	for v in levels.values():
		if v >= 3:
			many += 1
	w.events.emit("practice_level", {"skill": key, "level": lvl, "title": skill_name, "many_at_3": many})


# --- Listeners ------------------------------------------------------------

func _attack(_name: String, d: Dictionary) -> void:
	if not d["hit"]:
		return
	var style: String = world.weapon_style()
	gain({"unarmed": "fisticuffs", "blade": "blades", "blunt": "bludgeoning"}[style])
	if d["crit"]:
		gain("cheap_shots")
	if PyMath.truthy(d.get("boss")):
		gain("giant_killer")
	if PyMath.truthy(d.get("small")):
		gain("stomping")


func _kill(_name: String, d: Dictionary) -> void:
	if d.get("by") == "melee" and PyMath.truthy(d.get("small")):
		gain("stomping", 2)
	gain("pickpocketing")


func _hurt(_name: String, d: Dictionary) -> void:
	if d["hp"] > 0:
		gain("pain_tolerance")


func _dodged(_name: String, _d: Dictionary) -> void:
	gain("dodging")


func _bomb(_name: String, d: Dictionary) -> void:
	gain("lobbing", 1 + int(d.get("kills", 0)))


func _item_use(_name: String, d: Dictionary) -> void:
	if Content.item(d["item"])["kind"] == "potion":
		gain("first_aid", 2)


func _rest(_name: String, d: Dictionary) -> void:
	gain("power_napping", maxi(1, PyMath.floordiv(d["turns"], 10)))


func _step(_name: String, d: Dictionary) -> void:
	steps += 1
	if PyMath.mod(steps, CARDIO_STEPS) == 0:
		gain("cardio")
	if PyMath.truthy(d.get("sneaky")):
		gain("sneaking")


func _pickup(_name: String, _d: Dictionary) -> void:
	gain("scavenging")


func _shop(_name: String, _d: Dictionary) -> void:
	gain("haggling")


func _box(_name: String, _d: Dictionary) -> void:
	gain("gambling")


func _craft(_name: String, _d: Dictionary) -> void:
	gain("tinkering", 2)


func _viewers(_name: String, d: Dictionary) -> void:
	gain("showmanship", PyMath.floordiv(d["amount"], 40))


func _pet(_name: String, _d: Dictionary) -> void:
	gain("pet_bonding")


# --- Save / load ----------------------------------------------------------

## {levels, xp, used (sorted list), steps}. levels and xp are the live dictionaries, as in Python.
func to_dict() -> Dictionary:
	var u: Array = used.keys()
	u.sort()
	return {"levels": levels, "xp": xp, "used": u, "steps": steps}


## Restore from to_dict() output; skills missing from the save (added later) start at 0.
func load(d: Dictionary) -> void:
	var lv := {}
	var x := {}
	for k in skills():
		lv[k] = 0
	for k in skills():
		x[k] = 0
	lv.merge(d["levels"], true)
	x.merge(d["xp"], true)
	levels = lv
	xp = x
	used = {}
	for k in d["used"]:
		used[k] = true
	steps = d["steps"]

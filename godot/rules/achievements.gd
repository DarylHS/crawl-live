class_name Achievements
extends RefCounted
## Achievements: the only way (besides sponsors) to earn loot boxes (crawler/achievements.py).
##
## The table is Content.table("achievements") (key order = unlock order); each entry has the event it
## listens to (`on`) and a data `rule` that AchievementRules interprets. The tracker keeps the running
## counts. Quirky things count as much as feats: a natural 1 earns a box. Each unlock pops up on
## screen, the System explains what you did and what you got, and the box remembers why.
##
## Subscription order: Python subscribes once per distinct `on` event, iterating a set of strings
## (order varies per process with string hashing); each event's subscriber list gets exactly one
## Achievements handler, so the order between events never matters (plan 5.4). Here the distinct events
## are taken in first-seen table order, then "unequip", as in Python. Relative to other systems the
## order is what counts: Practice first (World._init), Achievements, then Showrunner.
##
## The world is held through a WeakRef (plan section 3). `world` is duck-typed: it needs `events`,
## `messages`, `turn`, `add_toast`, `add_box`, plus `viewers` and `inventory` for world_gte rules.

## key -> turn unlocked.
var unlocked: Dictionary = {}
var tracker: AchievementTracker
var world: Object:
	get:
		return _world_ref.get_ref()

var _world_ref: WeakRef


func _init(world_value: Object) -> void:
	_world_ref = weakref(world_value)
	tracker = AchievementTracker.new(world_value)
	var seen: Dictionary = {}
	var ev: EventBus = world_value.events
	for a in table().values():
		if not seen.has(a["on"]):
			seen[a["on"]] = true
			ev.subscribe(a["on"], _on_event)
	ev.subscribe("unequip", _on_unequip)


## ACHIEVEMENTS: key -> {name, desc, tier, on, rule}.
static func table() -> Dictionary:
	return Content.table("achievements")


func _on_unequip(_name: String, data: Dictionary) -> void:
	tracker.equipped.erase(data["slot"])


func _on_event(name: String, data: Dictionary) -> void:
	var t := tracker
	if name == "kill":
		t.kills += 1
		if data.get("by") == "melee" and data.get("style") == "unarmed":
			t.unarmed_kills += 1
	elif name == "item_pickup":
		t.pickups += 1
	elif name == "equip":
		t.equipped[data["slot"]] = true
	elif name == "pet_kill":
		t.pet_kills += 1
	elif name == "map_found":
		t.maps += 1
	elif name == "nat1":
		t.nat1s += 1
	elif name == "shop_sell" and data.get("item_kind") == "junk":
		t.junk_sold += 1
	var all: Dictionary = table()
	for key in all:
		var a: Dictionary = all[key]
		if a["on"] == name and not unlocked.has(key) and AchievementRules.test(a["rule"], t, data):
			_unlock(key, a)


func _unlock(key: String, a: Dictionary) -> void:
	var w: Object = world
	unlocked[key] = w.turn
	var box: String = Content.box(a["tier"])["name"]
	w.add_toast("Achievement: %s" % a["name"], a["tier"], "%s box. Open it in a safe room." % box)
	w.messages.add("Achievement unlocked: %s! %s" % [a["name"], a["desc"]], GameConfig.ACCENT)
	w.events.emit("achievement", {"key": key, "title": a["name"], "tier": a["tier"], "turn": w.turn,
			"why": a["desc"], "reward": "a %s box" % box})
	w.add_box(a["tier"], "%s. %s" % [a["name"], a["desc"]])

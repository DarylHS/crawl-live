class_name AchievementTracker
extends RefCounted
## Running totals the achievement rules read from (crawler/achievements.py Tracker).
##
## `equipped` is a set of slot names (Dictionary slot -> true). The world is held through a WeakRef
## (port plan section 3, "Back-references to World"): Python's Tracker holds it strongly, but
## World -> Achievements -> AchievementTracker -> World would be a reference cycle here. `world`
## is null once the world is gone.

var kills: int = 0
var pickups: int = 0
var equipped: Dictionary = {}
var unarmed_kills: int = 0
var pet_kills: int = 0
var maps: int = 0
var junk_sold: int = 0
var nat1s: int = 0
var world: Object:
	get:
		return _world_ref.get_ref() if _world_ref != null else null

var _world_ref: WeakRef


func _init(world_value: Object = null) -> void:
	if world_value != null:
		_world_ref = weakref(world_value)

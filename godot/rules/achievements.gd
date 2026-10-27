class_name Achievements
extends RefCounted
## P1 STAND-IN (port plan 9): same class name and constructor as crawler/achievements.py's
## Achievements, but it unlocks nothing and subscribes to no events (a handler that does nothing
## has no effect, so the stand-in omits the subscriptions). Slice T1 replaces this file with the
## real port (tracker, rules interpreter, unlock order).
## SEAM: `world` is duck-typed and held weakly (World arrives in slice S6).

## key -> turn unlocked.
var unlocked: Dictionary = {}
## The owning world, held through a WeakRef (port plan section 3, "Back-references to World").
var world: Object:
	get:
		return _world_ref.get_ref()

var _world_ref: WeakRef


func _init(world_value: Object) -> void:
	_world_ref = weakref(world_value)

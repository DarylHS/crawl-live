class_name FunFacts
extends RefCounted
## P1 STAND-IN (port plan 9): same class name and constructor as crawler/funfacts.py's FunFacts,
## but it says nothing and subscribes to no events. Slice T3 replaces this file with the real port.
## SEAM: `world` is duck-typed and held weakly (World arrives in slice S6).

## The owning world, held through a WeakRef (port plan section 3, "Back-references to World").
var world: Object:
	get:
		return _world_ref.get_ref()

var _world_ref: WeakRef


func _init(world_value: Object) -> void:
	_world_ref = weakref(world_value)

class_name Achievements
extends RefCounted
## P1 STAND-IN (port plan 9): same class name and constructor as crawler/achievements.py's
## Achievements, but it unlocks nothing and subscribes to no events (a handler that does nothing
## has no effect, so the stand-in omits the subscriptions). Slice T1 replaces this file with the
## real port (tracker, rules interpreter, unlock order).
## SEAM: `world` is duck-typed (World arrives in slice S6).

## key -> turn unlocked.
var unlocked: Dictionary = {}
var world: Variant


func _init(p_world: Variant) -> void:
	world = p_world

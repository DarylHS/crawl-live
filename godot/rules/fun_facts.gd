class_name FunFacts
extends RefCounted
## P1 STAND-IN (port plan 9): same class name and constructor as crawler/funfacts.py's FunFacts,
## but it says nothing and subscribes to no events. Slice T3 replaces this file with the real port.
## SEAM: `world` is duck-typed (World arrives in slice S6).

var world: Variant


func _init(p_world: Variant) -> void:
	world = p_world

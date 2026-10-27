class_name Showrunner
extends RefCounted
## P1 STAND-IN (port plan 9): same class name and constructor as crawler/showrunner.py's
## Showrunner. It owns its PyRandom (seed ^ 0x5EED) and the viewer fields, but never draws and
## subscribes to no events, so viewers stay at START_VIEWERS and the `show` stream is untouched.
## Slice T2 replaces this file with the real port (subscription order is RNG order there).
## SEAM: `world` is duck-typed (World arrives in slice S6); it needs `seed`.

var world: Variant
var rng: PyRandom
var viewers: int
var peak: int
## [turn, viewers] at each floor start and end.
var history: Array = []
## [turn, viewers] every SAMPLE_EVERY turns.
var samples: Array = []


func _init(p_world: Variant) -> void:
	var start: int = Content.config("showrunner")["START_VIEWERS"]
	world = p_world
	rng = PyRandom.new(int(p_world.seed) ^ 0x5EED)
	viewers = start
	peak = start
	samples = [[0, start]]

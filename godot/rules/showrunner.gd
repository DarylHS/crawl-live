class_name Showrunner
extends RefCounted
## P1 STAND-IN (port plan 9): same class name and constructor as crawler/showrunner.py's
## Showrunner. It owns its PyRandom (seed ^ 0x5EED) and the viewer fields, but never draws and
## subscribes to no events, so viewers stay at START_VIEWERS and the `show` stream is untouched.
## Slice T2 replaces this file with the real port (subscription order is RNG order there).
## SEAM: `world` is duck-typed and held weakly (World arrives in slice S6); it needs `seed`.

## The owning world, held through a WeakRef (port plan section 3, "Back-references to World").
var world: Object:
	get:
		return _world_ref.get_ref()

var _world_ref: WeakRef
var rng: PyRandom
var viewers: int
var peak: int
## [turn, viewers] at each floor start and end.
var history: Array = []
## [turn, viewers] every SAMPLE_EVERY turns.
var samples: Array = []


func _init(world_value: Object) -> void:
	var start: int = Content.config("showrunner")["START_VIEWERS"]
	_world_ref = weakref(world_value)
	rng = PyRandom.new(int(world_value.seed) ^ 0x5EED)
	viewers = start
	peak = start
	samples = [[0, start]]

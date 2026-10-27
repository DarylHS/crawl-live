class_name EventBus
extends RefCounted
## A tiny publish/subscribe event bus (crawler/events.py).
##
## The world emits events ("kill", "descend", ...) and other systems listen: achievements, the
## announcer, and later telemetry. Subscribing to "*" receives every event, which is how telemetry
## logs a whole run. Handlers are Callables taking (name: String, data: Dictionary). Named
## subscribers run first, in subscription order, then the "*" ones. The subscriber lists are
## iterated live by index, as Python iterates its live list, so a handler that subscribes during an
## emit is called in that same emit, and nested emits run depth first.
##
## Test seam (approved, port plan 11.3 item 7): an optional `tap` Callable, called first in emit
## with (name, data) before any handler, for the parity trace. No rule reads it. Leave it unset
## (the default invalid Callable) in the game.

var tap: Callable = Callable()

var _subs: Dictionary = {}   # name -> Array[Callable]


func subscribe(name: String, fn: Callable) -> void:
	if not _subs.has(name):
		_subs[name] = []
	_subs[name].append(fn)


## emit(name, {"depth": 3}): Python's emit(name, **data), with keys in the same order as the kwargs.
## A payload key called "name" is still forbidden by convention (it was a TypeError in Python).
func emit(name: String, data: Dictionary = {}) -> void:
	if tap.is_valid():
		tap.call(name, data)
	_run(_subs.get(name), name, data)
	_run(_subs.get("*"), name, data)


func _run(subs: Variant, name: String, data: Dictionary) -> void:
	if subs == null:
		return
	var i := 0
	while i < subs.size():
		subs[i].call(name, data)
		i += 1

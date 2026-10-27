class_name MessageLog
extends RefCounted
## The scrolling message log (MessageLog in crawler/world.py): a deque with a maximum length.
##
## `lines` holds [text, colour] pairs, oldest first, at most `maxlen` of them (200 by default; the
## oldest fall off the front). Colours are [r, g, b] int Arrays, default GameConfig.TEXT.
##
## Test seam (approved, port plan 11.3 item 7): an optional `tap` Callable, called first in add with
## (text, colour) before the line is stored, for the parity trace. No rule reads it. A tap lambda
## that captures an object owning this log (the World, say) makes a reference cycle and leaks it:
## clear the tap when done, or capture a separate holder object instead.

var tap: Callable = Callable()
var lines: Array = []
var maxlen: int


func _init(maxlen_value: int = 200) -> void:
	maxlen = maxlen_value


## add("You hit it.", GameConfig.GOOD). Omitting the colour (or passing null) uses GameConfig.TEXT.
func add(text: String, colour: Variant = null) -> void:
	var col: Array = (GameConfig.TEXT if colour == null else colour).duplicate()
	if tap.is_valid():
		tap.call(text, col)
	lines.append([text, col])
	while lines.size() > maxlen:
		lines.pop_front()


## list(lines)[-n:] with Python slice rules: recent(3) is the last three; recent(0) is the WHOLE
## log (since -0 is 0); a negative n drops that many lines from the front. Returns a new Array.
func recent(n: int) -> Array:
	var size := lines.size()
	var start := -n
	if start < 0:
		start = maxi(start + size, 0)
	if start > size:
		start = size
	return lines.slice(start)

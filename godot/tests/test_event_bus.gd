extends TestCase
## EventBus (crawler/events.py). No pytest file covers it directly, so these pin the behaviour the
## rules rely on: named before "*", subscription order, live list iteration, nesting, the tap seam.

var bus: EventBus
var seen: Array


func before_each() -> void:
	bus = EventBus.new()
	seen = []


func _rec(tag: String) -> Callable:
	return func(name: String, data: Dictionary) -> void: seen.append([tag, name, data])


func test_named_subscribers_get_name_and_data() -> void:
	bus.subscribe("kill", _rec("a"))
	bus.emit("kill", {"depth": 2, "boss": false})
	assert_eq(seen, [["a", "kill", {"depth": 2, "boss": false}]])


func test_emit_without_data_gives_empty_dictionary() -> void:
	bus.subscribe("turn", _rec("a"))
	bus.emit("turn")
	assert_eq(seen, [["a", "turn", {}]])


func test_unknown_event_is_silent() -> void:
	bus.subscribe("kill", _rec("a"))
	bus.emit("descend", {})
	assert_eq(seen, [])


func test_subscription_order_then_wildcard_last() -> void:
	bus.subscribe("*", _rec("star"))
	bus.subscribe("kill", _rec("first"))
	bus.subscribe("kill", _rec("second"))
	bus.emit("kill", {})
	assert_eq(seen.map(func(x: Array) -> String: return x[0]), ["first", "second", "star"])


func test_wildcard_sees_every_event() -> void:
	bus.subscribe("*", _rec("star"))
	bus.emit("a", {"x": 1})
	bus.emit("b", {})
	assert_eq(seen.map(func(x: Array) -> String: return x[1]), ["a", "b"])


func test_handlers_share_one_data_dictionary() -> void:
	bus.subscribe("e", func(_n: String, d: Dictionary) -> void: d["touched"] = true)
	bus.subscribe("e", func(_n: String, d: Dictionary) -> void: seen.append(d.has("touched")))
	bus.emit("e", {})
	assert_eq(seen, [true])


func test_subscribing_during_emit_is_called_in_the_same_emit() -> void:
	# Python iterates the live list, so an appended handler runs in the emit that appended it.
	bus.subscribe("e", func(_n: String, _d: Dictionary) -> void:
		seen.append("outer")
		bus.subscribe("e", func(_n2: String, _d2: Dictionary) -> void: seen.append("late")))
	bus.emit("e", {})
	assert_eq(seen, ["outer", "late"])
	bus.emit("e", {})
	assert_eq(seen, ["outer", "late", "outer", "late", "late"])


func test_nested_emit_is_depth_first() -> void:
	bus.subscribe("outer", func(_n: String, _d: Dictionary) -> void:
		seen.append("outer-1")
		bus.emit("inner", {}))
	bus.subscribe("outer", func(_n: String, _d: Dictionary) -> void: seen.append("outer-2"))
	bus.subscribe("inner", func(_n: String, _d: Dictionary) -> void: seen.append("inner"))
	bus.emit("outer", {})
	assert_eq(seen, ["outer-1", "inner", "outer-2"])


func test_tap_is_called_first_and_before_handlers() -> void:
	bus.tap = func(name: String, data: Dictionary) -> void: seen.append(["tap", name, data.duplicate()])
	bus.subscribe("e", _rec("h"))
	bus.subscribe("*", _rec("star"))
	bus.emit("e", {"n": 1})
	assert_eq(seen.map(func(x: Array) -> String: return x[0]), ["tap", "h", "star"])
	assert_eq(seen[0], ["tap", "e", {"n": 1}])


func test_tap_sees_events_nobody_listens_to() -> void:
	bus.tap = func(name: String, _data: Dictionary) -> void: seen.append(name)
	bus.emit("lonely", {})
	assert_eq(seen, ["lonely"])


func test_tap_is_pre_order_for_nested_emits() -> void:
	bus.tap = func(name: String, _data: Dictionary) -> void: seen.append("tap:" + name)
	bus.subscribe("outer", func(_n: String, _d: Dictionary) -> void: bus.emit("inner", {}))
	bus.emit("outer", {})
	assert_eq(seen, ["tap:outer", "tap:inner"])


func test_default_tap_is_unset() -> void:
	assert_false(bus.tap.is_valid())

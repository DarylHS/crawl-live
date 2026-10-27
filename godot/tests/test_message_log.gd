extends TestCase
## MessageLog (crawler/world.py): a bounded deque of (text, colour) pairs. No pytest file covers it
## on its own; these pin the behaviour the HUD and the traces rely on.


func test_add_stores_text_and_colour() -> void:
	var log := MessageLog.new()
	log.add("hello", GameConfig.GOOD)
	assert_eq(log.lines, [["hello", [110, 210, 120]]])


func test_default_colour_is_text() -> void:
	var log := MessageLog.new()
	log.add("plain")
	assert_eq(log.lines[0][1], [225, 222, 235])


func test_keeps_only_the_last_200() -> void:
	var log := MessageLog.new()
	for i in 250:
		log.add("m%d" % i)
	assert_eq(log.lines.size(), 200)
	assert_eq(log.lines[0][0], "m50")
	assert_eq(log.lines[199][0], "m249")


func test_custom_maxlen() -> void:
	var log := MessageLog.new(3)
	for i in 5:
		log.add(str(i))
	assert_eq(log.lines.map(func(l: Array) -> String: return l[0]), ["2", "3", "4"])


func test_recent_is_the_tail_oldest_first() -> void:
	var log := MessageLog.new()
	for i in 10:
		log.add(str(i))
	assert_eq(log.recent(3).map(func(l: Array) -> String: return l[0]), ["7", "8", "9"])
	assert_eq(log.recent(1).size(), 1)


func test_recent_larger_than_the_log() -> void:
	var log := MessageLog.new()
	log.add("a")
	log.add("b")
	assert_eq(log.recent(7).size(), 2)
	assert_eq(MessageLog.new().recent(7), [])


func test_recent_zero_is_the_whole_log_as_in_python() -> void:
	# list(lines)[-0:] is list(lines)[0:], the whole list (a Python quirk, ported as is).
	var log := MessageLog.new()
	for i in 4:
		log.add(str(i))
	assert_eq(log.recent(0).size(), 4)


func test_recent_negative_drops_from_the_front() -> void:
	var log := MessageLog.new()
	for i in 6:
		log.add(str(i))
	assert_eq(log.recent(-2).map(func(l: Array) -> String: return l[0]), ["2", "3", "4", "5"])


func test_recent_returns_a_copy() -> void:
	var log := MessageLog.new()
	log.add("a")
	var r := log.recent(1)
	r.clear()
	assert_eq(log.lines.size(), 1)


func test_tap_is_called_first_with_text_and_colour() -> void:
	var log := MessageLog.new()
	var seen: Array = []
	log.tap = func(text: String, colour: Array) -> void: seen.append([text, colour, log.lines.size()])
	log.add("x", GameConfig.DANGER)
	log.add("y")
	log.tap = Callable()   # the lambda captures log, which owns the tap: break the cycle
	assert_eq(seen, [["x", [235, 80, 80], 0], ["y", [225, 222, 235], 1]])


func test_default_tap_is_unset() -> void:
	assert_false(MessageLog.new().tap.is_valid())


func test_stored_colour_is_a_copy() -> void:
	var log := MessageLog.new()
	log.add("a")
	log.lines[0][1][0] = 0
	assert_eq(GameConfig.TEXT, [225, 222, 235])

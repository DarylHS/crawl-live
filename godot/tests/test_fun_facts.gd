extends TestCase
## FunFacts (crawler/funfacts.py) and the RunReport helpers (crawler/report.py, crawler/ui/report.py).
## The pytest fun fact and report tests are in test_phase4.gd; exact message text against Python is
## covered by the full-scope parity traces. Ownership of FunFacts is in test_s4_standins.gd and test_world.gd.


func _facts(w: World) -> Array:
	var out: Array = []
	for line in w.messages.recent(0):
		if line[0].begins_with("FUN FACT"):
			out.append(line[0])
	return out


func test_subscription_order_is_practice_showrunner_funfacts() -> void:
	var w := World.new(3)
	var owners: Array = []
	for c in w.events.subscribers("box_opened"):
		var o: Object = c.get_object()
		if not owners.has(o):
			owners.append(o)
	assert_true(owners == [w.training, w.showrunner, w.funfacts], "Practice, Showrunner, FunFacts (Achievements has no box_opened rule)")
	for ev in ["player_attack", "damage_taken", "box_trade", "contract_accepted", "shop_sold_out"]:
		var subs := w.events.subscribers(ev)
		assert_true(subs[-1].get_object() == w.funfacts, ev)
	for ev in ["player_attack", "damage_taken"]:
		assert_true(w.events.subscribers(ev)[0].get_object() == w.training, ev)


func test_crit_fact_text_and_once() -> void:
	var w := World.new(20)
	w.turn = 100
	w.player.crit_range = 3
	w.events.emit("player_attack", {"target": "g", "chance": 0.5, "hit": true, "crit": true})
	assert_eq(_facts(w), ["FUN FACT: You crit on 18-20 on the d20: 15% of swings, about one in 7. They still cluster and gap at random."])
	w.turn = 200
	w.events.emit("player_attack", {"target": "g", "chance": 0.5, "hit": true, "crit": true})
	assert_eq(_facts(w).size(), 1)    # "crit" only once per run


func test_miss_streak_text_and_reset() -> void:
	var w := World.new(21)
	w.turn = 100
	for _i in range(4):
		w.events.emit("player_attack", {"target": "g", "chance": 0.75, "hit": false, "crit": false})
	var facts := _facts(w)
	assert_eq(facts.size(), 1)
	assert_eq(facts[0], "FUN FACT: 4 misses in a row at 75% each: odds of that were 0.39%. Your next swing is still 75%. Dice have no memory.")
	assert_eq(w.funfacts.miss_streak, 0)


func test_trade_and_sold_out_are_forced_past_the_rate_limit() -> void:
	var w := World.new(22)
	w.turn = 5
	w.funfacts.last_turn = 5
	w.events.emit("box_trade", {"tier": "bronze", "to": "silver"})
	w.events.emit("shop_sold_out", {"item": "tonic"})
	assert_eq(_facts(w).size(), 2)
	w.events.emit("shop_sold_out", {"item": "tonic"})   # once per item
	assert_eq(_facts(w).size(), 2)


func test_close_call_needs_hp_in_range() -> void:
	var w := World.new(23)
	w.turn = 100
	w.events.emit("damage_taken", {"hp": 0})
	w.events.emit("damage_taken", {"hp": w.player.max_hp})
	assert_eq(_facts(w).size(), 0)
	w.events.emit("damage_taken", {"hp": 1})
	assert_eq(_facts(w).size(), 1)


func test_fun_fact_event_carries_the_text() -> void:
	var w := World.new(24)
	w.turn = 100
	var seen: Array = []
	w.events.subscribe("fun_fact", func(_n: String, d: Dictionary) -> void: seen.append(d["text"]))
	w.events.emit("contract_accepted", {"contract": "gloop_blitz", "depth": 2})
	assert_eq(seen.size(), 1)
	assert_true("positive expected value" in seen[0])


# --- RunReport helpers -------------------------------------------------------------

func test_nice_max_and_plural() -> void:
	assert_eq([RunReport.nice_max(0), RunReport.nice_max(2), RunReport.nice_max(3), RunReport.nice_max(5.5),
			RunReport.nice_max(11), RunReport.nice_max(101), RunReport.nice_max(1999)], [2, 2, 5, 10, 20, 200, 2000])
	assert_eq([RunReport.plural(1, "turn"), RunReport.plural(0, "kill"), RunReport.plural(1234, "viewer")],
			["1 turn", "0 kills", "1,234 viewers"])


func test_report_text_lines() -> void:
	var t := {"turns": 1, "kills": 3, "gold": 40, "damage": 7, "peak_viewers": 1500, "boxes": 2, "rerolls": 1}
	assert_eq(RunReport.summary_line(t), "1 turn   3 kills   40 gold earned   7 damage taken   peak 1,500 viewers")
	assert_eq(RunReport.notes_line(t), "Boxes opened: 2   Rerolls: 1   Grey lines on the viewer chart mark each new floor.")
	assert_eq(RunReport.box_caption([10.4, 20.4], [5, 30]), ["2 boxes: 30 gold vs 20 expected,", "so you were luckier than average."])
	assert_eq(RunReport.box_caption([10.0], [5])[1], "so you were unluckier than average.")
	assert_eq(RunReport.box_caption([5.0], [5])[1], "so you were exactly as lucky than average.")
	assert_eq(RunReport.contract_lines({"contracts": []}), ["None signed."])
	var lines := RunReport.contract_lines({"contracts": [[2, "gloop_blitz"]], "gold_by_floor": [[2, 9]], "damage_by_floor": [[2, 4]]})
	assert_eq(lines, ["Floor 2: Gloop Blitz (Gloop Energy). That floor: 9 gold, 4 damage taken."])


func test_report_totals_and_contracts() -> void:
	var w := World.new(30)
	w.floor_stats[0]["gold"] = 12
	w.floor_stats[0]["damage_taken"] = 3
	w.floor_stats[0]["contract"] = "gloop_blitz"
	w.box_log.append({"ev": 1.5, "value": 4, "rerolled": true})
	w.box_log.append({"ev": 2.5, "value": 6, "rerolled": false})
	var rep := RunReport.build(w)
	assert_eq(rep["contracts"], [[1, "gloop_blitz"]])
	assert_eq(rep["box_expected"], [1.5, 4.0])
	assert_eq(rep["box_realised"], [4, 10])
	assert_eq(rep["totals"], {"gold": 12, "kills": 0, "boxes": 2, "rerolls": 1, "damage": 3, "turns": w.turn, "peak_viewers": w.showrunner.peak})
	assert_eq(rep["viewers"][-1], [w.turn, w.viewers])

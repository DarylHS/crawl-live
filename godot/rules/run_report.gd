class_name RunReport
extends RefCounted
## Post-run report data (crawler/report.py) and the pure number and text helpers of the report
## screen (crawler/ui/report.py: nice_max, plural and the sentences it prints). Headless: the
## drawing itself is presentation (P7) and takes everything from here.
##
## Pairs and samples are two-element Arrays ([depth, value], [turn, viewers]), Python's tuples.


## Everything the report screen plots, as plain Arrays. Key order is Python's `dict(...)` order.
## The sums are the same: explicit `+=` loops stay naive, `sum()` over ints and bools is exact.
static func build(world: World) -> Dictionary:
	var floors: Array = world.floor_stats
	var expected: Array = []
	var realised: Array = []
	var ev_total := 0.0
	var got_total := 0
	for b in world.box_log:
		ev_total += b["ev"]
		got_total += b["value"]
		expected.append(ev_total)
		realised.append(got_total)
	var samples: Array = world.showrunner.samples.duplicate()
	if samples.is_empty() or samples[-1][0] != world.turn:
		samples.append([world.turn, world.viewers])
	var damage_by_floor: Array = []
	var gold_by_floor: Array = []
	var contracts: Array = []
	var gold := 0
	var damage := 0
	for f in floors:
		damage_by_floor.append([f["depth"], f["damage_taken"]])
		gold_by_floor.append([f["depth"], f["gold"]])
		if PyMath.truthy(f["contract"]):
			contracts.append([f["depth"], f["contract"]])
		gold += f["gold"]
		damage += f["damage_taken"]
	var rerolls := 0
	for b in world.box_log:
		rerolls += int(b["rerolled"])
	return {
		"damage_by_floor": damage_by_floor,
		"gold_by_floor": gold_by_floor,
		"contracts": contracts,
		"box_expected": expected, "box_realised": realised,
		"viewers": samples,
		"totals": {"gold": gold, "kills": world.player.kills,
				"boxes": world.box_log.size(), "rerolls": rerolls,
				"damage": damage, "turns": world.turn,
				"peak_viewers": world.showrunner.peak},
	}


## Round an axis maximum up to 2, 5 or 10 times a power of ten (at least 2).
static func nice_max(v: float) -> int:
	v = maxf(v, 2.0)
	var step := 1
	while true:
		for m in [2, 5, 10]:
			if m * step >= v:
				return m * step
		step *= 10
	return 0   # unreachable; keeps the typed return happy


## '1 turn', '2 turns', '1,234 viewers'.
static func plural(n: int, word: String) -> String:
	return "%s %s%s" % [PyFmt.thousands(n), word, "" if n == 1 else "s"]


## The line under the title.
static func summary_line(t: Dictionary) -> String:
	return "%s   %s   %d gold earned   %d damage taken   peak %s" % [
			plural(t["turns"], "turn"), plural(t["kills"], "kill"), t["gold"], t["damage"],
			plural(t["peak_viewers"], "viewer")]


## The two caption lines of the loot box chart for a non-empty run of boxes: [first, second].
static func box_caption(expected: Array, realised: Array) -> Array:
	var diff: float = realised[-1] - expected[-1]
	var verdict := "luckier" if diff > 0 else ("unluckier" if diff < 0 else "exactly as lucky")
	return ["%d boxes: %d gold vs %s expected," % [expected.size(), realised[-1], PyFmt.fixed(expected[-1], 0)],
			"so you were %s than average." % verdict]


## One line per signed sponsor deal, or ["None signed."] when there were none.
static func contract_lines(data: Dictionary) -> Array:
	var contracts: Array = data["contracts"]
	if contracts.is_empty():
		return ["None signed."]
	var gold := {}
	for p in data["gold_by_floor"]:
		gold[p[0]] = p[1]
	var dmg := {}
	for p in data["damage_by_floor"]:
		dmg[p[0]] = p[1]
	var out: Array = []
	for c in contracts:
		var info: Dictionary = Contracts.contracts()[c[1]]
		out.append("Floor %d: %s (%s). That floor: %d gold, %d damage taken." % [
				c[0], info["name"], info["sponsor"], gold.get(c[0], 0), dmg.get(c[0], 0)])
	return out


## The footer note under the sponsor deals.
static func notes_line(t: Dictionary) -> String:
	return "Boxes opened: %d   Rerolls: %d   Grey lines on the viewer chart mark each new floor." % [t["boxes"], t["rerolls"]]

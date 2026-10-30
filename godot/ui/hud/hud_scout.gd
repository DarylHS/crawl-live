class_name HudScout
extends RefCounted
## The Analyst's Scout Report in the side panel (crawler/ui/hud.py `draw_scout_report`): while
## world.scout_turns lasts, the three nearest monsters in sight with their HP and the exact odds
## each way: the roll needed, the chance to hit and the average damage. All numbers come from the
## rules (Dice.needed_roll, Combat.hit_chance, Combat.expected_damage); this only formats them.


## "SCOUT REPORT (n)".
static func title(world: World) -> String:
	return "SCOUT REPORT (%d)" % world.scout_turns


## The monsters in sight, nearest first (Chebyshev distance, ties in monster order), at most three.
static func seen(world: World) -> Array:
	var p := world.player
	var vis: Array = []
	for m: Monster in world.monsters:
		if world.visible.has(Vector2i(m.x, m.y)):
			vis.append(m)
	PyMath.stable_sort_in_place(vis, func(m: Monster) -> int: return maxi(absi(m.x - p.x), absi(m.y - p.y)))
	return vis.slice(0, 3)


## One odds line: who is "you" or "it" (right-aligned to 3), a attacks b.
static func odds_line(who: String, a: Entity, b: Entity) -> String:
	return "%s need %s+ %s  ~%s dmg" % [PyFmt.rjust(who, 3), PyFmt.rjust(str(Dice.needed_roll(a.attack, b.ac)), 2),
			PyFmt.rjust(PyFmt.percent(Combat.hit_chance(a, b), 0), 4), PyFmt.fixed(Combat.expected_damage(a, b), 1)]


## [{head, colour, lines}] for the monsters shown: head "g Name  hp/max", lines the odds both ways.
static func rows(world: World) -> Array:
	var out: Array = []
	var p := world.player
	for m: Monster in seen(world):
		out.append({"head": "%s %s  %d/%d" % [m.glyph, m.name, m.hp, m.max_hp], "colour": m.colour,
				"lines": [odds_line("you", p, m), odds_line("it", m, p)]})
	return out

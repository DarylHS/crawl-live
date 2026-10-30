class_name HudEnd
extends RefCounted
## The death and victory overlays (crawler/ui/screens.py `draw_death`, `draw_victory`, `_summary`
## and `overlay`): the whole window dimmed with the background colour, a big headline, the cause or
## a quip, and a run summary. P6 draws them so a finished run is readable; P7 owns the screens and the
## keys the last line names (R: report, Esc: title), which only Enter works for until then.

const SHADE_ALPHA := 200.0 / 255.0


## The summary lines under the headline (Python `_summary`, without the key hint).
static func summary(world: World) -> PackedStringArray:
	var p := world.player
	return PackedStringArray([
		"Reached floor %d of %d" % [world.depth, GameConfig.NUM_FLOORS],
		"Level %d   Kills %d   Turns %d   Gold %d" % [p.level, p.kills, world.turn, world.gold],
		"Final viewers: %s   (peak %s)" % [PyFmt.thousands(world.viewers), PyFmt.thousands(world.showrunner.peak)],
		"Seed %d" % world.seed])


## The overlay for a finished run (world.state "dead" or "victory"); an empty list while playing.
static func build(world: World, st: HudStyle) -> HudList:
	var list := HudList.new(st)
	if world.state == "playing":
		return list
	var shade := st.colour("BG")
	shade.a = SHADE_ALPHA
	list.fill(Rect2i(0, 0, HudPlace.SCREEN_W, HudPlace.SCREEN_H), shade)
	var cx := HudPlace.SCREEN_W / 2
	if world.state == "dead":
		list.centred("YOU DIED", cx, 230, st.colour("DANGER"), "huge")
		list.centred(world.death_cause if PyMath.truthy(world.death_cause) else "", cx, 290, st.colour("TEXT"), "big")
	else:
		list.centred("YOU SURVIVED", cx, 230, st.colour("GOOD"), "huge")
		list.centred("The ratings were... acceptable.", cx, 290, st.colour("TEXT"), "big")
	var lines := summary(world)
	for i in lines.size():
		list.centred(lines[i], cx, 350 + i * 26, st.colour("TEXT"))
	list.centred("Enter: new run   R: run report   Esc: title", cx, 350 + 136, st.colour("TEXT_DIM"))
	return list

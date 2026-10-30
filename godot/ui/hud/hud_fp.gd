class_name HudFp
extends RefCounted
## The first-person overlays that are not the minimap (crawler/ui/firstperson.py `provoking_steps`,
## `provoking`, `_warnings` and `_ahead`):
##   - chevrons: a red triangle with LEFT / RIGHT / BEHIND YOU for a monster right next to you that
##     you cannot see; orange when stepping away from it would give it a free swing;
##   - the "ahead" label: what W would hit ("Knockoff Goblin  7/7"), and in combat a hint naming the
##     keys whose step would provoke ("S / A provoke the Knockoff Goblin") in orange.
## The decisions are plain functions of the World and the look angle (FpLogic), so they run headless.


## In combat, [{key, monsters}] for each of W / S / A / D whose step would give monsters an attack of
## opportunity (W counts only when it wouldn't attack instead).
static func provoking_steps(world: World, logic: FpLogic) -> Array:
	var out: Array = []
	if world.combat == null:
		return out
	for pair: Array in [["W", "forward"], ["S", "back"], ["A", "left"], ["D", "right"]]:
		if pair[1] == "forward" and logic.target_ahead(world)[0] != null:
			continue
		var step := logic.relative(pair[1])
		var ms := world.provokers(step.x, step.y)
		if not ms.is_empty():
			out.append({"key": pair[0], "monsters": ms})
	return out


## The monsters any one-tile step (W / S / A / D) would provoke, each once.
static func provoking(world: World, logic: FpLogic) -> Array:
	var seen: Array = []
	for s: Dictionary in provoking_steps(world, logic):
		for m: Monster in s["monsters"]:
			if not seen.has(m):
				seen.append(m)
	return seen


## Chevrons for the monsters next to you outside the front 91 degrees: [{pts, text, pos, provoked}],
## `pos` the label's centre. `rect` is the view's rectangle (the map area).
static func chevrons(world: World, angle: float, rect: Rect2i, prov: Array) -> Array:
	var out: Array = []
	var p := world.player
	var c := rect.position + rect.size / 2
	for m: Monster in world.monsters:
		var ddx := m.x - p.x
		var ddy := m.y - p.y
		if maxi(absi(ddx), absi(ddy)) != 1:
			continue
		var rel := FpLogic.angle_gap(rad_to_deg(atan2(float(ddx), float(-ddy))), angle)
		if absf(rel) <= 45.5:
			continue                                  # in front: you can see it
		var pts: PackedVector2Array
		var text: String
		var pos: Vector2i
		if absf(rel) >= 157.5:
			pts = PackedVector2Array([Vector2(c.x - 40, rect.end.y - 40), Vector2(c.x + 40, rect.end.y - 40),
					Vector2(c.x, rect.end.y - 12)])
			text = "BEHIND YOU"
			pos = Vector2i(c.x, rect.end.y - 58)
		elif rel > 0:
			pts = PackedVector2Array([Vector2(rect.end.x - 40, c.y - 40), Vector2(rect.end.x - 40, c.y + 40),
					Vector2(rect.end.x - 12, c.y)])
			text = "RIGHT"
			pos = Vector2i(rect.end.x - 60, c.y - 58)
		else:
			pts = PackedVector2Array([Vector2(rect.position.x + 40, c.y - 40), Vector2(rect.position.x + 40, c.y + 40),
					Vector2(rect.position.x + 12, c.y)])
			text = "LEFT"
			pos = Vector2i(rect.position.x + 60, c.y - 58)
		out.append({"pts": pts, "text": text, "pos": pos, "provoked": prov.has(m)})
	return out


## Draw the chevrons into `list`.
static func build_chevrons(list: HudList, world: World, logic: FpLogic, rect: Rect2i) -> void:
	var prov := provoking(world, logic)
	for ch: Dictionary in chevrons(world, logic.angle, rect, prov):
		var colour := list.style.colour("WARN") if ch["provoked"] else list.style.colour("DANGER")
		list.polygon(ch["pts"], colour)
		list.centred(ch["text"], ch["pos"].x, ch["pos"].y, colour, "big")


## The hint for steps that would provoke, "S / A provoke the Knockoff Goblin", or "" when none would.
static func hint(steps: Array) -> String:
	if steps.is_empty():
		return ""
	var keys: PackedStringArray = []
	var ms: Array = []
	for s: Dictionary in steps:
		keys.append(s["key"])
		for m: Monster in s["monsters"]:
			if not ms.has(m):
				ms.append(m)
	var who: String = ms[0].the if ms.size() == 1 else "%d monsters" % ms.size()
	return "%s provoke%s %s" % [" / ".join(keys), "s" if steps.size() == 1 else "", who]


## The ahead label's lines: [{text, colour name}] (target first, then the provoke hint).
static func ahead_lines(world: World, logic: FpLogic, steps: Array) -> Array:
	var lines: Array = []
	var m: Variant = logic.target_ahead(world)[0]
	if m != null:
		lines.append({"text": "%s  %d/%d" % [m.name, m.hp, m.max_hp], "colour": "DANGER" if m.boss else "TEXT"})
	var h := hint(steps)
	if h != "":
		lines.append({"text": h, "colour": "WARN"})
	return lines


## Draw the ahead label (centred, `top` pixels down, default 12 below the view's top) into `list`.
## Returns the union of the text rectangles, or an empty Rect2i when nothing is shown.
static func build_ahead(list: HudList, world: World, logic: FpLogic, rect: Rect2i, top: int = -1) -> Rect2i:
	var st := list.style
	var lines := ahead_lines(world, logic, provoking_steps(world, logic))
	var y := top if top > 0 else rect.position.y + 12
	var union := Rect2i()
	var first := true
	for line: Dictionary in lines:
		var m := st.measure("big", line["text"])
		var r := Rect2i(rect.position.x + rect.size.x / 2 - m.x / 2, y, m.x, m.y)
		list.fill(Rect2i(r.position.x - 10, r.position.y - 4, r.size.x + 20, r.size.y + 8), st.colour("LABEL_BACK"))
		list.text(line["text"], r.position.x, r.position.y, st.colour(line["colour"]), "big")
		union = r if first else union.merge(r)
		first = false
		y = r.end.y + 10
	return union


## The text the label shows, joined by two spaces (Python `ahead_text`), or "" when it is not shown.
static func ahead_text(world: World, logic: FpLogic) -> String:
	var parts: PackedStringArray = []
	for line: Dictionary in ahead_lines(world, logic, provoking_steps(world, logic)):
		parts.append(line["text"])
	return "  ".join(parts)

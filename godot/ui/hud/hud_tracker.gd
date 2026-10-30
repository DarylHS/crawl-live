class_name HudTracker
extends RefCounted
## The initiative tracker over the map or 3D view (crawler/ui/hud.py `draw_tracker`, `_pips` and
## `fit_name`): the fighters in order with their HP, boss rows in their tier colour, you
## highlighted with your Move / Action / Bonus pips (filled while available, hollow once spent).
## It sits top-left of the view, or bottom-left when the top-left would hide you or a fighter
## (`avoid`, screen rectangles with you first). Monsters act between your turns, so whenever you
## can press a key it is your turn. It is clear of the minimap, the toasts and the side chevrons.

static var _hud: Dictionary = Content.table("ui_config")["hud"]
static var TIER_COLOURS: Dictionary = _hud["TIER_COLOURS"]


## Height of the box for this fight (Python: 30 + 18 per row + 22 + 16 for "+N more" + 20).
static func box_height(rows: int) -> int:
	var shown := mini(rows, HudPlace.TRACKER_ROWS)
	return 30 + 18 * shown + 22 + (16 if rows > shown else 0) + 20


## Where the tracker goes in `rect` (the map area): top-left, or bottom-left if that covers you.
static func place(rows: int, rect: Rect2i, avoid: Array) -> Rect2i:
	var h := box_height(rows)
	return HudPlace.clear_spot([
			Rect2i(rect.position.x + 10, rect.position.y + 10, HudPlace.TRACKER_W, h),
			Rect2i(rect.position.x + 10, rect.end.y - 10 - h, HudPlace.TRACKER_W, h)], avoid)


## prefix + name within `room` pixels: drop a leading "The ", then cut at a word with an ellipsis
## ("Grease Trap..."), never mid-word unless one word is too long.
static func fit_name(style: HudStyle, prefix: String, entity_name: String, room: int) -> String:
	if style.width("small", prefix + entity_name) <= room:
		return prefix + entity_name
	var nm := entity_name.trim_prefix("The ")
	var words := Array(nm.split(" ", false))
	var total := words.size()
	while not words.is_empty():
		var text := prefix + " ".join(words) + ("..." if words.size() < total else "")
		if style.width("small", text) <= room:
			return text
		words.pop_back()
	var text := prefix + nm
	while style.width("small", text + "...") > room and text.length() > prefix.length() + 1:
		text = text.left(text.length() - 1)
	return text + "..."


## The pips as [{part, label, available}] in PARTS order (Move, Action, Bonus).
static func pips(enc: Encounter) -> Array:
	var out: Array = []
	for part: String in Encounter.PARTS:
		out.append({"part": part, "label": part.capitalize(), "available": enc.has(part)})
	return out


## One tracker row: {you, label_name, colour, hp}.
static func rows(world: World) -> Array:
	var enc := world.combat
	var out: Array = []
	for ent: Entity in enc.entities:
		var you := is_same(ent, world.player)
		var tier: String = ent.tier if ent is Monster else ""
		var col: Array = TIER_COLOURS.get(tier, ent.colour)
		out.append({"you": you, "name": "You" if you else ent.name, "colour": col,
				"total": enc.total(ent), "hp": "%d/%d" % [ent.hp, ent.max_hp]})
	return out


func _pip_row(list: HudList, enc: Encounter, x: int, y: int) -> int:
	var st := list.style
	for pip: Dictionary in pips(enc):
		var label: String = pip["label"]
		var r := Rect2i(x, y, st.width("small", label) + 10, 16)
		var centre := r.position + r.size / 2
		if pip["available"]:
			list.fill(r, st.colour("GOOD"))
			list.centred(label, centre.x, centre.y, st.colour("PANEL_BG"), "small")
		else:
			list.frame(r, st.colour("TEXT_DIM"), 1)
			list.centred(label, centre.x, centre.y, st.colour("TEXT_DIM"), "small")
		x = r.end.x + 6
	return y + 18


## Draw the tracker into `list`; returns the box. Needs world.combat.
func build(list: HudList, world: World, rect: Rect2i, avoid: Array = []) -> Rect2i:
	var st := list.style
	var enc := world.combat
	var all := rows(world)
	var shown := mini(all.size(), HudPlace.TRACKER_ROWS)
	var box := place(all.size(), rect, avoid)
	var bg := st.colour("PANEL_BG")
	bg.a = 225.0 / 255.0
	list.fill(box, bg)
	list.frame(box, st.colour("DANGER"), 1)
	var x := box.position.x + 10
	var y := box.position.y + 6
	list.text("COMBAT", x, y, st.colour("DANGER"))
	var rnd := "round %d" % maxi(1, enc.round)
	list.text(rnd, box.end.x - 10 - st.width("small", rnd), y + 2, st.colour("TEXT_DIM"), "small")
	y += 24
	var you_shown := false
	for i in shown:
		var row: Dictionary = all[i]
		var you: bool = row["you"]
		if you:
			you_shown = true
			list.fill(Rect2i(box.position.x + 2, y - 1, box.size.x - 4, 38), st.colour("YOU_ROW"))
		var colour := st.colour("ACCENT") if you else UiColours.of(row["colour"])
		var hp: String = row["hp"]
		var hp_w := st.width("small", hp)
		var room := box.end.x - 18 - hp_w - (x - 6)
		var prefix := (">" if you else " ") + PyFmt.rjust(str(row["total"]), 3) + " "
		list.text(fit_name(st, prefix, row["name"], room), x - 6, y, colour, "small")
		list.text(hp, box.end.x - 10 - hp_w, y, st.colour("TEXT") if you else st.colour("TEXT_DIM"), "small")
		y += 18
		if you:
			y = _pip_row(list, enc, x + 26, y) + 2
	if all.size() > shown:
		list.text("  +%d more" % (all.size() - shown), x, y, st.colour("TEXT_DIM"), "small")
		y += 16
	if not you_shown:
		y = _pip_row(list, enc, x, y)
	list.text("Space ends your turn", x, box.end.y - 18, st.colour("TEXT_DIM"), "small")
	return box

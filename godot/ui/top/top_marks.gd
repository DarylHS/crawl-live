class_name TopMarks
extends Node2D
## The glyphs and boxes on the top-down map (crawler/ui/hud.py `draw_map`, everything but the
## terrain): `>` over stairwells and a glyph for each piece of furniture on tiles you have seen
## (dim grey out of sight), items and monsters in view, a tier-coloured box round each boss, a red
## health bar under any monster that has lost HP, orange corner brackets round a monster that
## stepping away from would give a free swing (`world.threats()`), then your pet and you.
##
## Glyphs are drawn centred in their 16 px tile with a monospace bold font (UiFonts); the map
## node scrolls, so positions here are plain tile x 16.

static var _hud: Dictionary = Content.table("ui_config")["hud"]
static var TILE: int = Content.table("ui_config")["layout"]["TILE"]
static var TIER_COLOURS: Dictionary = _hud["TIER_COLOURS"]
static var FURNITURE: Dictionary = _hud["FURNITURE_GLYPHS"]

const BRACKET_LEN := 5

var world: World = null
var cam: Vector2i = Vector2i.ZERO
var _font: Font = UiFonts.mono(true)
var drawn: Dictionary = {}     ## what the last draw put on the map, for tests: counts by kind


func set_world(w: World, cam_tile: Vector2i) -> void:
	world = w
	cam = cam_tile
	queue_redraw()


func _in_window(x: int, y: int) -> bool:
	return x >= cam.x and y >= cam.y and x < cam.x + TopView.VIEW_W and y < cam.y + TopView.VIEW_H


## Draw `ch` centred in tile (tx, ty) (Renderer._blit_glyph).
func _glyph(ch: String, colour: Color, tx: int, ty: int) -> void:
	var size := TILE
	var w := _font.get_string_size(ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var asc := _font.get_ascent(size)
	var desc := _font.get_descent(size)
	var pos := Vector2(tx * TILE + TILE / 2.0 - w / 2.0, ty * TILE + TILE / 2.0 + (asc - desc) / 2.0)
	draw_string(_font, pos, ch, HORIZONTAL_ALIGNMENT_LEFT, -1, size, colour)


func _draw() -> void:
	drawn = {"glyphs": 0, "boxes": 0, "brackets": 0, "bars": 0}
	var w := world
	if w == null:
		return
	var f := w.floor
	var dim := UiColours.c("TEXT_DIM")
	var open_stairs := not w.stairs_locked
	for s in f.stairs:
		if f.explored[s.y][s.x] != 0 and _in_window(s.x, s.y):
			var lit := w.visible.has(s)
			var c := (UiColours.c("ACCENT") if open_stairs else UiColours.c("DANGER")) if lit else dim
			_glyph(">", c, s.x, s.y)
			drawn["glyphs"] += 1
	for t: Vector2i in f.furniture:
		if f.explored[t.y][t.x] != 0 and _in_window(t.x, t.y):
			var fg: Dictionary = FURNITURE[f.furniture[t]]
			_glyph(fg["glyph"], UiColours.of(fg["colour"]) if w.visible.has(t) else dim, t.x, t.y)
			drawn["glyphs"] += 1
	for t: Vector2i in w.floor_items:
		if w.visible.has(t) and _in_window(t.x, t.y):
			var keys: Array = w.floor_items[t]
			var k: String = keys[keys.size() - 1]
			_glyph(Items.glyph(k), UiColours.of(Content.item(k)["colour"]), t.x, t.y)
			drawn["glyphs"] += 1
	var threats := w.threats()          # combat: stepping out of their reach provokes
	for m in w.monsters:
		if not w.visible.has(Vector2i(m.x, m.y)) or not _in_window(m.x, m.y):
			continue
		var px: int = m.x * TILE
		var py: int = m.y * TILE
		if m.boss:
			var tc: Array = TIER_COLOURS.get(m.tier, Content.table("ui_config")["colours"]["DANGER"])
			draw_rect(Rect2(px + 0.5, py + 0.5, TILE - 1, TILE - 1), UiColours.of(tc), false, 1.0)
			drawn["boxes"] += 1
		if threats.has(m):
			_provoke_marker(px, py)
			drawn["brackets"] += 1
		_glyph(m.glyph, UiColours.of(m.colour), m.x, m.y)
		drawn["glyphs"] += 1
		if m.hp < m.max_hp:
			var bw := int((TILE - 2) * m.hp / float(m.max_hp))
			draw_rect(Rect2(px + 1, py + TILE - 2, bw, 2), UiColours.c("DANGER"))
			drawn["bars"] += 1
	var pet := w.active_pet
	if pet != null and _in_window(pet.x, pet.y):
		_glyph(pet.glyph, UiColours.of(pet.colour), pet.x, pet.y)
		drawn["glyphs"] += 1
	var p := w.player
	_glyph(p.glyph, UiColours.of(p.colour), p.x, p.y)
	drawn["glyphs"] += 1


## Orange corner brackets just outside the tile: stepping away provokes it. Brackets, not a box,
## so it can't be mistaken for the 1 px boss tier box.
func _provoke_marker(px: int, py: int) -> void:
	var c := UiColours.c("WARN")
	var x0 := px - 2
	var y0 := py - 2
	var x1 := px + TILE + 1
	var y1 := py + TILE + 1
	for corner in [[x0, y0, 1, 1], [x1, y0, -1, 1], [x0, y1, 1, -1], [x1, y1, -1, -1]]:
		var x: int = corner[0]
		var y: int = corner[1]
		var sx: int = corner[2]
		var sy: int = corner[3]
		draw_line(Vector2(x, y), Vector2(x + sx * BRACKET_LEN, y), c, 2.0)
		draw_line(Vector2(x, y), Vector2(x, y + sy * BRACKET_LEN), c, 2.0)

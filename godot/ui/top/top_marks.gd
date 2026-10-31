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
##
## In the "tiles" zoom (P9, `set_mode(true)`) the same things are drawn as 32 px pictures from SpriteArt
## instead of glyphs (stairs, furniture, items, creatures, your pet and you, one picture per race for you), with
## the boxes, brackets and bars scaled to match: a 2 px tier box (3 px for a Headliner), brackets 3 px wide and
## 10 px long hugging the tile, a 4 px health bar. Remembered tiles dim their stairs and furniture.

static var _hud: Dictionary = Content.table("ui_config")["hud"]
static var TILE: int = Content.table("ui_config")["layout"]["TILE"]
static var TIER_COLOURS: Dictionary = _hud["TIER_COLOURS"]
static var FURNITURE: Dictionary = _hud["FURNITURE_GLYPHS"]

const BRACKET_LEN := 5
const ART_TILE := 32
const ART_DIM := Color(0.5, 0.5, 0.56)

var art_mode: bool = false
var _textures: Dictionary = {}   ## cache key -> ImageTexture
var _tex_gen: int = -1

var world: World = null
var cam: Vector2i = Vector2i.ZERO
var _font: Font = UiFonts.mono(true)
var drawn: Dictionary = {}     ## what the last draw put on the map, for tests: counts by kind


func _init() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Switch between the glyph overview and the 32 px pictures.
func set_mode(art: bool) -> void:
	art_mode = art
	queue_redraw()


func set_world(w: World, cam_tile: Vector2i) -> void:
	world = w
	cam = cam_tile
	queue_redraw()


func _in_window(x: int, y: int) -> bool:
	var cols := TopView.ART_VIEW_W if art_mode else TopView.VIEW_W
	var rows := TopView.ART_VIEW_H if art_mode else TopView.VIEW_H
	return x >= cam.x and y >= cam.y and x < cam.x + cols and y < cam.y + rows


## A cached texture for a picture; `make` builds the Image on a miss.
func _tex(key: String, make: Callable) -> Texture2D:
	if _tex_gen != SpriteArt.generation:
		_textures.clear()
		_tex_gen = SpriteArt.generation
	if not _textures.has(key):
		_textures[key] = ImageTexture.create_from_image(make.call())
	return _textures[key]


func _stairs_image(locked: bool) -> Image:
	var art := SpriteArt.supplied("tile:stairs_locked" if locked else "tile:stairs_open")
	return art if art != null else SpriteArt.stairs(locked)


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
	if art_mode:
		_draw_art(w)
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
		# pygame's width 2 line fills rows y and y + 1 (columns x and x + 1) and is 6 px long
		draw_rect(Rect2(mini(x, x + BRACKET_LEN * sx), y, BRACKET_LEN + 1, 2), c)
		draw_rect(Rect2(x, mini(y, y + BRACKET_LEN * sy), 2, BRACKET_LEN + 1), c)


# --- The 32 px tiles zoom ---------------------------------------------------------------------

func _draw_art(w: World) -> void:
	var f := w.floor
	var T := ART_TILE
	var locked := w.stairs_locked
	for s in f.stairs:
		if f.explored[s.y][s.x] != 0 and _in_window(s.x, s.y):
			var tex := _tex("stairs:%s" % locked, func() -> Image: return _stairs_image(locked))
			draw_texture(tex, Vector2(s * T), Color.WHITE if w.visible.has(s) else ART_DIM)
			drawn["glyphs"] += 1
	for t: Vector2i in f.furniture:
		if f.explored[t.y][t.x] != 0 and _in_window(t.x, t.y):
			var kind: String = f.furniture[t]
			var tex := _tex("furn:" + kind, func() -> Image: return SpriteArt.furniture(kind))
			draw_texture(tex, Vector2(t * T), Color.WHITE if w.visible.has(t) else ART_DIM)
			drawn["glyphs"] += 1
	for t: Vector2i in w.floor_items:
		if w.visible.has(t) and _in_window(t.x, t.y):
			var keys: Array = w.floor_items[t]
			var k: String = keys[keys.size() - 1]
			draw_texture(_tex("item:" + k, func() -> Image: return SpriteArt.item(k)), Vector2(t * T))
			drawn["glyphs"] += 1
	var threats := w.threats()
	for m in w.monsters:
		if not w.visible.has(Vector2i(m.x, m.y)) or not _in_window(m.x, m.y):
			continue
		var px: int = m.x * T
		var py: int = m.y * T
		if m.boss:
			var tc: Array = TIER_COLOURS.get(m.tier, Content.table("ui_config")["colours"]["DANGER"])
			var bw := 3 if m.tier == "headliner" else 2
			draw_rect(Rect2(px + bw / 2.0, py + bw / 2.0, T - bw, T - bw), UiColours.of(tc), false, float(bw))
			drawn["boxes"] += 1
		if threats.has(m):
			_provoke_marker_art(px, py)
			drawn["brackets"] += 1
		var mkey := SpriteArt.monster_key(m)
		var mcol: Array = m.colour
		var tier: String = m.tier
		draw_texture(_tex("%s|%s|%s" % [mkey, mcol, tier],
				func() -> Image: return SpriteArt.creature(mkey, mcol, tier)), Vector2(px, py))
		drawn["glyphs"] += 1
		if m.hp < m.max_hp:
			var bar_w := int((T - 4) * m.hp / float(m.max_hp))
			draw_rect(Rect2(px + 2, py + T - 4, T - 4, 4), Color(0.1, 0.04, 0.05, 0.85))
			draw_rect(Rect2(px + 2, py + T - 4, bar_w, 4), UiColours.c("DANGER"))
			drawn["bars"] += 1
	var pet := w.active_pet
	if pet != null and _in_window(pet.x, pet.y):
		var species: String = pet.species
		var pcol: Array = pet.colour
		draw_texture(_tex("pet:%s|%s" % [species, pcol],
				func() -> Image: return SpriteArt.creature("pet:" + species, pcol)), Vector2(pet.x * T, pet.y * T))
		drawn["glyphs"] += 1
	var p := w.player
	var race: String = String(w.race) if PyMath.truthy(w.race) else ""     # "" until a race is chosen
	draw_texture(_tex("player:" + race, func() -> Image: return SpriteArt.player(race)), Vector2(p.x * T, p.y * T))
	drawn["glyphs"] += 1


## The provoke brackets scaled for 32 px tiles: orange L shapes 3 px wide and 10 px long just outside each corner.
func _provoke_marker_art(px: int, py: int) -> void:
	var c := UiColours.c("WARN")
	var T := ART_TILE
	var th := 3
	var ln := 10
	var x0 := px - 4
	var y0 := py - 4
	var x1 := px + T + 4
	var y1 := py + T + 4
	draw_rect(Rect2(x0, y0, ln, th), c)
	draw_rect(Rect2(x0, y0, th, ln), c)
	draw_rect(Rect2(x1 - ln, y0, ln, th), c)
	draw_rect(Rect2(x1 - th, y0, th, ln), c)
	draw_rect(Rect2(x0, y1 - th, ln, th), c)
	draw_rect(Rect2(x0, y1 - ln, th, ln), c)
	draw_rect(Rect2(x1 - ln, y1 - th, ln, th), c)
	draw_rect(Rect2(x1 - th, y1 - ln, th, ln), c)

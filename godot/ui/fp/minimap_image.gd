class_name MinimapImage
extends RefCounted
## The first-person minimap as pixels (crawler/ui/firstperson.py `_minimap`, `_explored_layer`,
## `minimap_window`). Headless: it only makes an Image, which the Minimap node shows, so tests read
## the pixels as pytest did.
##
## The explored part of the floor is kept in one image per floor, with only the tiles that
## changed redrawn (the cache follows the floor object, not its id). Each redraw copies the window
## (MM_WINDOW tiles centred on you, clamped to the floor, MM_SCALE pixels a tile) out of it and
## paints on top: floor in view (lighter), stairwells you have seen (gold, red while locked or
## sealed), a white arrow at your tile pointing the way you look (free look angle), and monsters
## in view (red) over the arrow.

static var _cfg: Dictionary = Content.table("ui_config")["firstperson"]
static var WINDOW: Array = _cfg["MM_WINDOW"]       ## tiles shown around you
static var SCALE: int = _cfg["MM_SCALE"]           ## pixels per tile
static var BACK: Color = _c(_cfg["MM_BACK"])       ## unexplored (translucent black)
static var FLOOR: Color = _c(_cfg["MM_FLOOR"])     ## explored floor
static var SAFE: Color = _c(_cfg["MM_SAFE"])       ## explored safe room
static var IN_VIEW: Color = _c(_cfg["MM_IN_VIEW"]) ## floor you can see right now
static var SAFE_IN_VIEW: Color = _c(_cfg["MM_SAFE_IN_VIEW"])
static var _colours: Dictionary = Content.table("ui_config")["colours"]

var floor_ref: DungeonFloor = null    ## the floor the cache belongs to (Python `_mm_floor`)
var seen: Array = []                  ## explored rows at the last redraw (Python `_mm_seen`)
var origin: Vector2i = Vector2i.ZERO  ## top-left tile of the last window
var image: Image = null               ## the last window drawn, WINDOW x SCALE pixels (or the floor's)
var _layer: Image = null              ## the explored part of the whole floor


static func _c(a: Array) -> Color:
	return Color8(a[0], a[1], a[2], a[3] if a.size() > 3 else 255)


static func colour(name: String) -> Color:
	var a: Array = _colours[name]
	return Color8(a[0], a[1], a[2])


## Top-left tile and size (in tiles) of the window: MM_WINDOW centred on you, clamped to the floor.
static func window(world: World) -> Rect2i:
	var f := world.floor
	var p := world.player
	var w := mini(int(WINDOW[0]), f.width)
	var h := mini(int(WINDOW[1]), f.height)
	var ox := mini(maxi(0, p.x - w / 2), f.width - w)
	var oy := mini(maxi(0, p.y - h / 2), f.height - h)
	return Rect2i(ox, oy, w, h)


## The pixel at the middle of tile (x, y) in the last image (the tile must be in the window).
func pixel(x: int, y: int) -> Color:
	assert(x >= origin.x and y >= origin.y and (x - origin.x) * SCALE < image.get_width() \
			and (y - origin.y) * SCALE < image.get_height(), "tile outside the minimap")
	return image.get_pixel((x - origin.x) * SCALE, (y - origin.y) * SCALE)


## Redraw for the world and the look angle (degrees, 0 north) and return the image.
func redraw(world: World, angle: float) -> Image:
	var f := world.floor
	var s := SCALE
	var win := window(world)
	origin = win.position
	_update_layer(f)
	var mm := Image.create_empty(win.size.x * s, win.size.y * s, false, Image.FORMAT_RGBA8)
	mm.blit_rect(_layer, Rect2i(win.position * s, win.size * s), Vector2i.ZERO)
	var canvas := PixelCanvas.new(0, mm)

	var cell := func(x: int, y: int, c: Color) -> void:
		if win.has_point(Vector2i(x, y)):
			mm.fill_rect(Rect2i((x - win.position.x) * s, (y - win.position.y) * s, s, s), c)

	for t: Vector2i in world.visible:
		if f.in_bounds(t.x, t.y) and f.tiles[t.y][t.x] != DungeonFloor.WALL:
			cell.call(t.x, t.y, SAFE_IN_VIEW if f.safe[t.y][t.x] != 0 else IN_VIEW)
	var stairs_c := colour("DANGER") if world.stairs_locked or world.exit_sealed else colour("ACCENT")
	for st in f.stairs:
		if f.explored[st.y][st.x] != 0:
			cell.call(st.x, st.y, stairs_c)
	var p := world.player
	var a := deg_to_rad(angle)
	var fx := sin(a)
	var fy := -cos(a)                                   # follows the free look angle
	var cx := (p.x - win.position.x) * s + s / 2.0
	var cy := (p.y - win.position.y) * s + s / 2.0
	var tip := Vector2(cx + fx * 9, cy + fy * 9)
	var left := Vector2(cx - fx * 3 + fy * 5, cy - fy * 3 - fx * 5)
	var right := Vector2(cx - fx * 3 - fy * 5, cy - fy * 3 + fx * 5)
	var tri: Array[Vector2] = [tip, left, right]
	canvas.polygon(tri, Color.WHITE)
	canvas.polygon_outline(tri, Color8(10, 8, 14))
	for m in world.monsters:                            # on top of the arrow, so both show
		if world.visible.has(Vector2i(m.x, m.y)):
			cell.call(m.x, m.y, colour("DANGER"))
	image = mm
	return mm


## Bring the per-floor explored image up to date; only changed rows and tiles are touched.
func _update_layer(f: DungeonFloor) -> void:
	var s := SCALE
	if floor_ref != f:
		floor_ref = f
		_layer = Image.create_empty(f.width * s, f.height * s, false, Image.FORMAT_RGBA8)
		_layer.fill(BACK)
		seen = []
		for _y in f.height:
			var blank := PackedByteArray()
			blank.resize(f.width)
			seen.append(blank)
	for y in f.height:
		var row: PackedByteArray = f.explored[y]
		var old: PackedByteArray = seen[y]
		if row == old:
			continue
		for x in f.width:
			if row[x] == old[x]:
				continue
			var c: Color
			if row[x] == 0:
				c = BACK
			elif f.tiles[y][x] == DungeonFloor.WALL:
				continue
			else:
				c = SAFE if f.safe[y][x] != 0 else FLOOR
			_layer.fill_rect(Rect2i(x * s, y * s, s, s), c)
		seen[y] = row.duplicate()

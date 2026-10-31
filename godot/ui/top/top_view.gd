class_name TopView
extends Control
## The top-down map view (scenes/top_view.tscn; crawler/ui/hud.py `Renderer.draw_map`), in two zooms
## (P9, art bible section 7 question 1), both filling the 1024 x 640 map area:
##
##   "tiles"   (the default) 32 px art tiles, a 32 x 20 tile window: DCSS-based terrain per floor theme
##             (tinted like the first-person walls), furniture, stairs, items, creatures, you and your
##             pet as sprites, with the tier boxes, provoke brackets and health bars scaled up.
##   "glyphs"  the 16 px glyph overview, 64 x 40 tiles of a 120 x 76 floor, identical to the pygame
##             version pixel for pixel (its tests and pairing tools use this one).
##
## The Z key (action `zoom_map`, AppState.toggle_zoom) switches; `set_zoom` applies it.
##
## Scene tree:
##   TopView (Control, clips to 1024 x 640, this script)
##     Background (ColorRect, the BG colour)
##     Map (Node2D, moved to scroll: position = -camera tile x 16)
##       Terrain (TileMapLayer: wall, floor and safe-room tiles, lit or dim; unseen tiles are empty)
##       Marks (TopMarks: stairs and furniture glyphs, items, monsters with boss tier boxes, health
##              bars and orange provoke brackets, the pet and you, drawn with `_draw`)
##
## Fog of war: a tile you have seen is drawn dim, one in your line of sight lit, as pygame (two colours
## per kind in the TileSet, not a darkening effect). Only the tiles in the camera window are
## kept up to date, and only the ones that changed are written. The camera is Renderer._camera:
## centred on you and clamped to the floor (`camera`).

static var _layout: Dictionary = Content.table("ui_config")["layout"]
static var TILE: int = _layout["TILE"]
static var VIEW_W: int = _layout["VIEW_W"]      ## tiles across the map
static var VIEW_H: int = _layout["VIEW_H"]      ## tiles down the map

## Atlas column of each tile kind in the generated TileSet.
const WALL_LIT := 0
const WALL_DIM := 1
const FLOOR_LIT := 2
const FLOOR_DIM := 3
const SAFE_LIT := 4
const SAFE_DIM := 5
## Art tile set only (the glyph tile set has no art): a safe room's wall edge and the second brick variant.
const SAFE_WALL_LIT := 6
const SAFE_WALL_DIM := 7
const WALL_B_LIT := 8
const WALL_B_DIM := 9

const ART_TILE := 32                ## the art tiles' size in pixels
const ART_VIEW_W := 32              ## tiles across the map in the "tiles" zoom
const ART_VIEW_H := 20
const DIM_K := 0.46                 ## remembered tiles are drawn at this share of their lit brightness (pygame's WALL_DIM / WALL_LIT)

@onready var terrain: TileMapLayer = $Map/Terrain
@onready var marks: TopMarks = $Map/Marks
@onready var map_node: Node2D = $Map

var controller := TopController.new()
var input_enabled: bool = true
var active: bool = true
var hud: bool = true                 ## false while a menu covers the view (dims it)
var tile_px: int = TILE             ## pixels per tile now: 16 (glyphs) or 32 (tiles)
var view_w: int = VIEW_W            ## tiles across now
var view_h: int = VIEW_H            ## tiles down now
var art_mode: bool = false          ## true in the "tiles" zoom
var cam_tile: Vector2i = Vector2i.ZERO   ## top-left tile of the window drawn last
var written: int = 0                 ## tiles written to the TileMapLayer by the last refresh (tests, timings)
var _floor: DungeonFloor = null
var _state: PackedByteArray = PackedByteArray()   ## per tile: atlas column + 1 last written, 0 = empty
var _safe_wall: PackedByteArray = PackedByteArray()   ## per tile: 1 for a wall touching a safe-room floor (art tiles only)
var _art_depth: int = -1            ## the depth the art tile set was built for
var _art_gen: int = -1              ## the SpriteArt.generation it was built from
signal new_run_requested
signal acted                       ## a key was used (the parent runs its follow-up: first-person facing, run logging)


func _ready() -> void:
	terrain.tile_set = build_tile_set()
	terrain.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	custom_minimum_size = Vector2(VIEW_W * TILE, VIEW_H * TILE)
	clip_contents = true


## Choose the zoom: "tiles" (32 px art, 32 x 20 tiles) or "glyphs" (the 16 px overview, 64 x 40).
func set_zoom(zoom: String) -> void:
	var want := zoom == "tiles"
	if want == art_mode and terrain.tile_set != null:
		return
	art_mode = want
	tile_px = ART_TILE if want else TILE
	view_w = ART_VIEW_W if want else VIEW_W
	view_h = ART_VIEW_H if want else VIEW_H
	_floor = null                         # start the terrain over with the other tile set
	_art_depth = -1
	if not want:
		terrain.tile_set = build_tile_set()
	marks.set_mode(want)
	if world != null and active:
		refresh()


## The zoom now: "tiles" or "glyphs".
var zoom: String:
	get:
		return "tiles" if art_mode else "glyphs"


var world: World:
	get:
		return controller.world


## Show a new or loaded run.
func start(new_world: World) -> void:
	controller.start(new_world)
	refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not input_enabled or not active or world == null:
		return
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if world.state != "playing":
		if event.is_action_pressed(&"descend"):
			new_run_requested.emit()
			get_viewport().set_input_as_handled()
		return
	var action := &""
	if key.unicode == 62:
		action = &"descend"
	else:
		for a in TopController.ORDER:
			if event.is_action_pressed(a):
				action = a
				break
	if action != &"" and controller.press(action):
		acted.emit()
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if world != null:
		refresh()


## Show or hide the whole view; hidden, it stops updating.
func set_active(on: bool) -> void:
	active = on
	visible = on
	process_mode = Node.PROCESS_MODE_INHERIT if on else Node.PROCESS_MODE_DISABLED
	if on and world != null:
		refresh()


## Top-left tile of the visible window: centred on the player, clamped to the floor (Renderer._camera).
## `cols` x `rows` is the window in tiles: the 64 x 40 glyph overview by default, 32 x 20 for the art tiles.
static func camera(w: World, cols: int = VIEW_W, rows: int = VIEW_H) -> Vector2i:
	var f := w.floor
	var p := w.player
	return Vector2i(
			mini(maxi(0, p.x - cols / 2), maxi(0, f.width - cols)),
			mini(maxi(0, p.y - rows / 2), maxi(0, f.height - rows)))


## The window in tiles and the tile size of a zoom: [cols, rows, pixels].
static func metrics(zoom_name: String) -> Array:
	return [ART_VIEW_W, ART_VIEW_H, ART_TILE] if zoom_name == "tiles" else [VIEW_W, VIEW_H, TILE]


## Bring the map up to date with the world: scroll, write changed tiles, redraw the glyphs.
func refresh() -> void:
	var w := world
	if w == null:
		return
	var art_stale := art_mode and (_art_depth != w.depth or _art_gen != SpriteArt.generation)
	if _floor != w.floor or art_stale:
		_floor = w.floor
		terrain.clear()
		_state = PackedByteArray()
		_state.resize(w.floor.width * w.floor.height)
		if art_mode:
			_art_depth = w.depth
			_art_gen = SpriteArt.generation
			terrain.tile_set = build_art_tile_set(w.depth)
			_safe_wall = _safe_wall_mask(w.floor)
	cam_tile = camera(w, view_w, view_h)
	map_node.position = Vector2(-cam_tile * tile_px)
	written = _sync_terrain(w)
	marks.set_world(w, cam_tile)
	modulate = Color.WHITE                  # Python never dims the map view; only the 3D view darkens itself


## Write the tiles of the window whose look changed; returns how many were written.
func _sync_terrain(w: World) -> int:
	var f := w.floor
	var vis := w.visible
	var n := 0
	for y in range(cam_tile.y, mini(f.height, cam_tile.y + view_h)):
		var row: PackedByteArray = f.tiles[y]
		var safe_row: PackedByteArray = f.safe[y]
		var seen_row: PackedByteArray = f.explored[y]
		for x in range(cam_tile.x, mini(f.width, cam_tile.x + view_w)):
			var want := 0
			if seen_row[x] != 0:
				var lit := vis.has(Vector2i(x, y))
				if row[x] == DungeonFloor.WALL:
					if not art_mode:
						want = WALL_LIT if lit else WALL_DIM
					elif _safe_wall[y * f.width + x] != 0:
						want = SAFE_WALL_LIT if lit else SAFE_WALL_DIM
					elif _wall_b(x, y):
						want = WALL_B_LIT if lit else WALL_B_DIM
					else:
						want = WALL_LIT if lit else WALL_DIM
				elif safe_row[x] != 0:
					want = SAFE_LIT if lit else SAFE_DIM
				else:
					want = FLOOR_LIT if lit else FLOOR_DIM
				want += 1
			var i := y * f.width + x
			if _state[i] == want:
				continue
			_state[i] = want
			n += 1
			if want == 0:
				terrain.erase_cell(Vector2i(x, y))
			else:
				terrain.set_cell(Vector2i(x, y), 0, Vector2i(want - 1, 0))
	return n


## The atlas column a tile is drawn with now (tests): "wall"/"floor"/"safe" and lit or dim, or
## -1 when unseen. Reads what the TileMapLayer holds.
func tile_kind_at(x: int, y: int) -> int:
	var data := terrain.get_cell_atlas_coords(Vector2i(x, y))
	return data.x if terrain.get_cell_source_id(Vector2i(x, y)) >= 0 else -1


## The first-person view's hash: one wall block in three uses the second brick picture, so both views agree.
static func _wall_b(x: int, y: int) -> bool:
	return (((x * 73856093) ^ (y * 19349663)) & 0x7fffffff) % 3 == 0


## 1 for every wall tile next to a safe-room floor tile (its edge, drawn pale like the room).
static func _safe_wall_mask(f: DungeonFloor) -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(f.width * f.height)
	for y in f.height:
		var safe_row: PackedByteArray = f.safe[y]
		var row: PackedByteArray = f.tiles[y]
		for x in f.width:
			if safe_row[x] == 0 or row[x] == DungeonFloor.WALL:
				continue
			for n in DungeonFloor.NEIGHBOURS_8:
				var nx := x + n.x
				var ny := y + n.y
				if f.in_bounds(nx, ny) and f.tiles[ny][nx] == DungeonFloor.WALL:
					mask[ny * f.width + nx] = 1
	return mask


## The art TileSet for a floor: 32 px DCSS-based tiles (walls in two variants, floor, safe floor, safe
## wall), lit and dim columns sharing one picture; the dim columns and the floor's tint are the tiles'
## `modulate`, so fog of war and the per-floor tint are not baked into the art (art bible section 2). Safe
## rooms are never tinted. A kind with no art falls back to a flat colour like the glyph map's.
static func build_art_tile_set(depth: int) -> TileSet:
	var t := ART_TILE
	var tint := FpLogic.depth_tint(depth)
	var kinds: Array[Array] = [   # [art key, fallback colour name, tinted, full cell]
		["tile:%d:wall_0" % depth, "WALL_LIT", true, true],
		["tile:%d:floor" % depth, "FLOOR_LIT", true, false],
		["tile:safe_floor", "SAFE_LIT", false, false],
		["tile:safe_wall", "SAFE_LIT", false, true],
		["tile:%d:wall_1" % depth, "WALL_LIT", true, true]]
	var atlas := Image.create_empty(t * 10, t, false, Image.FORMAT_RGBA8)
	var order := [0, 1, 2, 3, 4]               # pair p fills columns for lit/dim: wall, floor, safe, safe wall, wall b
	var cols := [[WALL_LIT, WALL_DIM], [FLOOR_LIT, FLOOR_DIM], [SAFE_LIT, SAFE_DIM],
			[SAFE_WALL_LIT, SAFE_WALL_DIM], [WALL_B_LIT, WALL_B_DIM]]
	for p in order:
		var k: Array = kinds[p]
		var img := SpriteArt.supplied(k[0])
		if img == null and p == 4:
			img = SpriteArt.supplied(kinds[0][0])
		if img == null:
			img = Image.create_empty(t, t, false, Image.FORMAT_RGBA8)
			var inset := 0 if k[3] else 1
			img.fill_rect(Rect2i(0, 0, t - inset, t - inset), UiColours.c(k[1]))
		elif img.get_width() != t or img.get_height() != t:
			img = img.duplicate()
			img.resize(t, t, Image.INTERPOLATE_NEAREST)
		for c: int in cols[p]:
			atlas.blit_rect(img, Rect2i(0, 0, t, t), Vector2i(c * t, 0))
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(atlas)
	src.texture_region_size = Vector2i(t, t)
	for i in 10:
		src.create_tile(Vector2i(i, 0))
	for p in order:
		var colour := tint if kinds[p][2] else Color.WHITE
		src.get_tile_data(Vector2i(cols[p][0], 0), 0).modulate = colour
		src.get_tile_data(Vector2i(cols[p][1], 0), 0).modulate = Color(colour.r * DIM_K, colour.g * DIM_K, colour.b * DIM_K, 1.0)
	var ts := TileSet.new()
	ts.tile_size = Vector2i(t, t)
	ts.add_source(src, 0)
	return ts


## The TileSet: one 16 px colour tile per kind and light. Walls fill the cell; floors are one pixel
## short on the right and bottom (the BG shows through as a grid line), as hud.py draws them.
static func build_tile_set() -> TileSet:
	var t := TILE
	var kinds: Array[Array] = [
		["WALL_LIT", true], ["WALL_DIM", true], ["FLOOR_LIT", false], ["FLOOR_DIM", false],
		["SAFE_LIT", false], ["SAFE_DIM", false]]
	var atlas := Image.create_empty(t * kinds.size(), t, false, Image.FORMAT_RGBA8)
	for i in kinds.size():
		var full: bool = kinds[i][1]
		var inset := 0 if full else 1
		atlas.fill_rect(Rect2i(i * t, 0, t - inset, t - inset), UiColours.c(kinds[i][0]))
	var src := TileSetAtlasSource.new()
	src.texture = ImageTexture.create_from_image(atlas)
	src.texture_region_size = Vector2i(t, t)
	for i in kinds.size():
		src.create_tile(Vector2i(i, 0))
	var ts := TileSet.new()
	ts.tile_size = Vector2i(t, t)
	ts.add_source(src, 0)
	return ts

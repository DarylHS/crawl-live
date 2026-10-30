class_name TopView
extends Control
## The top-down map view (scenes/top_view.tscn; crawler/ui/hud.py `Renderer.draw_map`): the same
## 16 px glyph grid as the pygame version, 64 x 40 tiles of a 120 x 76 floor.
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

@onready var terrain: TileMapLayer = $Map/Terrain
@onready var marks: TopMarks = $Map/Marks
@onready var map_node: Node2D = $Map

var controller := TopController.new()
var input_enabled: bool = true
var active: bool = true
var hud: bool = true                 ## false while a menu covers the view (dims it)
var cam_tile: Vector2i = Vector2i.ZERO   ## top-left tile of the window drawn last
var written: int = 0                 ## tiles written to the TileMapLayer by the last refresh (tests, timings)
var _floor: DungeonFloor = null
var _state: PackedByteArray = PackedByteArray()   ## per tile: atlas column + 1 last written, 0 = empty
signal new_run_requested


func _ready() -> void:
	terrain.tile_set = build_tile_set()
	custom_minimum_size = Vector2(VIEW_W * TILE, VIEW_H * TILE)
	clip_contents = true


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
static func camera(w: World) -> Vector2i:
	var f := w.floor
	var p := w.player
	return Vector2i(
			mini(maxi(0, p.x - VIEW_W / 2), maxi(0, f.width - VIEW_W)),
			mini(maxi(0, p.y - VIEW_H / 2), maxi(0, f.height - VIEW_H)))


## Bring the map up to date with the world: scroll, write changed tiles, redraw the glyphs.
func refresh() -> void:
	var w := world
	if w == null:
		return
	if _floor != w.floor:
		_floor = w.floor
		terrain.clear()
		_state = PackedByteArray()
		_state.resize(w.floor.width * w.floor.height)
	cam_tile = camera(w)
	map_node.position = Vector2(-cam_tile * TILE)
	written = _sync_terrain(w)
	marks.set_world(w, cam_tile)
	modulate = Color.WHITE if hud else Color(0.65, 0.65, 0.65)


## Write the tiles of the window whose look changed; returns how many were written.
func _sync_terrain(w: World) -> int:
	var f := w.floor
	var vis := w.visible
	var n := 0
	for y in range(cam_tile.y, mini(f.height, cam_tile.y + VIEW_H)):
		var row: PackedByteArray = f.tiles[y]
		var safe_row: PackedByteArray = f.safe[y]
		var seen_row: PackedByteArray = f.explored[y]
		for x in range(cam_tile.x, mini(f.width, cam_tile.x + VIEW_W)):
			var want := 0
			if seen_row[x] != 0:
				var lit := vis.has(Vector2i(x, y))
				if row[x] == DungeonFloor.WALL:
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

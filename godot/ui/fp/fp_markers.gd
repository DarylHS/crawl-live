class_name FpMarkers
extends Node3D
## PLACEHOLDER (P4 only; P5 replaces this file with ui/fp/billboards.gd and real sprites).
##
## Simple Sprite3D markers so the first-person view is playable: a blob with eyes for each visible
## monster (tier-coloured outline for bosses) and the pet, a small diamond for floor items, a
## floating arrow over stairwells (gold when open, red when locked) and a block for safe-room
## furniture. Sizes follow the art bible (monsters 0.62-0.71 tiles by HP, Acts 0.85 / 0.95,
## Headliners 1.0, pets 0.5, furniture 0.75, items 0.32), feet on the floor, only what the player
## can see (world.visible), as the Python view draws them. Sprites are billboards that turn about
## Y only, nearest-filtered, binary alpha.

const OUTLINE := Color8(14, 12, 18)

static var _fp_cfg: Dictionary = Content.table("ui_config")["firstperson"]
static var _furniture: Dictionary = Content.table("ui_config")["hud"]["FURNITURE_GLYPHS"]

var _textures: Dictionary = {}   ## cache key -> ImageTexture
var _pool: Array[Sprite3D] = []
var shown: int = 0               ## markers shown after the last sync (tests read it)


## Show markers for what the player can see now. Cheap enough to call every frame.
func sync(world: World) -> void:
	var specs: Array = []
	var vis := world.visible
	for tile in world.floor_items:
		if vis.has(tile):
			var keys: Array = world.floor_items[tile]
			var k: String = keys[keys.size() - 1]
			specs.append([tile, _item_tex(k), 0.32, 0.0])
	var locked := world.stairs_locked or world.exit_sealed
	for s in world.floor.stairs:
		if vis.has(s):
			specs.append([s, _stairs_tex(locked), 0.3, 0.55])
	for f in world.floor.furniture:
		if vis.has(f):
			specs.append([f, _furniture_tex(world.floor.furniture[f]), 0.75, 0.0])
	var pt := world.active_pet
	if pt != null and vis.has(Vector2i(pt.x, pt.y)):
		specs.append([Vector2i(pt.x, pt.y), _creature_tex("pet:" + pt.species, pt.colour, OUTLINE), 0.5, 0.0])
	for m in world.monsters:
		if vis.has(Vector2i(m.x, m.y)):
			var outline := OUTLINE
			if _fp_cfg["TIER_OUTLINE"].has(m.tier):
				var c: Array = _fp_cfg["TIER_OUTLINE"][m.tier]
				outline = Color8(c[0], c[1], c[2])
			var scale_v: float = _fp_cfg["TIER_SCALE"].get(m.tier, 0.62 + 0.03 * mini(m.max_hp, 12) / 4.0)
			var look: String = m.base if m.base != "" else m.key
			specs.append([Vector2i(m.x, m.y), _creature_tex("mon:%s:%s" % [look, m.tier], m.colour, outline), scale_v, 0.0])
	while _pool.size() < specs.size():
		var s := Sprite3D.new()
		s.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
		s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		s.shaded = false
		add_child(s)
		_pool.append(s)
	for i in _pool.size():
		var s := _pool[i]
		s.visible = i < specs.size()
		if not s.visible:
			continue
		var tile: Vector2i = specs[i][0]
		var tex: Texture2D = specs[i][1]
		var size_v: float = specs[i][2]
		s.texture = tex
		s.pixel_size = size_v / tex.get_height()
		s.position = Vector3(tile.x + 0.5, size_v / 2.0 + float(specs[i][3]), tile.y + 0.5)
	shown = specs.size()


func _cached(key: String, make: Callable) -> Texture2D:
	if not _textures.has(key):
		_textures[key] = ImageTexture.create_from_image(make.call())
	return _textures[key]


static func _col(c: Array) -> Color:
	return Color8(c[0], c[1], c[2])


## A 32 x 32 creature stand-in: a body and a lighter head in its colour, two eyes, an outline.
func _creature_tex(key: String, colour: Array, outline: Color) -> Texture2D:
	return _cached(key + str(outline), func() -> Image:
		var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
		var body := _col(colour)
		var head := body.lightened(0.2)
		for y in 32:
			for x in 32:
				var in_body := pow((x - 15.5) / 11.0, 2) + pow((y - 21.0) / 9.5, 2) <= 1.0
				var in_head := pow((x - 15.5) / 6.5, 2) + pow((y - 9.0) / 6.0, 2) <= 1.0
				if in_head:
					img.set_pixel(x, y, head)
				elif in_body:
					img.set_pixel(x, y, body.darkened(clampf((y - 14) / 40.0, 0.0, 0.3)))
		for ex in [13, 18]:
			img.set_pixel(ex, 9, Color.WHITE)
			img.set_pixel(ex, 10, Color8(20, 10, 10))
		_outline(img, outline)
		return img)


## A 16 x 16 item stand-in: a diamond in the item's colour.
func _item_tex(key: String) -> Texture2D:
	return _cached("item:" + key, func() -> Image:
		var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		var c := _col(Content.item(key)["colour"])
		for y in range(2, 15):
			for x in range(1, 15):
				if absf(x - 7.5) / 6.0 + absf(y - 8.5) / 6.0 <= 1.0:
					img.set_pixel(x, y, c)
		_outline(img, OUTLINE)
		return img)


## A 16 x 16 downward arrow: gold when the stairs are open, red when locked or sealed.
func _stairs_tex(locked: bool) -> Texture2D:
	return _cached("stairs:%s" % locked, func() -> Image:
		var img := Image.create_empty(16, 16, false, Image.FORMAT_RGBA8)
		var c := Color8(235, 80, 80) if locked else Color8(255, 196, 64)
		for y in range(5, 14):
			var half := (13 - y) * 5.0 / 8.0
			for x in 16:
				if absf(x - 7.5) <= half:
					img.set_pixel(x, y, c)
		if locked:                              # a padlock body on the arrow
			img.fill_rect(Rect2i(6, 7, 4, 3), Color8(40, 30, 30))
		_outline(img, Color8(60, 30, 10))
		return img)


## A 32 x 32 block in the furniture's map colour (bed, bench, counter).
func _furniture_tex(kind: String) -> Texture2D:
	return _cached("furniture:" + kind, func() -> Image:
		var img := Image.create_empty(32, 32, false, Image.FORMAT_RGBA8)
		var c := _col(_furniture[kind]["colour"])
		img.fill_rect(Rect2i(2, 14, 28, 10), c)
		img.fill_rect(Rect2i(3, 24, 3, 8), c.darkened(0.4))
		img.fill_rect(Rect2i(26, 24, 3, 8), c.darkened(0.4))
		_outline(img, OUTLINE)
		return img)


## A one-pixel outline round every opaque pixel (binary alpha, as the art bible asks).
static func _outline(img: Image, colour: Color) -> void:
	var w := img.get_width()
	var h := img.get_height()
	var edge: Array[Vector2i] = []
	for y in h:
		for x in w:
			if img.get_pixel(x, y).a > 0:
				continue
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var nx: int = x + d.x
				var ny: int = y + d.y
				if nx >= 0 and ny >= 0 and nx < w and ny < h and img.get_pixel(nx, ny).a > 0:
					edge.append(Vector2i(x, y))
					break
	for p in edge:
		img.set_pixelv(p, colour)

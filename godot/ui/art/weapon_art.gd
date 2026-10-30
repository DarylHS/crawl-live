class_name WeaponArt
extends RefCounted
## Placeholder first-person weapon view models (P8, owner decision 3 in docs/art-bible.md): hands in a
## contestant's sleeves holding the equipped weapon, Wolfenstein style, drawn in code on an 80 x 80
## canvas with hard pixels and the art bible's near-black outline. The grip is at the bottom centre
## (about x 44, y 62), so a swing can pivot there.
##
## SpriteArt.weapon_view picks these only when no real art is registered under `wpn:<item>` or
## `wpn:<style>`, so P9 drops pictures in without touching ViewModel. Each of the five starting
## weapons has its own shape; any other blade or blunt weapon gets a generic one by `style`, and bare
## hands get two fists. Every pixel is fully opaque or fully transparent (binary alpha).

const SIZE := 80
const EDGE := Color8(20, 16, 24)
const SKIN := Color8(226, 176, 134)
const SKIN_SHADE := Color8(186, 136, 100)
const SLEEVE := Color8(58, 68, 112)
const SLEEVE_SHADE := Color8(40, 48, 84)
const WOOD := Color8(138, 98, 58)
const WOOD_SHADE := Color8(98, 68, 40)


## The 80 x 80 picture for a weapon: `item_key` "" and style "unarmed" for bare fists.
static func paint(item_key: String, style: String) -> Image:
	var c := PixelCanvas.new(SIZE)
	var col := Color.WHITE
	var two_handed := false
	if item_key != "" and Items.items().has(item_key):
		var row: Dictionary = Items.items()[item_key]
		col = Color8(row["colour"][0], row["colour"][1], row["colour"][2])
	match item_key:
		"pan":
			_pan(c, col)
		"cleaver":
			_cleaver(c, col)
		"katana":
			_katana(c, col)
		"extinguisher":
			_extinguisher(c, col)
			two_handed = true
		"sledge":
			_sledge(c, col)
			two_handed = true
		_:
			if item_key == "" or style == "unarmed":
				_fists(c)
				return c.image
			if style == "blade":
				_sword(c, col)
			else:
				_club(c, col)
	if two_handed:
		_hand(c, 44, 44)                   # the upper hand first, so the lower sleeve and fist sit on top
	_hand(c, 44, 62)
	return c.image


static func _shade(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0))


## A rectangle with the one pixel outline.
static func _box(c: PixelCanvas, x: int, y: int, w: int, h: int, fill: Color) -> void:
	c.rect(x - 1, y - 1, w + 2, h + 2, EDGE)
	c.rect(x, y, w, h, fill)


## A fist gripping at (cx, cy) with the sleeve running down off the bottom of the picture.
static func _hand(c: PixelCanvas, cx: int, cy: int) -> void:
	c.polygon(_pts([[cx - 12, cy + 4], [cx + 12, cy + 4], [cx + 16, 80], [cx - 16, 80]]), EDGE)
	c.polygon(_pts([[cx - 10, cy + 6], [cx + 10, cy + 6], [cx + 14, 80], [cx - 14, 80]]), SLEEVE)
	c.rect(cx + 4, cy + 10, 6, 70 - cy, SLEEVE_SHADE)
	c.rect(cx - 12, cy + 3, 24, 4, EDGE)                              # cuff
	c.rect(cx - 11, cy + 4, 22, 2, Color8(210, 210, 220))
	c.ellipse(cx - 10, cy - 7, 20, 14, EDGE)                           # the fist
	c.ellipse(cx - 9, cy - 6, 18, 12, SKIN)
	c.rect(cx - 8, cy + 1, 16, 4, SKIN_SHADE)
	for i in 3:                                                        # knuckle gaps
		c.rect(cx - 6 + i * 5, cy - 6, 1, 6, SKIN_SHADE)
	c.rect(cx - 9, cy - 2, 5, 3, SKIN)                                 # thumb
	c.rect(cx - 9, cy - 2, 5, 1, SKIN_SHADE)


static func _fists(c: PixelCanvas) -> void:
	_hand_pair(c)


static func _hand_pair(c: PixelCanvas) -> void:
	_hand(c, 28, 58)
	_hand(c, 58, 52)


static func _pan(c: PixelCanvas, col: Color) -> void:
	_box(c, 42, 30, 5, 36, Color8(70, 66, 74))                        # handle
	c.circle(44, 20, 16, EDGE)                                        # pan
	c.circle(44, 20, 15, _shade(col, 0.7))
	c.circle(44, 20, 11, _shade(col, 0.95))
	c.rect(36, 12, 5, 3, _shade(col, 1.3))                            # a glint
	c.circle(44, 20, 2, _shade(col, 0.5))                             # the hanging hole


static func _cleaver(c: PixelCanvas, col: Color) -> void:
	_box(c, 42, 40, 6, 24, WOOD)
	c.rect(43, 42, 2, 20, WOOD_SHADE)
	_box(c, 36, 8, 20, 34, col)                                       # broad blade
	c.rect(51, 9, 4, 32, _shade(col, 0.7))                            # spine
	c.rect(37, 9, 2, 30, _shade(col, 1.25))                           # edge glint
	c.rect(40, 14, 3, 3, EDGE)                                        # hang hole


static func _katana(c: PixelCanvas, col: Color) -> void:
	c.polygon(_pts([[41, 52], [47, 52], [47, 8], [44, 1], [41, 8]]), EDGE)
	c.polygon(_pts([[42, 52], [46, 52], [46, 9], [44, 3], [42, 9]]), col)
	c.rect(42, 8, 1, 44, _shade(col, 1.3))
	c.rect(45, 12, 1, 40, _shade(col, 0.65))
	_box(c, 36, 52, 16, 4, Color8(230, 190, 70))                      # guard
	_box(c, 42, 56, 5, 18, Color8(52, 40, 64))                        # wrapped handle
	for i in 4:
		c.rect(42, 58 + i * 4, 5, 1, Color8(150, 120, 190))


static func _extinguisher(c: PixelCanvas, col: Color) -> void:
	_box(c, 34, 22, 22, 40, col)                                      # body
	c.rect(36, 24, 3, 36, _shade(col, 1.3))
	c.rect(51, 24, 4, 36, _shade(col, 0.65))
	c.rect(34, 36, 22, 4, Color8(240, 230, 210))                      # label band
	_box(c, 40, 12, 10, 10, Color8(70, 66, 74))                       # valve
	_box(c, 34, 12, 8, 4, Color8(30, 28, 34))                         # lever
	c.line(Vector2(51, 18), Vector2(62, 22), EDGE, 3)                 # hose
	c.line(Vector2(62, 22), Vector2(62, 40), EDGE, 3)
	_box(c, 60, 38, 6, 5, Color8(30, 28, 34))                         # nozzle


static func _sledge(c: PixelCanvas, col: Color) -> void:
	_box(c, 42, 24, 6, 50, WOOD)
	c.rect(43, 26, 2, 46, WOOD_SHADE)
	_box(c, 26, 4, 38, 22, col)                                       # heavy head
	c.rect(27, 5, 36, 3, _shade(col, 1.3))
	c.rect(27, 21, 36, 4, _shade(col, 0.6))
	_box(c, 24, 6, 4, 18, _shade(col, 0.8))                           # end caps
	_box(c, 62, 6, 4, 18, _shade(col, 0.8))


static func _sword(c: PixelCanvas, col: Color) -> void:
	c.polygon(_pts([[40, 52], [48, 52], [48, 10], [44, 2], [40, 10]]), EDGE)
	c.polygon(_pts([[41, 52], [47, 52], [47, 11], [44, 4], [41, 11]]), col)
	c.rect(42, 10, 1, 42, _shade(col, 1.3))
	_box(c, 34, 52, 20, 4, Color8(200, 160, 60))
	_box(c, 42, 56, 5, 16, WOOD)


static func _club(c: PixelCanvas, col: Color) -> void:
	_box(c, 41, 26, 6, 46, WOOD)
	_box(c, 34, 4, 20, 28, col)
	c.rect(36, 6, 3, 24, _shade(col, 1.3))
	c.rect(49, 6, 4, 24, _shade(col, 0.65))


static func _pts(a: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in a:
		out.append(Vector2(p[0], p[1]))
	return out

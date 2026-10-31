class_name HudCanvas
extends Control
## Paints a HudList: the one drawing node behind the side panel, log, tracker, toasts, labels and
## end overlay. It decides nothing; the models in ui/hud/ build the list and `show_list` swaps it in
## (redrawing only when it differs from what is already on screen).
##
## Text is drawn with the Theme's fonts at pygame's positions (top-left of the text, so the baseline is
## the font's ascent below), character by character at the face's whole-pixel advance. Frames are drawn inside their rectangle as pygame's `draw.rect(width=n)`.

var list: HudList = null
var _shown: Array = []


var _icons: Dictionary = {}         ## art key -> ImageTexture
var _icon_gen: int = -1


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## The picture for an art key (cached; forgotten when the art set changes), or null.
func _icon_texture(key: String) -> Texture2D:
	if _icon_gen != SpriteArt.generation:
		_icons.clear()
		_icon_gen = SpriteArt.generation
	if not _icons.has(key):
		var img := SpriteArt.supplied(key)
		_icons[key] = ImageTexture.create_from_image(img) if img != null else null
	return _icons[key]


## Show `new_list` (null or empty hides everything). Redraws only when the items changed.
func show_list(new_list: HudList) -> void:
	var items: Array = [] if new_list == null else new_list.items
	list = new_list
	if items == _shown:
		return
	_shown = items.duplicate()
	queue_redraw()


func _draw() -> void:
	if list == null:
		return
	var st := list.style
	for it: Dictionary in list.items:
		match it["k"]:
			"t":
				var face: String = it["f"]
				var font := st.font(face)
				var sz := st.face_size(face)
				var adv := st.advance(face)
				var base: float = it["y"] + font.get_ascent(sz)
				var s: String = it["s"]
				for i in s.length():                  # one character at a time, at pygame's whole-pixel advance
					if s[i] != " ":
						draw_char(font, Vector2(it["x"] + i * adv, base), s[i], sz, it["c"])
			"i":
				var tex := _icon_texture(it["key"])
				if tex != null:
					draw_texture_rect(tex, Rect2(it["r"]), false)
			"r":
				draw_rect(Rect2(it["r"]), it["c"])
			"f":
				var r: Rect2i = it["r"]
				var w: int = it["w"]
				var c: Color = it["c"]
				draw_rect(Rect2(r.position.x, r.position.y, r.size.x, w), c)
				draw_rect(Rect2(r.position.x, r.end.y - w, r.size.x, w), c)
				draw_rect(Rect2(r.position.x, r.position.y + w, w, r.size.y - 2 * w), c)
				draw_rect(Rect2(r.end.x - w, r.position.y + w, w, r.size.y - 2 * w), c)
			"p":
				draw_colored_polygon(it["pts"], it["c"])
			"pl":
				var pts: PackedVector2Array = it["pts"]
				var w: int = it["w"]
				var shift := Vector2(0.5, 0.5) if w % 2 == 1 else Vector2.ZERO    # odd widths sit on pixel centres
				var moved := PackedVector2Array()
				for pt in pts:
					moved.append(pt + shift)
				draw_polyline(moved, it["c"], float(w))

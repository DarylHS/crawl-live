class_name HudList
extends RefCounted
## A list of things to draw, in screen pixels (1280 x 768), built by the HUD models and painted by
## HudCanvas. Text is placed the way pygame places it: by its top-left corner, or centred / mid-top
## on a point using the font's line height. Every `add` returns the rectangle the thing covers so
## the models can lay out what follows, as `Renderer.text` returns its rect.
##
## Items are Dictionaries: {k: "t", x, y, s, c, f} text, {k: "r", r, c} filled rectangle,
## {k: "f", r, c, w} frame drawn inside r, {k: "p", pts, c} polygon.

var style: HudStyle
var items: Array = []


func _init(hud_style: HudStyle) -> void:
	style = hud_style


## Text with its top-left at (x, y).
func text(s: String, x: int, y: int, colour: Color, face: String = "font") -> Rect2i:
	items.append({"k": "t", "x": x, "y": y, "s": s, "c": colour, "f": face})
	return Rect2i(Vector2i(x, y), style.measure(face, s))


## Text centred on (cx, cy): pygame `get_rect(center=...)` (integer halves, rounded down).
func centred(s: String, cx: int, cy: int, colour: Color, face: String = "font") -> Rect2i:
	var m := style.measure(face, s)
	return text(s, cx - m.x / 2, cy - m.y / 2, colour, face)


## Text with the middle of its top edge at (cx, y): pygame `get_rect(midtop=...)`.
func midtop(s: String, cx: int, y: int, colour: Color, face: String = "font") -> Rect2i:
	var m := style.measure(face, s)
	return text(s, cx - m.x / 2, y, colour, face)


func fill(r: Rect2i, colour: Color) -> void:
	items.append({"k": "r", "r": r, "c": colour})


## A frame of width w drawn inside r (pygame `draw.rect(width=w)`).
func frame(r: Rect2i, colour: Color, w: int = 1) -> void:
	items.append({"k": "f", "r": r, "c": colour, "w": w})


func polygon(pts: PackedVector2Array, colour: Color) -> void:
	items.append({"k": "p", "pts": pts, "c": colour})


## Every text string, in drawing order (tests read what a model shows).
func strings() -> PackedStringArray:
	var out := PackedStringArray()
	for it: Dictionary in items:
		if it["k"] == "t":
			out.append(it["s"])
	return out


## The first text item whose string is s, or an empty Dictionary.
func find_text(s: String) -> Dictionary:
	for it: Dictionary in items:
		if it["k"] == "t" and it["s"] == s:
			return it
	return {}

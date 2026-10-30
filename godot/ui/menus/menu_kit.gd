class_name MenuKit
extends RefCounted
## Shared pieces of the menu models (crawler/ui/menus.py and screens.py): the panel frame every
## overlay menu sits in, the full-window shade, and the text helpers `_wrap` and `_fit`. Everything
## is laid out in 1280 x 768 window pixels on a HudList, exactly as pygame places it.

const X0 := 330                      ## the overlay panel's left edge (Python menus.X0)
const WIDTH := 620                   ## and width (menus.WIDTH)
const SEL_COLOUR := Color(50.0 / 255.0, 46.0 / 255.0, 70.0 / 255.0)   ## the highlighted row (50, 46, 70)


## The whole window shaded with the background colour at `alpha` (0-255), Python `screens.overlay`.
static func shade(list: HudList, alpha: int = 200) -> void:
	var c := list.style.colour("BG")
	c.a = alpha / 255.0
	list.fill(Rect2i(0, 0, HudPlace.SCREEN_W, HudPlace.SCREEN_H), c)


## An opaque background, pygame `surface.fill(BG)` (the full-screen scenes).
static func background(list: HudList) -> void:
	list.fill(Rect2i(0, 0, HudPlace.SCREEN_W, HudPlace.SCREEN_H), list.style.colour("BG"))


## Python `menus._frame`: shade, panel, outline and the centred title.
static func frame(list: HudList, title: String, y: int = 90, h: int = 560) -> void:
	var st := list.style
	shade(list)
	list.fill(Rect2i(X0, y, WIDTH, h), st.colour("PANEL_BG"))
	list.frame(Rect2i(X0, y, WIDTH, h), st.colour("WALL_LIT"), 1)
	list.centred(title, X0 + WIDTH / 2, y + 28, st.colour("ACCENT"), "big")


## Python `menus._wrap`: words packed into lines no wider than `width` in `face`.
static func wrap(st: HudStyle, text: String, width: int, face: String = "small") -> PackedStringArray:
	var lines := PackedStringArray()
	var line := ""
	for word in text.replace("\t", " ").replace("\n", " ").replace("\r", " ").split(" ", false):
		var trial := ("%s %s" % [line, word]).strip_edges()
		if st.width(face, trial) > width and line != "":
			lines.append(line)
			line = word
		else:
			line = trial
	if line != "":
		lines.append(line)
	return lines


## Python `menus._fit`: text short enough for `width`; a trailing "(...)" aside goes first, then
## the end is cut with "...". Never loops for ever, even for a width of 1.
static func fit(st: HudStyle, text: String, width: int, face: String = "small") -> String:
	if st.width(face, text) <= width:
		return text
	if text.ends_with(")") and " (" in text:
		text = text.substr(0, text.rfind(" ("))
	while st.width(face, text) > width and text.length() > 3:
		text = text.substr(0, text.length() - 4).strip_edges(false, true) + "..."
	return text

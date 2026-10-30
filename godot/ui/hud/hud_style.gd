class_name HudStyle
extends RefCounted
## The HUD's look, read from the Theme resource (ui/theme/crawl_theme.tres): fonts, sizes and the
## config.py colours. The models (HudPanel, HudTracker, ...) take one of these to measure text and
## pick colours, so they run headless and a different Theme restyles everything.
##
## Font faces are the pygame Renderer's: `font` 15 px, `small` 13 px, `big` 22 px bold and `huge`
## 56 px bold (all DejaVu Sans Mono), kept as theme items of the custom type "Crawl".

const THEME_PATH := "res://ui/theme/crawl_theme.tres"
const TYPE := "Crawl"

var theme: Theme = load(THEME_PATH)


## The Font for a face name ("font", "small", "big", "huge").
func font(face: String) -> Font:
	return theme.get_font(face, TYPE)


## The pixel size of a face.
func face_size(face: String) -> int:
	return theme.get_font_size(face, TYPE)


## The theme colour of a config.py name ("ACCENT", "DANGER", ...).
func colour(colour_name: String) -> Color:
	return theme.get_color(colour_name, TYPE)


## Width and height of `s` in `face`, as pygame's font.size(s): the advance and the line height.
func measure(face: String, s: String) -> Vector2i:
	return Vector2i(s.length() * advance(face), line_height(face))


## The whole-pixel advance of every character of a face (the font is monospace): pygame rounds it
## (8, 9, 13 and 34 px for the 13, 15, 22 and 56 px faces), and HudCanvas draws each character at
## this spacing so lines are as wide as pygame's.
func advance(face: String) -> int:
	return roundi(font(face).get_char_size(77, face_size(face)).x)       # "M"


## Width only (pygame `font.size(s)[0]`).
func width(face: String, s: String) -> int:
	return measure(face, s).x


## Line height (pygame `font.get_height()`): ascent plus descent.
func line_height(face: String) -> int:
	var f := font(face)
	var sz := face_size(face)
	return ceili(f.get_ascent(sz) + f.get_descent(sz))


## pygame's `font.get_linesize()` for each face (18, 16, 26 and 66 px): what pygame steps down a wrapped
## paragraph by. `line_height` rounds the Godot metrics up, one pixel more for the small and big faces.
func linesize(face: String) -> int:
	return {"font": 18, "small": 16, "big": 26, "huge": 66}.get(face, line_height(face))

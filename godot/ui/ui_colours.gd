class_name UiColours
extends RefCounted
## The config.py colours (BG, TEXT, ACCENT, DANGER, WALL_LIT, ...) from ui_config.json as Colors.

static var _table: Dictionary = Content.table("ui_config")["colours"]


## The named colour, e.g. UiColours.c("DANGER").
static func c(colour_name: String) -> Color:
	return of(_table[colour_name])


## A colour from an [r, g, b] (or [r, g, b, a]) array of 0-255 ints.
static func of(a: Array) -> Color:
	return Color8(a[0], a[1], a[2], a[3] if a.size() > 3 else 255)

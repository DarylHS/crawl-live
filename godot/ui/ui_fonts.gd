class_name UiFonts
extends RefCounted
## The monospace font of the pygame UI (config MONO: DejaVu Sans Mono, then common fallbacks), as a
## SystemFont so nothing is bundled yet (P7's Theme picks the final font). Every call makes a new
## font: the owner keeps it, so no font handle lives in a static variable until exit.

const NAMES: PackedStringArray = ["DejaVu Sans Mono", "Menlo", "Consolas", "Courier New", "monospace"]


## A monospace SystemFont, bold or regular.
static func mono(bold: bool = false) -> SystemFont:
	var f := SystemFont.new()
	f.font_names = NAMES
	f.font_weight = 700 if bold else 400
	return f

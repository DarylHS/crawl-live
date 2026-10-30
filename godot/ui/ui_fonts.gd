class_name UiFonts
extends RefCounted
## The monospace font of the pygame UI (config MONO: DejaVu Sans Mono), bundled under
## assets/fonts/ with its licence (owner decision 6). `mono` hands out the loaded FontFile: Godot's
## resource cache shares it, so there is nothing to free and no font lives in a static variable.

const REGULAR := "res://assets/fonts/DejaVuSansMono.ttf"
const BOLD := "res://assets/fonts/DejaVuSansMono-Bold.ttf"


## The bundled DejaVu Sans Mono, bold or regular.
static func mono(bold: bool = false) -> Font:
	return load(BOLD if bold else REGULAR) as Font

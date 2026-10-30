class_name FxCanvas
extends Control
## Draws the floating damage numbers over the 3D view (the screen-space part of the effects). It decides
## nothing: FxState holds each number's text, tone, position and age; this reads them every frame and
## paints them, bold and outlined so they read on any wall, climbing and fading out.
##
## Colours follow the game's palette (config colours): white for your hits, gold for crits and natural
## 20s, red for damage you take, green for healing, grey for misses, blue for your pet.

const TONE_COLOURS := {
	"hit": Color8(240, 240, 245), "crit": Color8(255, 196, 64), "hurt": Color8(235, 80, 80),
	"heal": Color8(110, 210, 120), "miss": Color8(170, 170, 180), "pet": Color8(110, 170, 240),
	"boss": Color8(235, 80, 80), "nat20": Color8(255, 196, 64),
}
const TONE_SIZES := {"hit": 30, "crit": 40, "hurt": 32, "heal": 28, "miss": 22, "pet": 24, "boss": 46, "nat20": 26}

var fx: FxState = null
var drawn: int = 0               ## numbers drawn last frame (tests read it)


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if fx != null and (not fx.numbers.is_empty() or drawn > 0):
		queue_redraw()


func _draw() -> void:
	drawn = 0
	if fx == null:
		return
	var font := UiFonts.mono(true)
	for n in fx.numbers:
		var tone: String = n["tone"]
		var fs: int = TONE_SIZES.get(tone, 22)
		var text: String = n["text"]
		var pos := FxState.number_pos(n)
		var alpha := FxState.number_alpha(n)
		var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var at := Vector2(roundf(pos.x - w / 2.0), roundf(pos.y))
		var col: Color = TONE_COLOURS.get(tone, Color.WHITE)
		col.a = alpha
		draw_string_outline(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, 5, Color(0.05, 0.04, 0.07, alpha))
		draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
		drawn += 1

class_name RevealCanvas
extends Control
## Draws the loot box reveal over the menu (the animation FxReveal times): a gift box in the tier's colour
## that rattles, then throws its lid and a flash of light, with sparkles (CPUParticles2D, the 2D twin of
## CPUParticles3D). Everything is drawn in 4 px blocks so it matches the game's hard pixels. Draws nothing
## when no reveal is running.

const BLOCK := 4

var reveal: FxReveal = null
var colour: Color = Color.WHITE        ## the box tier's colour
var centre: Vector2 = Vector2(520.0, 312.0)
var sparkle_scale: float = 1.0         ## particle share from the Effects setting (0 = none)
var _sparks: CPUParticles2D = null
var _was_running: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _ready() -> void:
	_sparks = CPUParticles2D.new()
	_sparks.one_shot = true
	_sparks.emitting = false
	_sparks.explosiveness = 0.95
	_sparks.lifetime = 0.9
	_sparks.direction = Vector2(0, -1)
	_sparks.spread = 180.0
	_sparks.initial_velocity_min = 90.0
	_sparks.initial_velocity_max = 260.0
	_sparks.gravity = Vector2(0, 320)
	_sparks.scale_amount_min = 4.0
	_sparks.scale_amount_max = 8.0
	_sparks.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_sparks)


## Redraw for this frame and fire the sparkles at the moment the lid opens.
func update_from(r: FxReveal, tier_colour: Color, mid: Vector2, particles: float) -> void:
	reveal = r
	colour = tier_colour
	centre = mid
	sparkle_scale = particles
	if r != null and r.should_burst() and sparkle_scale > 0.0 and _sparks != null:
		_sparks.position = mid + Vector2(0, -20)
		_sparks.amount = maxi(4, roundi(48.0 * sparkle_scale))
		var ramp := Gradient.new()
		ramp.colors = PackedColorArray([Color.WHITE, colour, Color(colour.r, colour.g, colour.b, 0.0)])
		ramp.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
		_sparks.color_ramp = ramp
		_sparks.restart()
		_sparks.emitting = true
	var running := r != null and r.running
	if running or _was_running:                 # no redraw at all while there is no box
		queue_redraw()
	_was_running = running


func _draw() -> void:
	if reveal == null or not reveal.running:
		return
	var off := reveal.shake_offset().round()
	var lift := reveal.lid_lift()
	var edge := Color8(14, 12, 18)
	var dark := colour.darkened(0.45)
	var lite := colour.lightened(0.35)
	var o := centre + off
	# the light behind the lid: rays fading as the lid goes
	var glow := reveal.light()
	if glow > 0.0:
		for i in 12:
			var a := TAU * i / 12.0 + 0.2
			var tip := o + Vector2(0, -24) + Vector2(cos(a), sin(a)) * (60.0 + 170.0 * glow)
			var p1 := o + Vector2(0, -24) + Vector2(cos(a + 0.12), sin(a + 0.12)) * 16.0
			var p2 := o + Vector2(0, -24) + Vector2(cos(a - 0.12), sin(a - 0.12)) * 16.0
			draw_colored_polygon(PackedVector2Array([p1, tip, p2]), Color(1, 1, 0.8, 0.5 * glow))
	# body: 20 x 12 blocks, with a ribbon down the middle
	var body := Rect2(o.x - 10 * BLOCK, o.y - 4, 20 * BLOCK, 12 * BLOCK)
	draw_rect(body.grow(BLOCK), edge)
	draw_rect(body, colour)
	draw_rect(Rect2(body.position.x, body.end.y - 3 * BLOCK, body.size.x, 3 * BLOCK), dark)
	draw_rect(Rect2(body.position.x + 9 * BLOCK, body.position.y, 2 * BLOCK, body.size.y), lite)
	# lid: 22 x 4 blocks sitting on the body, rising and turning away as it opens
	var lid_pos := Vector2(o.x - 11 * BLOCK, o.y - 4 - 4 * BLOCK) + Vector2(lift * 70.0, -lift * 150.0)
	var fade := 1.0 - clampf(lift * 1.2, 0.0, 1.0)
	if fade > 0.0:
		var lid := Rect2(lid_pos, Vector2(22 * BLOCK, 4 * BLOCK))
		draw_rect(lid.grow(BLOCK), Color(edge, fade))
		draw_rect(lid, Color(lite, fade))
		draw_rect(Rect2(lid.position.x + 10 * BLOCK, lid.position.y, 2 * BLOCK, lid.size.y), Color(colour, fade))
		draw_rect(Rect2(lid.position.x + 7 * BLOCK, lid.position.y - 2 * BLOCK, 3 * BLOCK, 2 * BLOCK), Color(colour, fade))    # bow loops
		draw_rect(Rect2(lid.position.x + 12 * BLOCK, lid.position.y - 2 * BLOCK, 3 * BLOCK, 2 * BLOCK), Color(colour, fade))

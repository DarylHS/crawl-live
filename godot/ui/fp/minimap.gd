class_name Minimap
extends Control
## The minimap and the "Facing X" compass label in the corner of the first-person view
## (crawler/ui/firstperson.py `_minimap`). MinimapImage makes the pixels; this node shows them
## 1:1 (nearest filtering) inside a one pixel frame in the wall colour, with the compass point
## under it. FpView sizes and calls it each frame while the HUD is up.

const BORDER := 1
const LABEL_GAP := 6

var data := MinimapImage.new()
var texture: ImageTexture = null
var compass_label: Label = null
var _font: Font = UiFonts.mono(true)


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	compass_label = Label.new()
	compass_label.add_theme_font_override("font", _font)
	compass_label.add_theme_font_size_override("font_size", 18)
	compass_label.add_theme_color_override("font_color", MinimapImage.colour("TEXT"))
	compass_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(compass_label)


## Redraw for the world and look angle; the label reads "Facing <compass point>".
func update_from(world: World, angle: float, compass: String) -> void:
	var img := data.redraw(world, angle)
	if texture == null or texture.get_size() != Vector2(img.get_size()):
		texture = ImageTexture.create_from_image(img)
	else:
		texture.update(img)
	size = Vector2(img.get_size())
	compass_label.text = "Facing %s" % compass
	compass_label.position = Vector2(0, size.y + LABEL_GAP)
	queue_redraw()


func _draw() -> void:
	if texture == null:
		return
	draw_texture(texture, Vector2.ZERO)
	draw_rect(Rect2(Vector2(-BORDER, -BORDER) + Vector2(0.5, 0.5), size + Vector2(BORDER, BORDER)),
			MinimapImage.colour("WALL_LIT"), false, 1.0)

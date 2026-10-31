class_name ViewModel
extends Control
## The first-person weapon view model (P8, owner decision 3): your hands holding the equipped weapon at
## the bottom of the 3D view, Wolfenstein style. It is a 2D overlay (not part of the 3D scene) drawn at the
## 320 x 200 frame's pixel size, so its pixels match the Retro look at any window size: one picture
## pixel is one pixel of the 320 x 200 frame, scaled up with nearest filtering.
##
## The picture comes from SpriteArt.weapon_view (keyed by weapon, so P9 art drops in). Movement comes from
## ViewModelPose: a breath and a walking bob while the camera glides, and a swing (blade slash, blunt
## smash, fist punch) on every attack, started by FxDirector from the `player_attack` event. Nothing
## here changes the game; with Effects off the weapon is drawn still.

## Where the grip is in the picture and where it sits on screen (fractions of the view's width).
const PIVOT := Vector2(44.0, 70.0)
const SCREEN_X := 0.62

var fx: FxState = null           ## null: draw still (standalone use, tests)
var item_key: String = ""        ## the equipped weapon ("" for fists)
var style: String = "unarmed"
var walked: float = 0.0          ## tiles the camera has travelled (FpView keeps it)
var moving: float = 0.0          ## 0 to 1, how much the camera is moving now
var dim: bool = false            ## a menu covers the view
var last_pose: Dictionary = {}   ## the pose drawn last (tests read it)
var _textures: Dictionary = {}   ## cache key -> ImageTexture
var _drawn_dim: bool = false


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Show this weapon: its item key ("" for none) and style ("blade", "blunt", "unarmed").
func set_weapon(new_key: String, new_style: String) -> void:
	if new_key != item_key or new_style != style:
		item_key = new_key
		style = new_style
		queue_redraw()


## The pose to draw now: the swing if one is running, plus the idle sway.
func current_pose() -> Dictionary:
	var pose := {"off": Vector2.ZERO, "rot": 0.0, "scale": 1.0}
	var t := fx.time if fx != null else 0.0
	var bob := float(fx.profile["bob"]) if fx != null else 0.0
	if fx != null:
		var k := fx.swing_progress()
		if k >= 0.0:
			pose = ViewModelPose.swing(fx.swing_style(), k)
	pose["off"] = (pose["off"] as Vector2) + ViewModelPose.idle(t, walked, moving, bob)
	return pose


func _process(_delta: float) -> void:
	if visible and (current_pose() != last_pose or dim != _drawn_dim):   # redraw only when the weapon actually moved
		queue_redraw()


func _draw() -> void:
	var tex := _texture()
	var s := size.x / 320.0
	var pose := current_pose()
	last_pose = pose
	_drawn_dim = dim
	var pivot := Vector2(size.x * SCREEN_X, size.y - (float(WeaponArt.SIZE) - PIVOT.y) * s + 2.0 * s)
	var off: Vector2 = pose["off"]
	var k: float = pose["scale"]
	draw_set_transform(pivot + off * s, float(pose["rot"]), Vector2(s * k, s * k))
	draw_texture(tex, -PIVOT, Color(0.65, 0.65, 0.65) if dim else Color.WHITE)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Forget the cached pictures (another art set was chosen).
func forget_textures() -> void:
	_textures.clear()


func _texture() -> Texture2D:
	var key := "%s|%s" % [item_key, style]
	if not _textures.has(key):
		_textures[key] = ImageTexture.create_from_image(SpriteArt.weapon_view(item_key, style))
	return _textures[key]

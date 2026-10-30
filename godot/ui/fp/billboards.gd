class_name Billboards
extends Node3D
## The first-person sprites (crawler/ui/firstperson.py `_draw_sprites`): a billboard for each thing
## the player can see: monsters (Acts and Headliners larger, with a tier-coloured outline), the
## pet, items on the floor (with a soft shadow), the stairwell arrow (gold, or red with a padlock),
## and safe-room furniture. A monster that has lost HP gets a red health bar above it.
##
## Each is a Sprite3D (its quad, `pixel_size` and nearest-filtered texture) whose material is
## billboard.gdshader: it faces the camera about the Y axis and is shaded by fog alone, with
## Python's 0.12 minimum brightness; the lower-half darkening is part of the sprite
## (SpriteArt.finish_creature). Sizes are the art bible's (monsters 0.62 to 0.71 of a wall by HP,
## Opening 0.85, Featured 0.95, Headliner 1.0, pets 0.5, furniture 0.75, items 0.32), as a fraction
## of the wall height (FloorMeshBuilder.WALL_H); feet on the floor, `lift` raises the stairs arrow.
## The pictures come from SpriteArt by asset key, so P9's real art needs no change here.
##
## World units, not pixels: the sprites keep their size at any render scale (FpView.render_scale).

const BAR_BACK := Color8(60, 10, 10)
const BAR_PX := 2.0                   ## bar height in pixels of the 320 x 200 frame
const BAR_MIN_PX := 6.0
const BAR_GAP_PX := 4.0               ## the bar's top edge sits this far above the sprite
const PX_PER_TILE := 228.57           ## 320 / (2 * PLANE) pixels of the 320 px frame per tile at depth 1
const MIN_BRIGHT := 0.12              ## Python: v = 255 * max(0.12, fog), so sprites never go fully black
const MIN_DEPTH := 0.2                ## Python skips sprites nearer than this (tz <= 0.2)
const SHADOW_BACK := 0.02             ## shadows sit this far behind their item (tiles)
const SHADOW_ALPHA := 120.0 / 255.0

static var _fp_cfg: Dictionary = Content.table("ui_config")["firstperson"]

var shown: int = 0                    ## sprites shown after the last sync (tests read it)
var _shader: Shader = load("res://ui/fp/billboard.gdshader")
var _bar_shader: Shader = load("res://ui/fp/billboard_bar.gdshader")
var _textures: Dictionary = {}        ## cache key -> ImageTexture
var _pool: Array[_Slot] = []
var _bar_textures: Dictionary = {}    ## filled pixels (0-64) -> ImageTexture


## One sprite with its health bar and item shadow.
class _Slot:
	extends RefCounted
	var sprite: Sprite3D
	var bar: Sprite3D
	var shadow: Sprite3D
	var mat: ShaderMaterial
	var bar_mat: ShaderMaterial


## What to show, from what the player can see now: [{tile, tex, scale, lift, tier?, monster?, shadow?}].
## `cam` is FpLogic's [x, y, angle] (used for depth and the health bars); empty means no culling.
func specs(world: World) -> Array:
	var out: Array = []
	var vis := world.visible
	for tile in world.floor_items:
		if vis.has(tile):
			var keys: Array = world.floor_items[tile]
			var k: String = keys[keys.size() - 1]
			out.append({"tile": tile, "tex": _tex("item:" + k, func() -> Image: return SpriteArt.item(k)),
					"scale": 0.32, "lift": 0.0, "shadow": true})
	var locked := world.stairs_locked or world.exit_sealed
	for s in world.floor.stairs:
		if vis.has(s):
			out.append({"tile": s, "tex": _tex("fx:stairs_%s" % locked, func() -> Image: return SpriteArt.stairs(locked)),
					"scale": 0.3, "lift": 0.55})
	for f in world.floor.furniture:
		if vis.has(f):
			var kind: String = world.floor.furniture[f]
			out.append({"tile": f, "tex": _tex("furn:" + kind, func() -> Image: return SpriteArt.furniture(kind)),
					"scale": 0.75, "lift": 0.0})
	var pt := world.active_pet
	if pt != null and vis.has(Vector2i(pt.x, pt.y)):
		var species: String = pt.species
		var pcol: Array = pt.colour
		out.append({"tile": Vector2i(pt.x, pt.y), "tex": _tex("pet:%s|%s" % [species, pcol],
				func() -> Image: return SpriteArt.creature("pet:" + species, pcol)),
				"scale": 0.5, "lift": 0.0})
	for m in world.monsters:
		if vis.has(Vector2i(m.x, m.y)):
			var mkey := SpriteArt.monster_key(m)
			var mcol: Array = m.colour
			var tier: String = m.tier
			var scale_v: float = _fp_cfg["TIER_SCALE"].get(tier, 0.62 + 0.03 * mini(m.max_hp, 12) / 4.0)
			out.append({"tile": Vector2i(m.x, m.y), "tex": _tex("%s|%s|%s" % [mkey, mcol, tier],
					func() -> Image: return SpriteArt.creature(mkey, mcol, tier)),
					"scale": scale_v, "lift": 0.0, "monster": m})
	return out


## Show a billboard for each thing in `specs`. Cheap enough to call every frame.
func sync(world: World, cam: Array = []) -> void:
	var list := specs(world)
	var fwd := Vector2.ZERO
	if not cam.is_empty():
		fwd = Vector2(cos(cam[2]), sin(cam[2]))
	var used: Array = []
	for spec: Dictionary in list:
		var tile: Vector2i = spec["tile"]
		var depth := 1.0
		if not cam.is_empty():
			depth = (tile.x + 0.5 - cam[0]) * fwd.x + (tile.y + 0.5 - cam[1]) * fwd.y
			if depth <= MIN_DEPTH:
				continue                      # behind you or in your face: Python skips it too
		spec["depth"] = depth
		used.append(spec)
	while _pool.size() < used.size():
		_pool.append(_make_slot())
	for i in _pool.size():
		var slot := _pool[i]
		var on := i < used.size()
		slot.sprite.visible = on
		if not on:
			slot.shadow.visible = false
			slot.bar.visible = false
			continue
		_place(slot, used[i], fwd)
	shown = used.size()


func _place(slot: _Slot, spec: Dictionary, fwd: Vector2) -> void:
	var tile: Vector2i = spec["tile"]
	var tex: Texture2D = spec["tex"]
	var size_v: float = float(spec["scale"]) * FloorMeshBuilder.WALL_H   # Python: scale x wall height
	var lift: float = float(spec["lift"]) * FloorMeshBuilder.WALL_H
	var pixel := size_v / tex.get_height()
	slot.sprite.texture = tex
	slot.mat.set_shader_parameter("sprite_tex", tex)
	slot.sprite.pixel_size = pixel
	var centre := Vector3(tile.x + 0.5, size_v / 2.0 + lift, tile.y + 0.5)
	slot.sprite.position = centre
	slot.shadow.visible = spec.get("shadow", false)
	if slot.shadow.visible:
		var sh := SpriteArt.shadow()
		slot.shadow.texture = _tex("fx:shadow", func() -> Image: return sh)
		slot.shadow.pixel_size = pixel
		slot.shadow.position = centre + Vector3(fwd.x, 0.0, fwd.y) * SHADOW_BACK
	var m: Monster = spec.get("monster")
	slot.bar.visible = m != null and m.hp < m.max_hp
	if slot.bar.visible:
		var depth: float = spec["depth"]
		var px := depth / PX_PER_TILE                      # one pixel of the 320 x 200 frame, in tiles
		var bar_w := maxf(BAR_MIN_PX * px, size_v / 2.0)
		var bar_h := BAR_PX * px
		var filled := int(64.0 * m.hp / m.max_hp)
		slot.bar.texture = _bar_tex(filled)
		slot.bar_mat.set_shader_parameter("sprite_tex", slot.bar.texture)
		slot.bar.pixel_size = bar_w / 64.0
		slot.bar.scale = Vector3(1.0, bar_h / bar_w * 32.0, 1.0)   # the 64 x 2 texture is bar_w x bar_h
		slot.bar.position = centre + Vector3(0.0, size_v / 2.0 + (BAR_GAP_PX - 1.0) * px, 0.0) \
				- Vector3(fwd.x, 0.0, fwd.y) * 0.01


func _make_slot() -> _Slot:
	var slot := _Slot.new()
	slot.sprite = _new_sprite()
	slot.mat = _material(true)
	slot.sprite.material_override = slot.mat
	slot.bar = _new_sprite()
	slot.bar_mat = _material(false, _bar_shader)
	slot.bar.material_override = slot.bar_mat
	slot.shadow = _new_sprite()
	slot.shadow.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	slot.shadow.shaded = false
	slot.shadow.transparent = true
	slot.shadow.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	slot.shadow.modulate = Color(0, 0, 0, SHADOW_ALPHA)
	return slot


func _new_sprite() -> Sprite3D:
	var s := Sprite3D.new()
	s.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	s.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	s.visible = false
	add_child(s)
	return s


func _material(fogged: bool, shader: Shader = null) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = shader if shader != null else _shader
	mat.set_shader_parameter("light", FpLogic.LIGHT)
	mat.set_shader_parameter("min_bright", MIN_BRIGHT)
	mat.set_shader_parameter("fogged", fogged)
	return mat


func _tex(key: String, make: Callable) -> Texture2D:
	if not _textures.has(key):
		_textures[key] = ImageTexture.create_from_image(make.call())
	return _textures[key]


## A 64 x 2 health bar: `filled` pixels of the danger colour, the rest dark red.
func _bar_tex(filled: int) -> Texture2D:
	if not _bar_textures.has(filled):
		var img := Image.create_empty(64, 2, false, Image.FORMAT_RGBA8)
		var danger: Array = Content.table("ui_config")["colours"]["DANGER"]
		img.fill(BAR_BACK)
		img.fill_rect(Rect2i(0, 0, filled, 2), Color8(danger[0], danger[1], danger[2]))
		_bar_textures[filled] = ImageTexture.create_from_image(img)
	return _bar_textures[filled]

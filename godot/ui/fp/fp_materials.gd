class_name FpMaterials
extends RefCounted
## Materials for the first-person floor mesh: one per FloorMeshBuilder slot, per floor.
##
## StandardMaterial3D, lit by the torch (an OmniLight3D on the camera) and the dim ambient light,
## with nearest filtering and no mipmaps for hard pixels. The per-floor tint (DEPTH_TINT) is the
## albedo colour of the stone slots (walls, floor, ceiling); safe-room and stairs slots are never
## tinted, so they read the same on every floor. The mesh's vertex colours carry Python's fixed
## shading (north and south wall faces 0.78, ceiling 0.8). "stairs_locked" is the stairs grate in
## red; FpView swaps it in while the stairwells are shut.
##
## An instance keeps the materials of the floors it has made (owned by the view, so nothing
## GPU-backed lives in a static variable until exit).

const TINTED: Array[String] = ["wall_a", "wall_b", "floor", "ceiling"]
const LOCKED_TINT := Color(1.0, 0.38, 0.34)
const KEEP := 2                      ## floors kept in the cache (the current one and the last)

var _cache: Dictionary = {}          ## depth -> {slot: StandardMaterial3D}


## Every slot's material for a floor, plus "stairs_locked".
func for_depth(depth: int) -> Dictionary:
	if _cache.has(depth):
		return _cache[depth]
	var images := FpTextures.images_for_depth(depth)
	var tint := FpLogic.depth_tint(depth)
	var out := {}
	for slot in FpTextures.SLOTS:
		var tex := ImageTexture.create_from_image(images[slot])
		out[slot] = _make(tex, tint if slot in TINTED else Color.WHITE)
	out["stairs_locked"] = _make(out["stairs"].albedo_texture, LOCKED_TINT)
	while _cache.size() >= KEEP:
		_cache.erase(_cache.keys()[0])
	_cache[depth] = out
	return out


static func _make(texture: Texture2D, albedo: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = texture
	m.albedo_color = albedo
	m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	m.vertex_color_use_as_albedo = true
	m.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	m.roughness = 1.0
	return m

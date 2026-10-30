class_name WallTorches
extends Node3D
## Torches on the dungeon walls (P8, owner decision: torch flicker and torch particles). The game has
## no torch props, so these are pure decoration: a deterministic scatter of wall tiles per floor (a hash
## of the tile and the depth, never the game's RNG), a flickering flame sprite on a bracket, and a few
## drifting embers (CPUParticles3D). Safe rooms and stairs are left alone. There is no extra light:
## the torch light on the camera (FpCameraRig) is what flickers, so walls never brighten past their texture.
##
## Only the few nearest torches you can see are shown, from a small pool of nodes, so the cost does not
## grow with the floor. Torches are not game state: nothing reads them.

const MAX_SHOWN := 5
const HASH_MOD := 19                     ## about one wall tile in 19 beside open floor holds a torch
const HEIGHT := 0.6                      ## sprite centre height as a fraction of the wall
const SIZE_FRAC := 0.34                  ## sprite height as a fraction of the wall
const OFF_WALL := 0.06                   ## how far the sprite sits out from the wall (tiles)
const FLAME_FPS := 7.0

static var _shader: Shader = load("res://ui/fp/billboard.gdshader")

var shown: int = 0                       ## torches showing after the last sync (tests read it)
var _sites_floor: DungeonFloor = null
var _sites: Array[Dictionary] = []
var _pool: Array[Dictionary] = []        ## {sprite, mat, embers}
var _textures: Array[Texture2D] = []


## Where the torches are on a floor: [{tile: Vector2i, dir: Vector2i}], `dir` pointing from the open
## tile at its wall. Same floor, same torches, every time.
static func sites_for(floor: DungeonFloor) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for y in range(1, floor.height - 1):
		for x in range(1, floor.width - 1):
			if floor.tiles[y][x] != DungeonFloor.FLOOR or floor.is_safe(x, y):
				continue
			var h := ((x * 73856093) ^ (y * 19349663) ^ (floor.depth * 83492791)) & 0xffff
			if h % HASH_MOD != 0:
				continue
			var walls: Array[Vector2i] = []
			for d in FpLogic.DIRS:
				if floor.tiles[y + d.y][x + d.x] == DungeonFloor.WALL and not floor.is_safe(x + d.x, y + d.y):
					walls.append(d)
			if walls.is_empty():
				continue
			out.append({"tile": Vector2i(x, y), "dir": walls[(h >> 4) % walls.size()]})
	return out


## The `limit` sites nearest the camera (cam is [x, y, angle]) that are in sight, nearest first.
static func pick(sites: Array, cam: Array, visible: Dictionary, limit: int = MAX_SHOWN) -> Array[Dictionary]:
	var scored: Array = []
	for s: Dictionary in sites:
		var tile: Vector2i = s["tile"]
		if not visible.has(tile):
			continue
		var dx := tile.x + 0.5 - float(cam[0])
		var dy := tile.y + 0.5 - float(cam[1])
		scored.append([dx * dx + dy * dy, s])
	scored.sort_custom(func(a: Array, b: Array) -> bool: return a[0] < b[0])
	var out: Array[Dictionary] = []
	for i in mini(limit, scored.size()):
		out.append(scored[i][1])
	return out


## Show the torches near the camera. `fx` null or a mode without torches hides them all.
func sync(world: World, cam: Array, fx: FxState) -> void:
	if fx == null or not fx.profile["torches"] or cam.is_empty():
		_hide_from(0)
		shown = 0
		return
	if _sites_floor != world.floor:
		_sites_floor = world.floor
		_sites = sites_for(world.floor)
	var chosen := pick(_sites, cam, world.visible)
	while _pool.size() < chosen.size():
		_pool.append(_make())
	if _textures.is_empty():
		_textures = [_tex(0), _tex(1)]
	var embers_on: bool = float(fx.profile["particles"]) > 0.0
	var frame := int(fx.time * FLAME_FPS)
	for i in chosen.size():
		var slot: Dictionary = _pool[i]
		var tile: Vector2i = chosen[i]["tile"]
		var dir: Vector2i = chosen[i]["dir"]
		var sprite: Sprite3D = slot["sprite"]
		var size_v := SIZE_FRAC * FloorMeshBuilder.WALL_H
		var tex := _textures[(frame + tile.x + tile.y) % 2]
		sprite.texture = tex
		(slot["mat"] as ShaderMaterial).set_shader_parameter("sprite_tex", tex)
		sprite.pixel_size = size_v / tex.get_height()
		var flick := 1.0 + 0.08 * float(fx.profile["flicker"]) * sin(fx.time * 23.0 + tile.x * 1.7 + tile.y)
		sprite.scale = Vector3(flick, flick, 1.0)
		var pos := Vector3(tile.x + 0.5 + dir.x * (0.5 - OFF_WALL), HEIGHT * FloorMeshBuilder.WALL_H,
				tile.y + 0.5 + dir.y * (0.5 - OFF_WALL))
		sprite.position = pos
		sprite.visible = true
		var embers: CPUParticles3D = slot["embers"]
		embers.position = pos + Vector3(0.0, size_v * 0.35, 0.0)
		embers.emitting = embers_on
	_hide_from(chosen.size())
	shown = chosen.size()


func _hide_from(n: int) -> void:
	for i in range(n, _pool.size()):
		(_pool[i]["sprite"] as Sprite3D).visible = false
		(_pool[i]["embers"] as CPUParticles3D).emitting = false


func _tex(frame: int) -> Texture2D:
	return ImageTexture.create_from_image(SpriteArt.torch(frame))


func _make() -> Dictionary:
	var sprite := Sprite3D.new()
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	var mat := ShaderMaterial.new()
	mat.shader = _shader
	mat.set_shader_parameter("light", FpLogic.LIGHT)
	mat.set_shader_parameter("min_bright", 0.12)
	mat.set_shader_parameter("fogged", true)
	sprite.material_override = mat
	sprite.visible = false
	add_child(sprite)
	var embers := FxParticles.configure(CPUParticles3D.new(), "ember", 6)
	embers.emitting = false
	embers.one_shot = false
	embers.explosiveness = 0.0
	embers.local_coords = false
	add_child(embers)
	return {"sprite": sprite, "mat": mat, "embers": embers}

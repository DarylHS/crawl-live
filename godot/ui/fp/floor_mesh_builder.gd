class_name FloorMeshBuilder
extends RefCounted
## Builds a dungeon floor as one ArrayMesh for the first-person view (port plan 10.1).
##
## Tile (x, y) covers x..x+1 on the X axis and y..y+1 on the Z axis (north is -Z), floor at Y = 0
## and ceiling at Y = WALL_H. Every open tile (floor, stairs, furniture) gets a floor quad and a
## ceiling quad; every side of it that touches a wall (or the map edge) gets a wall quad facing
## into the tile. Nothing else: no hidden faces, no wall tops. That is what the Python raycaster
## shows too (walls are the faces a ray from an open tile hits).
##
## One surface per material slot, named after it (`mesh.surface_find_by_name("stairs")`), in the
## FpTextures.SLOTS order, skipping slots with no faces:
##   wall_a / wall_b  stone walls, the variant picked by a hash of the wall tile
##   safe_wall        a wall face seen from a safe-room tile (Python: the tile the ray came from)
##   floor / safe_floor / stairs   by the open tile
##   ceiling          above every open tile
## Vertex colours carry Python's fixed shading: 0.78 on north and south wall faces (the
## raycaster's "side 1"), 0.8 on the ceiling. UVs map one 64 x 64 texture per tile face.
##
## Why 0.875: Python's raycaster draws a wall 200 / d pixels tall in a 320 x 200 frame whose
## horizontal half-width is PLANE = 0.7, so its pixels are not square (vertically it behaves like a
## half-height of 0.5, horizontally 0.7 * 200 / 320 = 0.4375). With square pixels and the same 70
## degree horizontal FOV, a wall 0.875 tiles high with the eye at half of it fills exactly the same
## 200 / d pixels, so the proportions match the pygame view.
##
## The arrays are filled directly (PackedVector3Array and friends) rather than through SurfaceTool:
## the same result, several times faster in GDScript. The face counts per slot are stored in the
## mesh's "faces" metadata for tests and the build report.

const WALL_H := 0.875                  ## wall height in tiles (see the note above; the eye is at half of it)
const SIDE_SHADE := 0.78               ## Python: walls hit on a y side are drawn at 0.78
const CEILING_SHADE := 0.8             ## Python: the ceiling is drawn at 0.8


## The floor as an ArrayMesh with no materials (see `build` for a MeshInstance3D with them).
static func build_mesh(floor: DungeonFloor) -> ArrayMesh:
	var w := floor.width
	var h := floor.height
	var buckets := {}
	for slot in FpTextures.SLOTS:
		buckets[slot] = _Bucket.new()
	var side := Color(SIDE_SHADE, SIDE_SHADE, SIDE_SHADE)
	var ceil_c := Color(CEILING_SHADE, CEILING_SHADE, CEILING_SHADE)
	var top := WALL_H
	for y in h:
		var row: PackedByteArray = floor.tiles[y]
		var safe_row: PackedByteArray = floor.safe[y]
		for x in w:
			var t := row[x]
			if t == DungeonFloor.WALL:
				continue
			var safe := safe_row[x] != 0
			var kind := "stairs" if t == DungeonFloor.STAIRS else ("safe_floor" if safe else "floor")
			(buckets[kind] as _Bucket).quad(
					Vector3(x, 0, y), Vector3(x + 1, 0, y), Vector3(x + 1, 0, y + 1), Vector3(x, 0, y + 1),
					Vector3.UP, Color.WHITE)
			(buckets["ceiling"] as _Bucket).quad(
					Vector3(x + 1, top, y), Vector3(x, top, y), Vector3(x, top, y + 1), Vector3(x + 1, top, y + 1),
					Vector3.DOWN, ceil_c, true)
			if _solid(floor, x, y - 1):        # north wall, facing south into the tile
				_wall(buckets, safe, x, y - 1).quad(
						Vector3(x, top, y), Vector3(x + 1, top, y), Vector3(x + 1, 0, y), Vector3(x, 0, y),
						Vector3.BACK, side)
			if _solid(floor, x, y + 1):        # south wall, facing north
				_wall(buckets, safe, x, y + 1).quad(
						Vector3(x + 1, top, y + 1), Vector3(x, top, y + 1), Vector3(x, 0, y + 1), Vector3(x + 1, 0, y + 1),
						Vector3.FORWARD, side)
			if _solid(floor, x + 1, y):        # east wall, facing west
				_wall(buckets, safe, x + 1, y).quad(
						Vector3(x + 1, top, y), Vector3(x + 1, top, y + 1), Vector3(x + 1, 0, y + 1), Vector3(x + 1, 0, y),
						Vector3.LEFT, Color.WHITE)
			if _solid(floor, x - 1, y):        # west wall, facing east
				_wall(buckets, safe, x - 1, y).quad(
						Vector3(x, top, y + 1), Vector3(x, top, y), Vector3(x, 0, y), Vector3(x, 0, y + 1),
						Vector3.RIGHT, Color.WHITE)
	var mesh := ArrayMesh.new()
	var faces := {}
	for slot in FpTextures.SLOTS:
		var b: _Bucket = buckets[slot]
		faces[slot] = b.faces
		if b.faces == 0:
			continue
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, b.arrays())
		mesh.surface_set_name(mesh.get_surface_count() - 1, slot)
	mesh.set_meta("faces", faces)
	return mesh


## The floor as a MeshInstance3D with the floor's materials on each surface.
static func build(floor: DungeonFloor, materials: Dictionary) -> MeshInstance3D:
	var mesh := build_mesh(floor)
	for i in mesh.get_surface_count():
		mesh.surface_set_material(i, materials[mesh.surface_get_name(i)])
	var mi := MeshInstance3D.new()
	mi.name = "FloorMesh"
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return mi


## Face counts per slot of a mesh made by build_mesh.
static func faces(mesh: ArrayMesh) -> Dictionary:
	return mesh.get_meta("faces", {})


## True for a wall tile or a tile off the map (the raycaster stops at the edge too).
static func _solid(floor: DungeonFloor, x: int, y: int) -> bool:
	return not floor.in_bounds(x, y) or floor.tiles[y][x] == DungeonFloor.WALL


## The bucket for a wall face: safe-room wall when seen from a safe tile, else a stone variant
## chosen by a hash of the wall tile, so every face of one wall block matches.
static func _wall(buckets: Dictionary, from_safe: bool, wx: int, wy: int) -> _Bucket:
	if from_safe:
		return buckets["safe_wall"]
	var hsh := ((wx * 73856093) ^ (wy * 19349663)) & 0x7fffffff
	return buckets["wall_b" if hsh % 3 == 0 else "wall_a"]


## Vertex data for one surface, filled a quad at a time.
class _Bucket:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var colours := PackedColorArray()
	var indices := PackedInt32Array()
	var faces := 0

	## A quad given clockwise as seen from its front (top-left, top-right, bottom-right,
	## bottom-left), which is Godot's front-face winding. `world_uv` maps the ceiling by world
	## position so its texture lines up with the floor's.
	func quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3, normal: Vector3, colour: Color,
			world_uv := false) -> void:
		var base := verts.size()
		verts.append_array([a, b, c, d])
		normals.append_array([normal, normal, normal, normal])
		colours.append_array([colour, colour, colour, colour])
		if world_uv:
			uvs.append_array([Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1)])
		else:
			uvs.append_array([Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)])
		indices.append_array([base, base + 1, base + 2, base, base + 2, base + 3])
		faces += 1

	func arrays() -> Array:
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_TEX_UV] = uvs
		arr[Mesh.ARRAY_COLOR] = colours
		arr[Mesh.ARRAY_INDEX] = indices
		return arr

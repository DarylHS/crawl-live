class_name FpTextures
extends RefCounted
## Placeholder 64 x 64 textures for the first-person view, drawn in code (P4; real art is P9).
##
## A GDScript port of the procedural textures in crawler/ui/firstperson.py (`_bricks`, `_tiles`,
## `_flagstones`, `_stairs`, `_ceiling`). Python draws with numpy's generator, so the noise differs
## pixel for pixel; the shapes, sizes and colours are the same. Textures are made untinted: the
## per-floor tint is the material's albedo colour (FpMaterials), and safe-room and stairs
## materials are never tinted. Presentation code, so it may use RandomNumberGenerator.
##
## Slots: "wall_a", "wall_b" (two brick variants picked by a tile hash), "safe_wall", "floor",
## "safe_floor", "stairs", "ceiling". 64 x 64 RGB8, no mipmaps (art bible section 3).

const TEX := 64
const SLOTS: Array[String] = ["wall_a", "wall_b", "safe_wall", "floor", "safe_floor", "stairs", "ceiling"]

## The seven images for a floor, {slot: Image}. Floors share the shapes but get their own noise,
## as Python seeds its generator with 1000 + depth. Not cached here: FpMaterials keeps the
## textures made from them for the floors it has shown.
static func images_for_depth(depth: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = 1000 + depth
	return {
		"wall_a": _bricks(rng, Color8(112, 104, 120)),
		"wall_b": _bricks(rng, Color8(104, 100, 112)),
		"safe_wall": _tiles(rng, Color8(178, 214, 188), Color8(160, 200, 174), 16, Color8(90, 120, 100)),
		"floor": _flagstones(rng, Color8(74, 70, 82)),
		"safe_floor": _tiles(rng, Color8(58, 110, 80), Color8(42, 84, 62), 16, Color8(28, 52, 40)),
		"stairs": _stairs(),
		"ceiling": _ceiling(rng),
	}


static func _new_image() -> Image:
	return Image.create_empty(TEX, TEX, false, Image.FORMAT_RGB8)


static func _put(img: Image, x: int, y: int, r: float, g: float, b: float) -> void:
	img.set_pixel(x, y, Color(clampf(r, 0, 255) / 255.0, clampf(g, 0, 255) / 255.0, clampf(b, 0, 255) / 255.0))


## Running bond bricks 32 x 16 with dark mortar, a lit top and shaded bottom per course, and noise.
static func _bricks(rng: RandomNumberGenerator, base: Color, mortar := Color8(30, 28, 34), bh := 16, bw := 32) -> Image:
	var img := _new_image()
	var shade := PackedFloat32Array()
	shade.resize(TEX * TEX)
	for row in TEX / bh:
		var y0 := row * bh
		var offset := (bw / 2) * (row % 2)
		for bx in range(-1, TEX / bw + 1):
			var x0 := bx * bw + offset
			var k := rng.randf_range(0.78, 1.08)
			for y in range(y0, y0 + bh):
				for x in range(maxi(x0, 0), mini(x0 + bw, TEX)):
					shade[y * TEX + x] = k
	for y in TEX:
		var row := y / bh
		var in_row := y % bh
		var offset := (bw / 2) * (row % 2)
		var bevel := lerpf(14.0, -18.0, in_row / float(bh - 1))
		for x in TEX:
			var n := float(rng.randi_range(-10, 10))
			if in_row == 0 or (x - offset) % bw == 0:
				_put(img, x, y, mortar.r8 + n, mortar.g8 + n, mortar.b8 + n)
				continue
			var k := shade[y * TEX + x]
			_put(img, x, y, base.r8 * k + bevel + n, base.g8 * k + bevel + n, base.b8 * k + bevel + n)
	return img


## A checker of size x size tiles in two colours with grout lines (the safe room's clean tiles).
static func _tiles(rng: RandomNumberGenerator, a: Color, b: Color, size: int, grout: Color) -> Image:
	var img := _new_image()
	for y in TEX:
		for x in TEX:
			if x % size == 0 or y % size == 0:
				_put(img, x, y, grout.r8, grout.g8, grout.b8)
				continue
			var c := a if (x / size + y / size) % 2 == 1 else b
			var n := float(rng.randi_range(-6, 6))
			_put(img, x, y, c.r8 + n, c.g8 + n, c.b8 + n)
	return img


## Uneven stone flags with a grout border on all four edges.
static func _flagstones(rng: RandomNumberGenerator, base: Color, grout := Color8(22, 20, 26)) -> Image:
	var img := _new_image()
	var k := rng.randf_range(0.9, 1.05)
	for y in TEX:
		for x in TEX:
			if x == 0 or y == 0 or x == TEX - 1 or y == TEX - 1:
				_put(img, x, y, grout.r8, grout.g8, grout.b8)
				continue
			var n := 8.0 * sin(x / 7.0) * cos(y / 9.0) + rng.randi_range(-12, 12)
			_put(img, x, y, base.r8 * k + n, base.g8 * k + n, base.b8 * k + n)
	return img


## The stairwell grate: gold square rings glowing towards the centre (the show's accent colour).
static func _stairs() -> Image:
	var img := _new_image()
	for y in TEX:
		for x in TEX:
			var d := maxf(absf(x - 31.5), absf(y - 31.5))
			var glow := clampf(1.0 - d / 34.0, 0.0, 1.0)
			if int(d) % 8 < 2:
				var g := 0.5 + 0.5 * glow
				_put(img, x, y, 255 * g, 190 * g, 60 * g)
			else:
				_put(img, x, y, 30 + 60 * glow, 24 + 60 * glow, 14 + 60 * glow)
	return img


## A dark, slightly noisy ceiling with shaded seams on two edges.
static func _ceiling(rng: RandomNumberGenerator) -> Image:
	var img := _new_image()
	for y in TEX:
		for x in TEX:
			var n := float(rng.randi_range(-5, 5))
			var k := 0.75 if x < 2 or y < 2 else 1.0
			_put(img, x, y, (34 + n) * k, (31 + n) * k, (40 + n) * k)
	return img

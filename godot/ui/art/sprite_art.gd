class_name SpriteArt
extends RefCounted
## The sprite lookup: one 32 x 32 picture per creature, item, piece of furniture and stairwell
## marker, found by the art bible's asset keys (docs/art-bible.md section 6):
##
##   mon:<monster>          mon:opening_<monster>, mon:featured_<monster>   (Acts)
##   boss:boss_<depth>      pet:<species>      item:<item>      furn:<kind>
##   fx:stairs_open         fx:stairs_locked
##   fx:torch_0, fx:torch_1                 (P8: the two frames of a wall torch's flame)
##   wpn:<item>  wpn:blade  wpn:blunt  wpn:unarmed   (P8: the first-person weapon view model, 80 x 80,
##                           hands included; an item's own picture wins over its style's, then the placeholder)
##
##   player:<race>  player:crawler       (P9: the top-down player, one per race; crawler before a race is chosen)
##   fx:badge_opening  fx:sash_featured   (P9: Act overlays, laid over the base monster's body)
##   tex:<depth>:wall_0|wall_1|floor|ceiling  tex:safe_wall|safe_floor|stairs_open|stairs_locked  (64 x 64)
##   tile:<depth>:wall_0|wall_1|floor  tile:safe_wall|safe_floor|stairs_open|stairs_locked  (32 x 32 top-down)
##   box:<tier>  box_big:<tier>           (loot box icons, 32 and 64 px)
##
## Real art (P9): the keys are answered from `res://assets/manifest.json` (written by scripts/art_build.py,
## {"mon:goblin": {"file": "sprites/monsters/goblin.png", ...}}, paths relative to res://assets/). An art
## set is a folder `res://assets/sets/<name>/` with its own manifest.json (scripts/artgen.py import writes
## one); the active set answers first and the default set fills what it lacks. The set called "placeholder"
## skips every manifest, so each key is answered by the placeholder drawn in code, ported from the pygame
## "body plan" sprites in crawler/ui/firstperson.py (creatures), with simple per-kind shapes for items. The
## placeholders are also the fallback for any key no manifest has, so nothing ever crashes on a missing PNG.
## `register(key, image)` wins over everything (tests). Views notice a switch through `generation`.
##
## Creatures get the same finishing as Python's `creature_sprite`, whatever their source: light from
## above (the lower half darker, 1.1 to 0.75 down the rows) and a one pixel outline drawn from the
## alpha, near-black for ordinary monsters and the tier colour for Acts and Headliners. Every pixel
## is fully opaque or fully transparent (binary alpha). Feet sit on the bottom rows.

const SIZE := 32
const OUTLINE := Color8(14, 12, 18)
const ASSETS := "res://assets/"
const MANIFEST := "res://assets/manifest.json"
const SETS_DIR := "res://assets/sets/"
const DEFAULT_SET := "default"
const PLACEHOLDER_SET := "placeholder"

static var generation: int = 0           ## bumped whenever the art changes (a set switch, register, reset): views rebuild
static var sets_dir: String = SETS_DIR  ## where the art sets live (tests point it at a temporary folder)
static var art_set: String = DEFAULT_SET ## the active set: "default", a folder under assets/sets/, or "placeholder"

static var _cache: Dictionary = {}       ## cache key -> Image (finished)
static var _overrides: Dictionary = {}   ## asset key -> Image supplied by register()
static var _loaded: Dictionary = {}      ## asset key -> Image read from a manifest's file (false: none)
static var _sources_cache: Variant = null   ## [{dir, entries}] in priority order, null until read
static var _env_read: bool = false


## Use `image` for `key` from now on (what the art loader of P9 calls).
static func register(key: String, image: Image) -> void:
	_overrides[key] = image
	_cache.clear()
	generation += 1


## Forget registered images, the manifests and every cached sprite (tests). The chosen set stays.
static func reset() -> void:
	_overrides.clear()
	_cache.clear()
	_loaded.clear()
	_sources_cache = null
	generation += 1


# --- Art sets ---------------------------------------------------------------------------------

## The sets that can be switched to: "default" (res://assets/manifest.json), every folder in
## res://assets/sets/ with a manifest.json (the AI trial, hand-made packs), and "placeholder".
static func available_sets() -> Array[String]:
	var out: Array[String] = [DEFAULT_SET]
	var dir := DirAccess.open(sets_dir)
	if dir != null:
		var names := dir.get_directories()
		names.sort()
		for n in names:
			if FileAccess.file_exists(sets_dir.path_join(n).path_join("manifest.json")):
				out.append(n)
	out.append(PLACEHOLDER_SET)
	return out


## Use art set `name` from now on (unknown names fall back to "default"). Returns the set in use.
static func use_set(name: String) -> String:
	_env_read = true
	var all := available_sets()
	art_set = name if all.has(name) else DEFAULT_SET
	_cache.clear()
	_loaded.clear()
	_sources_cache = null
	generation += 1
	return art_set


## The next set in `available_sets()` after the current one (the dev key).
static func cycle_set() -> String:
	var all := available_sets()
	return use_set(all[(all.find(art_set) + 1) % all.size()])


## Take the set from the CRAWL_ART_SET environment variable the first time art is asked for.
static func _read_env() -> void:
	if _env_read:
		return
	_env_read = true
	var want := OS.get_environment("CRAWL_ART_SET")
	if want != "" and want != art_set:
		art_set = want if available_sets().has(want) else art_set


## True when some manifest supplies a picture for `key` (not just the placeholder).
static func has_art(key: String) -> bool:
	return _supplied(key) != null


## The raw picture for `key` from the registered images or the active manifests, or null (textures, tiles, icons).
static func supplied(key: String) -> Image:
	return _supplied(key)


# --- Asset keys -------------------------------------------------------------------------

## The asset key for a monster: Headliners are boss:boss_N, Acts mon:<tier>_<base>, the rest mon:<key>.
static func monster_key(m: Monster) -> String:
	if m.tier == "headliner":
		return "boss:" + m.base
	if m.tier != "":
		return "mon:%s_%s" % [m.tier, m.base]
	return "mon:" + m.key


## The body plan name behind a monster: its base (an Act's monster, a Headliner's boss_N) or its key.
static func look_of(m: Monster) -> String:
	return m.base if m.base != "" else m.key


## Every asset key the game can ask for (monsters, Acts, Headliners, pets, items, furniture, stairs).
static func all_keys() -> Array[String]:
	var out: Array[String] = []
	for k: String in Content.table("monsters"):
		out.append("mon:" + k)
		out.append("mon:opening_" + k)
		out.append("mon:featured_" + k)
	for d: String in Content.table("bosses"):
		out.append("boss:boss_" + d)
	for k: String in Content.table("pets"):
		out.append("pet:" + k)
	for k: String in Content.table("items")["items"]:
		out.append("item:" + k)
	for k: String in Content.table("ui_config")["hud"]["FURNITURE_GLYPHS"]:
		out.append("furn:" + k)
	out.append_array(["fx:stairs_open", "fx:stairs_locked", "player:crawler"])
	for r: String in Content.table("races"):
		out.append("player:" + r)
	return out


# --- Lookup -----------------------------------------------------------------------------

## A finished creature sprite. `key` is a mon:/boss:/pet: asset key, `colour` the creature's
## colour (the body-plan placeholders are drawn in it), `tier` picks the outline colour.
static func creature(key: String, colour: Array, tier: String = "") -> Image:
	var outline := OUTLINE
	var tiers: Dictionary = Content.table("ui_config")["firstperson"]["TIER_OUTLINE"]
	if tiers.has(tier):
		var t: Array = tiers[tier]
		outline = Color8(t[0], t[1], t[2])
	elif tier == "player":
		outline = UiColours.c("PLAYER_COLOUR")      # white: you stand out on the map
	var ck := "%s|%s|%s" % [key, str(colour), outline.to_html()]
	if _cache.has(ck):
		return _cache[ck]
	var base := _supplied(key)
	if base == null and _base_key(key) != key:
		base = _supplied(_base_key(key))        # an Act without its own art uses its monster's, with a badge or sash
		if base != null:
			base = _with_act_overlay(base, key.get_slice(":", 1).get_slice("_", 0))
	if base == null and key.begins_with("player:") and key != "player:crawler":
		base = _supplied("player:crawler")
	if base == null:
		var c := PixelCanvas.new(SIZE)
		_body(c, _plan_name(key), Color8(colour[0], colour[1], colour[2]))
		base = c.image
	var out := finish_creature(base, outline)
	_cache[ck] = out
	return out


## The top-down player for `race` ("" before a race is chosen): white outline, one picture per race.
static func player(race: String) -> Image:
	return creature("player:" + (race if race != "" else "crawler"), [255, 255, 255], "player")


## The size of an item billboard in wall heights: 0.32 for the placeholder glyph shapes, 0.4 for real art (art bible 6).
static func item_scale(item_key: String) -> float:
	return 0.4 if has_art("item:" + item_key) else 0.32


## A finished item sprite (lying on the floor, shapes by kind: weapons diagonal, armour a torso,
## potions bottles, bombs round with a fuse, junk greyish).
static func item(item_key: String) -> Image:
	return _plain("item:" + item_key, func(c: PixelCanvas) -> void: _item_shape(c, item_key))


## A finished furniture sprite for "bed", "bench" or "counter".
static func furniture(kind: String) -> Image:
	return _plain("furn:" + kind, func(c: PixelCanvas) -> void: _furniture_shape(c, kind))


## The floating stairwell arrow: gold when open, red with a padlock when locked.
static func stairs(locked: bool) -> Image:
	var key := "fx:stairs_locked" if locked else "fx:stairs_open"
	return _plain(key, func(c: PixelCanvas) -> void: _stairs_shape(c, locked))


## The soft dark ellipse under an item (Python's glyph_sprite shadow), as an opaque white ellipse:
## the billboard tints it black and fades it. 32 x 32, in the bottom rows.
static func shadow() -> Image:
	return _plain("fx:shadow", func(c: PixelCanvas) -> void: c.ellipse(4, 22, 24, 10, Color.WHITE))


## Light from above and a one pixel outline round the opaque pixels, binary alpha.
static func finish_creature(src: Image, outline: Color) -> Image:
	var img := src.duplicate() as Image
	if img.get_format() != Image.FORMAT_RGBA8:
		img.convert(Image.FORMAT_RGBA8)
	var w := img.get_width()
	var h := img.get_height()
	var solid := PackedByteArray()
	solid.resize(w * h)
	for y in h:
		var k := lerpf(1.1, 0.75, y / float(h - 1))
		for x in w:
			var p := img.get_pixel(x, y)
			if p.a > 0.0:
				solid[y * w + x] = 1
				img.set_pixel(x, y, Color(minf(p.r * k, 1.0), minf(p.g * k, 1.0), minf(p.b * k, 1.0), 1.0))
			else:
				img.set_pixel(x, y, Color(0, 0, 0, 0))
	for y in h:
		for x in w:
			if solid[y * w + x] == 1:
				continue
			if (x > 0 and solid[y * w + x - 1] == 1) or (x < w - 1 and solid[y * w + x + 1] == 1) \
					or (y > 0 and solid[(y - 1) * w + x] == 1) or (y < h - 1 and solid[(y + 1) * w + x] == 1):
				img.set_pixel(x, y, outline)
	return img


## Image.get_used_rect for sprites: the bounding box of the opaque pixels.
## One frame (0 or 1) of a wall torch's flame on its bracket (P8), 32 x 32; the views flicker between them.
static func torch(frame: int) -> Image:
	return _plain("fx:torch_%d" % (frame % 2), func(c: PixelCanvas) -> void: _torch_shape(c, frame % 2))


## The first-person weapon view model for an equipped weapon (`item_key` "" for bare hands) of `style`
## ("blade", "blunt" or "unarmed"): 80 x 80 with the hands holding it, the grip at the bottom centre,
## drawn by WeaponArt until real art is registered as `wpn:<item>` or `wpn:<style>`.
static func weapon_view(item_key: String, style: String) -> Image:
	var key := "wpn:" + (item_key if item_key != "" else "unarmed")
	if _cache.has(key):
		return _cache[key]
	var img := _supplied(key)
	if img == null:
		img = _supplied("wpn:" + style)
	if img == null:
		img = WeaponArt.paint(item_key, style)
	_cache[key] = img
	return img


static func bounds(img: Image) -> Rect2i:
	return img.get_used_rect()


static func _plain(key: String, painter: Callable) -> Image:
	if _cache.has(key):
		return _cache[key]
	var img := _supplied(key)
	if img == null:
		var c := PixelCanvas.new(SIZE)
		painter.call(c)
		img = c.image
	_cache[key] = img
	return img


## An image from register() or the active manifests, or null.
static func _supplied(key: String) -> Image:
	if _overrides.has(key):
		return _overrides[key]
	_read_env()
	if _loaded.has(key):
		var got: Variant = _loaded[key]
		return got if got is Image else null
	var found: Image = null
	for src: Dictionary in _sources():
		var entries: Dictionary = src["entries"]
		if not entries.has(key):
			continue
		var entry: Variant = entries[key]
		if not entry is Dictionary:
			continue
		var path: String = String(src["dir"]) + String((entry as Dictionary).get("file", ""))
		if FileAccess.file_exists(path):
			var img := read_image(path)
			if img != null:
				found = img
				break
	_loaded[key] = found if found != null else false
	return found


## A PNG as an RGBA8 Image, or null. Imported pictures load as resources (the way that survives an export);
## one the editor has not imported yet (a fresh artgen set, a new checkout before `godot --import`) is read
## from disk instead.
static func read_image(path: String) -> Image:
	var img: Image = null
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex != null:
			img = tex.get_image()
	if img == null:
		img = Image.load_from_file(ProjectSettings.globalize_path(path))
	if img == null or img.is_empty():
		return null
	if img.is_compressed():
		img.decompress()
	img.convert(Image.FORMAT_RGBA8)
	return img


## The manifests in priority order: the active set's own, then the default one ("placeholder": none).
static func _sources() -> Array:
	if _sources_cache != null:
		return _sources_cache
	var out: Array = []
	if art_set != PLACEHOLDER_SET:
		if art_set != DEFAULT_SET:
			_add_source(out, sets_dir.path_join(art_set) + "/")
		_add_source(out, ASSETS)
	_sources_cache = out
	return out


static func _add_source(out: Array, dir: String) -> void:
	var path := dir + "manifest.json"
	if not FileAccess.file_exists(path):
		return
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if parsed is Dictionary:
		out.append({"dir": dir, "entries": parsed})


## An Act's look: the base monster's picture with the tier's overlay (`fx:badge_opening` lanyard badge,
## `fx:sash_featured` star sash) laid over its body, only where the base has pixels. Without the overlay
## picture the base is used as it is.
static func _with_act_overlay(base: Image, tier: String) -> Image:
	var over := _supplied("fx:badge_opening" if tier == "opening" else "fx:sash_featured")
	if over == null:
		return base
	var out := base.duplicate() as Image
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	var used := base.get_used_rect()
	if used.size.x <= 0:
		return base
	var ow := over.get_width()
	var oh := over.get_height()
	var ox := used.position.x + used.size.x / 2 - ow / 2
	var oy: int
	if tier == "opening":                           # the badge hangs from the neck, about a third of the way down
		oy = used.position.y + int(used.size.y * 0.28) - 1
	else:                                           # the sash crosses the middle of the body
		oy = used.position.y + used.size.y / 2 - oh / 2
	for y in oh:
		for x in ow:
			var p := over.get_pixel(x, y)
			var tx := ox + x
			var ty := oy + y
			if p.a > 0.5 and tx >= 0 and ty >= 0 and tx < out.get_width() and ty < out.get_height() \
					and out.get_pixel(tx, ty).a > 0.5:
				out.set_pixel(tx, ty, Color(p.r, p.g, p.b, 1.0))
	return out


## mon:opening_goblin -> mon:goblin; other keys unchanged.
static func _base_key(key: String) -> String:
	var parts := key.split(":")
	if parts.size() == 2:
		for tier in ["opening_", "featured_"]:
			if parts[1].begins_with(tier):
				return parts[0] + ":" + parts[1].substr(tier.length())
	return key


## The body plan name behind a key ("mon:opening_goblin" -> "goblin", "boss:boss_3" -> "boss_3").
static func _plan_name(key: String) -> String:
	return _base_key(key).get_slice(":", 1)


static func _shade(c: Color, k: float) -> Color:
	return Color(clampf(c.r * k, 0.0, 1.0), clampf(c.g * k, 0.0, 1.0), clampf(c.b * k, 0.0, 1.0))


static func _pts(a: Array) -> Array[Vector2]:
	var out: Array[Vector2] = []
	for p in a:
		out.append(Vector2(p[0], p[1]))
	return out


# --- Creature body plans (crawler/ui/firstperson.py BODIES) --------------------------------

static func _body(c: PixelCanvas, plan: String, col: Color) -> void:
	match plan:
		"gnawer", "mouse":
			_beast(c, col, "round", true, true)
		"goblin":
			_biped(c, col)
		"vacbot":
			_robot(c, col)
		"skeleton":
			_biped(c, col, {"ribs": true})
		"brute":
			_biped(c, col, {"big": true})
		"cultist":
			_biped(c, col, {"robe": true, "hood": true})
		"golem":
			_blob(c, col, {"stitches": true})
		"stalker":
			_ghost(c, col)
		"boss_1":
			_blob(c, col, {"crown": true})
		"boss_2":
			_biped(c, col, {"robe": true, "glasses": true})
		"boss_3":
			_biped(c, col, {"big": true, "hat": true})
		"boss_4":
			_biped(c, col, {"robe": true, "hood": true, "horns": true, "staff": true})
		"boss_5":
			_blob(c, col, {"wrap": true})
		"boss_6":
			_biped(c, col, {"big": true, "horns": true, "tie": true})
		"cat":
			_beast(c, col, "pointy", false, false)
		"dog":
			_beast(c, col, "floppy", false, false)
		"budgie":
			_bird(c, col)
		_:
			_biped(c, col)


static func _biped(c: PixelCanvas, col: Color, o: Dictionary = {}) -> void:
	var dark := _shade(col, 0.6)
	var light := _shade(col, 1.2)
	var w: int = 4 if o.get("big", false) else 0
	if o.get("robe", false):
		c.polygon(_pts([[10 - w, 30], [22 + w, 30], [19 + w / 2, 13], [13 - w / 2, 13]]), dark)
	else:
		c.rect(11 - w / 2, 23, 4, 8, dark)
		c.rect(17 + w / 2, 23, 4, 8, dark)
	c.ellipse(9 - w, 12, 14 + 2 * w, 14, col)
	c.rect(6 - w, 14, 4, 10, col)
	c.rect(22 + w, 14, 4, 10, col)
	c.circle(16, 8, 5, light)
	var hood: bool = o.get("hood", false)
	if hood:
		c.polygon(_pts([[10, 12], [22, 12], [19, 1], [13, 1]]), dark)
		c.rect(13, 6, 6, 5, Color8(20, 14, 24))
	if o.get("ribs", false):
		for y in [15, 18, 21]:
			c.line(Vector2(12, y), Vector2(20, y), dark)
	if o.get("tie", false):
		c.polygon(_pts([[14, 13], [18, 13], [16, 22]]), Color8(240, 240, 240))
		c.polygon(_pts([[15, 14], [17, 14], [16, 21]]), Color8(40, 40, 160))
	if o.get("horns", false):
		c.polygon(_pts([[11, 5], [13, 2], [9, -2]]), Color8(230, 220, 200))
		c.polygon(_pts([[21, 5], [19, 2], [23, -2]]), Color8(230, 220, 200))
	if o.get("crown", false):
		c.polygon(_pts([[11, 4], [21, 4], [21, 0], [19, 2], [16, -1], [13, 2], [11, 0]]), Color8(255, 205, 60))
	if o.get("hat", false):
		c.ellipse(9, 1, 14, 7, Color8(250, 200, 40))
		c.rect(8, 5, 16, 2, Color8(250, 200, 40))
	if o.get("staff", false):
		c.line(Vector2(27, 4), Vector2(27, 30), Color8(150, 110, 70), 2)
		c.circle(27, 4, 3, Color8(180, 255, 200))
	var eye_y := 9 if hood else 8
	var eye := Color8(255, 230, 120) if hood else Color.WHITE
	for ex in [14, 18]:
		c.set_at(ex, eye_y, eye)
	if o.get("glasses", false):
		c.circle(14, 8, 2, Color8(30, 30, 30), 1)
		c.circle(18, 8, 2, Color8(30, 30, 30), 1)


static func _beast(c: PixelCanvas, col: Color, ears: String, tail: bool, small: bool) -> void:
	var dark := _shade(col, 0.6)
	var light := _shade(col, 1.2)
	var off := 6 if small else 0
	c.ellipse(7 + off / 2, 14 + off, 18 - off, 13 - off / 2, col)
	for lx in [10, 19]:
		c.rect(lx + off / 3, 25, 3, 6, dark)
	var hx := 16
	var hy := 13 + off
	if ears == "pointy":
		c.polygon(_pts([[hx - 6, hy - 2], [hx - 3, hy - 4], [hx - 6, hy - 10]]), col)
		c.polygon(_pts([[hx + 6, hy - 2], [hx + 3, hy - 4], [hx + 6, hy - 10]]), col)
	elif ears == "floppy":
		c.ellipse(hx - 10, hy - 5, 5, 10, dark)
		c.ellipse(hx + 5, hy - 5, 5, 10, dark)
	elif ears == "round":
		c.circle(hx - 6, hy - 5, 4, light)
		c.circle(hx + 6, hy - 5, 4, light)
	c.circle(hx, hy, 6 - off / 3, light)
	c.circle(hx, hy + 3, 1, Color8(30, 20, 20))
	for ex in [hx - 3, hx + 2]:
		c.set_at(ex, hy - 1, Color.WHITE)
		c.set_at(ex, hy, Color8(20, 10, 10))
	if tail:
		c.lines(_pts([[24, 26], [29, 22], [30, 16], [27, 12]]), Color8(220, 160, 170))


static func _bird(c: PixelCanvas, col: Color) -> void:
	var dark := _shade(col, 0.6)
	var light := _shade(col, 1.25)
	var beak := Color8(250, 170, 60)
	c.ellipse(6, 14, 8, 12, dark)
	c.ellipse(18, 14, 8, 12, dark)
	c.ellipse(10, 12, 12, 16, col)
	c.circle(16, 10, 5, light)
	c.polygon(_pts([[15, 11], [17, 11], [16, 14]]), beak)
	for ex in [14, 18]:
		c.set_at(ex, 9, Color8(20, 10, 10))
	c.line(Vector2(13, 28), Vector2(13, 31), beak)
	c.line(Vector2(19, 28), Vector2(19, 31), beak)


static func _robot(c: PixelCanvas, col: Color) -> void:
	var dark := _shade(col, 0.55)
	var light := _shade(col, 1.25)
	c.ellipse(3, 20, 26, 11, dark)
	c.ellipse(3, 17, 26, 11, col)
	c.ellipse(8, 18, 16, 5, light)
	c.circle(16, 24, 2, Color8(255, 60, 60))
	for x in range(6, 27, 3):
		c.line(Vector2(x, 29), Vector2(x - 1, 31), Color8(60, 60, 60))


static func _ghost(c: PixelCanvas, col: Color) -> void:
	var light := _shade(col, 1.3)
	c.circle(16, 11, 9, col)
	c.polygon(_pts([[7, 11], [25, 11], [27, 30], [22, 26], [18, 31], [14, 26], [10, 31], [5, 26]]), col)
	c.ellipse(11, 8, 4, 6, Color8(240, 240, 255))
	c.ellipse(17, 8, 4, 6, Color8(240, 240, 255))
	c.circle(16, 11, 9, light, 1)


static func _blob(c: PixelCanvas, col: Color, o: Dictionary = {}) -> void:
	var dark := _shade(col, 0.6)
	var light := _shade(col, 1.2)
	c.ellipse(2, 12, 28, 20, col)
	c.ellipse(7, 4, 18, 16, light)
	for ex in [12, 19]:
		c.circle(ex, 11, 2, Color.WHITE)
		c.set_at(ex, 11, Color8(10, 10, 10))
	c.arc(11, 12, 10, 6, 3.4, 6.0, dark)
	if o.get("stitches", false):
		c.line(Vector2(6, 20), Vector2(26, 24), dark)
		for x in range(8, 26, 4):
			c.line(Vector2(x, 19 + (x - 6) / 5), Vector2(x + 1, 23 + (x - 6) / 5), dark)
	if o.get("wrap", false):                       # cling film, kept inside the body
		var body: Image = c.image.duplicate()
		for k in range(-20, 32, 7):
			c.line(Vector2(k, 31), Vector2(k + 18, 4), Color8(240, 250, 255))
		for y in c.image.get_height():
			for x in c.image.get_width():
				if body.get_pixel(x, y).a == 0.0:
					c.image.set_pixel(x, y, Color(0, 0, 0, 0))
	if o.get("crown", false):
		c.polygon(_pts([[9, 6], [23, 6], [23, 0], [20, 3], [16, -1], [12, 3], [9, 0]]), Color8(255, 205, 60))


# --- Items, furniture, stairs -------------------------------------------------------------------

static func _torch_shape(c: PixelCanvas, frame: int) -> void:
	var edge := Color8(30, 26, 36)
	c.rect(13, 20, 6, 10, edge)                          # bracket
	c.rect(14, 21, 4, 8, Color8(90, 84, 96))
	c.rect(11, 18, 10, 4, edge)                          # cup
	c.rect(12, 19, 8, 2, Color8(120, 110, 100))
	var lean := 1 if frame == 1 else 0
	c.polygon(_pts([[10 + lean, 18], [16, 4 + lean], [22 - lean, 18]]), Color8(200, 60, 20))
	c.polygon(_pts([[12, 18], [16 + lean, 8], [20, 18]]), Color8(255, 150, 30))
	c.polygon(_pts([[14, 18], [16, 12 + lean], [18, 18]]), Color8(255, 235, 140))


static func _item_shape(c: PixelCanvas, key: String) -> void:
	var row: Dictionary = Content.item(key)
	var col := Color8(row["colour"][0], row["colour"][1], row["colour"][2])
	var dark := _shade(col, 0.55)
	var edge := Color8(30, 26, 36)
	match row["kind"]:
		"weapon":                                   # a diagonal: handle bottom left, head top right
			c.line(Vector2(7, 27), Vector2(22, 10), edge, 4)
			c.line(Vector2(8, 26), Vector2(21, 11), col, 2)
			if row.get("style", "") == "blunt":
				c.rect(19, 5, 9, 8, edge)
				c.rect(20, 6, 7, 6, col)
			else:
				c.line(Vector2(14, 18), Vector2(26, 5), col, 2)
			c.rect(7, 25, 4, 4, dark)
		"armour":                                   # a torso with sleeves
			c.polygon(_pts([[10, 8], [22, 8], [28, 13], [25, 19], [22, 17], [22, 29], [10, 29], [10, 17], [7, 19], [4, 13]]), edge)
			c.polygon(_pts([[11, 10], [21, 10], [26, 13], [24, 17], [21, 15], [21, 27], [11, 27], [11, 15], [8, 17], [6, 13]]), col)
			c.rect(14, 8, 4, 3, dark)
		"potion":                                   # a bottle: cork, neck, round body
			c.rect(13, 6, 6, 3, Color8(190, 150, 100))
			c.rect(14, 9, 4, 6, edge)
			c.circle(16, 22, 8, edge)
			c.rect(15, 9, 2, 5, col)
			c.circle(16, 22, 7, col)
			c.rect(12, 19, 3, 3, _shade(col, 1.4))
		"bomb":                                     # round, with a fuse and a spark
			c.circle(15, 22, 8, edge)
			c.circle(15, 22, 7, col)
			c.rect(12, 18, 3, 3, _shade(col, 1.4))
			c.lines(_pts([[19, 14], [22, 10], [25, 9]]), Color8(200, 170, 110))
			c.circle(26, 8, 2, Color8(255, 240, 120))
		_:                                          # junk: a lumpy greyish thing
			c.ellipse(6, 16, 20, 13, edge)
			c.ellipse(7, 17, 18, 11, _shade(col, 0.8))
			c.ellipse(11, 14, 10, 8, edge)
			c.ellipse(12, 15, 8, 6, col)


static func _furniture_shape(c: PixelCanvas, kind: String) -> void:
	if kind == "bed":
		c.rect(2, 18, 28, 8, Color8(90, 60, 40))
		c.rect(3, 13, 26, 7, Color8(150, 180, 230))
		c.rect(4, 11, 8, 5, Color8(240, 240, 240))
		for x in [3, 27]:
			c.rect(x, 24, 2, 8, Color8(70, 45, 30))
	elif kind == "bench":
		c.rect(1, 14, 30, 5, Color8(160, 115, 70))
		for x in [3, 26]:
			c.rect(x, 19, 3, 13, Color8(110, 80, 50))
		c.rect(6, 9, 7, 5, Color8(170, 170, 180))                       # vice
		c.line(Vector2(18, 13), Vector2(26, 6), Color8(200, 200, 210), 2)   # spanner
	else:
		c.rect(0, 14, 32, 18, Color8(120, 90, 140))
		c.rect(0, 12, 32, 3, Color8(255, 196, 64))
		c.rect(11, 4, 10, 8, Color8(60, 200, 120))                      # till
		c.rect(13, 6, 6, 3, Color8(20, 40, 30))


static func _stairs_shape(c: PixelCanvas, locked: bool) -> void:
	var col := Color8(235, 80, 80) if locked else Color8(255, 196, 64)
	var tri := _pts([[6, 10], [26, 10], [16, 26]])
	c.polygon(tri, col)
	c.polygon_outline(tri, Color8(60, 30, 10))
	if locked:
		c.rect(12, 14, 8, 6, Color8(40, 30, 30))
		c.arc(12, 8, 8, 10, 0.0, 3.15, Color8(40, 30, 30))

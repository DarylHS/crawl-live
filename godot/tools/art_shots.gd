extends SceneTree
## P9 art screenshots: both views on all six floors, sprite sheets of every picture, the safe room, stairs,
## the 32 px tiles against the 16 px glyph overview, and menu screens with the new art.
##
##   xvfb-run -a godot --path godot --rendering-driver opengl3 --resolution 1280x768 \
##       -s res://tools/art_shots.gd -- --out /tmp/crawl-p9/shots [--set default|placeholder|ai_trial] \
##       [--only sheets,floors,rooms,zoom,menus] [--seed 1]
##
## Needs a display (Xvfb is fine). The game runs through the real Main scene (title to HUD), so the shots
## show exactly what a player sees at 1280 x 768. Nothing here touches the rules: worlds are staged by
## placing the player and monsters the way tools/screenshots.gd does, and by marking tiles explored so the
## map views have something to show.

var out_dir := ""
var seed_value := 1
var only: PackedStringArray = PackedStringArray()
var main: Main = null
var app: AppState = null


func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	out_dir = args.get("out", "")
	if out_dir == "":
		push_error("art_shots.gd: pass -- --out=<dir>")
		quit(2)
		return
	seed_value = int(args.get("seed", "1"))
	if args.has("set"):
		SpriteArt.use_set(args["set"])
	if args.has("only"):
		only = String(args["only"]).split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _want(name: String) -> bool:
	return only.is_empty() or only.has(name)


func _run() -> void:
	var scene: PackedScene = load("res://scenes/main.tscn")
	main = scene.instantiate()
	main.summary_on_headless = false
	main.options = {"quick": "", "seed": str(seed_value), "pet": "dog",
			"save-dir": "/tmp/crawl-p9/save", "runs-dir": "/tmp/crawl-p9/runs"}
	root.add_child(main)
	await _frames(4)
	app = main.app
	app.settings["effects"] = "reduced"
	if _want("menus"):
		await _title_shot()
	if _want("sheets"):
		await _sheets()
	if _want("floors"):
		await _floor_shots()
	if _want("rooms"):
		await _room_shots()
	if _want("zoom"):
		await _zoom_shots()
	if _want("menus"):
		await _menu_shots()
	quit(0)


func _frames(n: int) -> void:
	for _i in n:
		await process_frame
	await RenderingServer.frame_post_draw


func _save(name: String) -> void:
	await _frames(3)
	var img := root.get_texture().get_image()
	var path := out_dir.path_join(name + ".png")
	img.save_png(path)
	print("shot ", path)


func _hero() -> Dictionary:
	return {"name": "Crawler", "gender": Content.table("genders").keys()[0],
			"backstory": Content.table("backstories").keys()[0]}


func _empty(w: World, x: int, y: int) -> bool:
	return w.floor.walkable(x, y) and w.monster_at(x, y) == null and w.pet_at(x, y) == null


## A fresh world on `depth`, quiet, with the player at the start of an open stretch `forward` tiles deep.
func _staged_world(depth: int, forward: int = 6, half_w: int = 2) -> Array:
	var w := World.new(seed_value, ["dog", "Rex"], _hero())
	for d in range(2, depth + 1):
		w.new_floor(d)
	w.monsters.clear()
	var f := w.floor
	for y in f.height:
		for x in f.width:
			for d in 4:
				var s: Vector2i = FpLogic.DIRS[d]
				var side := Vector2i(-s.y, s.x)
				var ok := true
				for k in range(0, forward + 1):
					for l in range(-half_w, half_w + 1):
						var t := Vector2i(x, y) + s * k + side * l
						if not _empty(w, t.x, t.y) or f.is_safe(t.x, t.y) or w.floor_items.has(t):
							ok = false
							break
					if not ok:
						break
				if ok:
					w.player.x = x
					w.player.y = y
					w.update_fov()
					return [w, Vector2i(x, y), d, s, side]
	push_error("art_shots.gd: no open area on floor %d" % depth)
	return []


## The tile `forward` ahead and `lateral` to the right of a staged area's start.
func _at(st: Array, forward: int, lateral: int) -> Vector2i:
	var o: Vector2i = st[1]
	var s: Vector2i = st[3]
	var side: Vector2i = st[4]
	return o + s * forward + side * lateral


func _show(w: World, view: String, angle: Variant = null, zoom: String = "tiles") -> void:
	app.attach_world(w)
	app.overlay = ""
	app.set_map_zoom(zoom)
	app.set_view(view)
	main.game_view.fx_director.on_key()
	var fpv := main.game_view.fp_view
	if angle != null:
		fpv.logic.angle = angle
	fpv.logic.cam = []
	fpv.refresh(0.0)
	main._apply_scene()


## Everything the player has "seen" within `radius` tiles, so the map views show a lived-in floor.
func _explore(w: World, radius: int) -> void:
	var f := w.floor
	var p := w.player
	for y in range(maxi(0, p.y - radius), mini(f.height, p.y + radius + 1)):
		for x in range(maxi(0, p.x - radius), mini(f.width, p.x + radius + 1)):
			if Vector2(x - p.x, y - p.y).length() <= radius:
				f.explored[y][x] = 1


func _cast(depth: int) -> Array:
	var mons: Array = []
	for k: String in Content.table("monsters"):
		var fl: Array = Content.table("monsters")[k]["floors"]
		if depth >= fl[0] and depth <= fl[1]:
			mons.append(k)
	return mons


func _populate(st: Array, depth: int) -> void:
	var w: World = st[0]
	var o: Vector2i = st[1]
	var s: Vector2i = st[3]
	var side: Vector2i = st[4]
	var cast := _cast(depth)
	var spots: Array = [[3, -1], [4, 1], [6, 0]]
	for i in spots.size():
		var sp: Array = spots[i]
		var t := o + s * int(sp[0]) + side * int(sp[1])
		var m := Entities.spawn_monster(cast[i % cast.size()], t.x, t.y)
		if i == 1:
			m.hp = maxi(1, m.max_hp / 2)
		w.monsters.append(m)
	var item_keys := ["tonic", "cleaver", "pan", "trophy", "plate", "popper"]
	w.floor_items[o + s * 2 + side] = [item_keys[depth - 1]]
	w.floor_items[o + s * 5 - side] = [item_keys[(depth + 2) % item_keys.size()]]
	w.pet.x = (o + s).x
	w.pet.y = (o + s).y
	w.update_fov()


func _floor_shots() -> void:
	for depth in range(1, 7):
		var st := _staged_world(depth)
		if st.is_empty():
			continue
		var w: World = st[0]
		_populate(st, depth)
		if depth == 3:                                  # an Opening Act and a Featured Act on floor 3
			var ta := _at(st, 5, 1)
			w.monsters.append(Bosses.spawn_act("opening", "goblin", ta.x, ta.y))
			var tb := _at(st, 4, -2)
			w.monsters.append(Bosses.spawn_act("featured", "brute", tb.x, tb.y))
			w.update_fov()
		_show(w, "fp", float(int(st[2]) * 90))
		await _save("floor%d_fp" % depth)
		_explore(w, 14)
		_show(w, "top", null, "tiles")
		await _save("floor%d_top32" % depth)


func _room_shots() -> void:
	# the safe room (first-person facing the furniture, then the map), both of floor 1 and floor 4
	for depth in [1, 4]:
		var w := World.new(seed_value, ["dog", "Rex"], _hero())
		for d in range(2, depth + 1):
			w.new_floor(d)
		w.monsters.clear()
		var c := w.floor.safe_room.centre()
		w.player.x = c.x
		w.player.y = c.y
		w.update_fov()
		var best: Vector2i = w.floor.furniture.keys()[0]
		for t: Vector2i in w.floor.furniture:
			if (t - c).length_squared() < (best - c).length_squared():
				best = t
		var a := PyMath.fmod_py(rad_to_deg(atan2(best.x - c.x, c.y - best.y)), 360.0)
		_show(w, "fp", a)
		await _save("safe_room_floor%d_fp" % depth)
		_explore(w, 12)
		_show(w, "top", null, "tiles")
		await _save("safe_room_floor%d_top32" % depth)
	# stairs, locked and open, with a Headliner key for the open one
	for open in [false, true]:
		var w := World.new(seed_value, ["dog", "Rex"], _hero())
		w.monsters.clear()
		w.has_key = open
		var s: Vector2i = w.floor.stairs[0]
		var placed := false
		for r in range(2, 5):
			for d in 4:
				var dir: Vector2i = FpLogic.DIRS[d]
				var t := s - dir * r
				if not placed and w.floor.walkable(t.x, t.y) and _empty(w, t.x, t.y):
					var clear := true
					for k in range(1, r):
						if not w.floor.walkable(s.x - dir.x * k, s.y - dir.y * k):
							clear = false
					if clear:
						w.player.x = t.x
						w.player.y = t.y
						placed = true
						w.update_fov()
						_show(w, "fp", float(d * 90))
		if placed:
			await _save("stairs_%s_fp" % ("open" if open else "locked"))
			_explore(w, 10)
			_show(w, "top", null, "tiles")
			await _save("stairs_%s_top32" % ("open" if open else "locked"))


## The same moment at 32 px (tiles) and 16 px (the glyph overview the Z key zooms out to), with a fight on.
func _zoom_shots() -> void:
	var st := _staged_world(2, 6, 3)
	if st.is_empty():
		return
	var w: World = st[0]
	_populate(st, 2)
	var tk := _at(st, 3, 2)
	var boss := Bosses.spawn_act("opening", "skeleton", tk.x, tk.y)
	w.monsters.append(boss)
	w.update_fov()
	if w.monsters.size() > 0:
		w.join_combat(w.monsters[0])
	_explore(w, 14)
	_show(w, "top", null, "tiles")
	await _save("zoom_tiles32")
	_show(w, "top", null, "glyphs")
	await _save("zoom_glyphs16")
	# a Headliner fight: tier box, brackets, health bar
	var st2 := _staged_world(3, 6, 3)
	var w3: World = st2[0]
	var th := _at(st2, 3, 0)
	var hb := Bosses.spawn_boss(3, th.x, th.y)
	hb.hp = hb.max_hp * 2 / 3
	w3.monsters.append(hb)
	w3.update_fov()
	w3.join_combat(hb)
	_explore(w3, 14)
	_show(w3, "top", null, "tiles")
	await _save("headliner_top32")
	_show(w3, "fp", float(int(st2[2]) * 90))
	await _save("headliner_fp")


func _title_shot() -> void:
	app.scene = AppState.TITLE
	main._apply_scene()
	await _save("menu_title")
	app.scene = AppState.GAME


func _menu_shots() -> void:
	var w := World.new(seed_value, ["dog", "Rex"], _hero())
	w.inventory = ["tonic", "cleaver", "plate", "popper", "sock", "extinguisher", "elixir", "trophy"]
	w.equipment["weapon"] = "katana"
	w.equipment["armour"] = "jersey"
	w.boxes = ["gold", "silver", "bronze", "bronze"]
	w.gold = 140
	w.monsters.clear()
	_show(w, "fp", null)
	app.open_overlay("inventory")
	main._apply_scene()
	await _save("menu_inventory")
	app.overlay = ""
	app.open_overlay("safe")
	await _save("menu_safe_room")
	app.overlay = ""
	# the box reveal, after the animation has run its course
	var c := w.floor.safe_room.centre()                  # boxes open in the safe room
	w.player.x = c.x
	w.player.y = c.y
	w.update_fov()
	if w.open_box("gold"):
		app.overlay = "reveal"
		main.hud.reveal.skip()
		main._apply_scene()
		await _save("menu_box_reveal")
	app.overlay = ""
	app.show_help = true
	app.set_view("top")
	await _save("menu_help_top")
	app.show_help = false


# --- Sprite sheets -----------------------------------------------------------------------------

func _sheets() -> void:
	app.scene = AppState.TITLE
	main.visible = false
	var holder := Control.new()
	holder.set_anchors_preset(Control.PRESET_FULL_RECT)
	holder.size = Vector2(1280, 768)
	root.add_child(holder)
	var bg := ColorRect.new()
	bg.color = Color8(40, 38, 50)
	bg.size = Vector2(1280, 768)
	holder.add_child(bg)
	var monsters: Dictionary = Content.table("monsters")
	var creatures: Array = []
	for k: String in monsters:
		creatures.append(["mon:" + k, monsters[k]["colour"], "", monsters[k]["name"]])
	await _sheet(holder, "sheet_monsters", creatures, 4)
	var acts: Array = []
	for tier in ["opening", "featured"]:
		for k: String in monsters:
			acts.append(["mon:%s_%s" % [tier, k], monsters[k]["colour"], tier, "%s %s" % [tier, k]])
	await _sheet(holder, "sheet_acts", acts, 8)
	var bosses: Array = []
	for d: String in Content.table("bosses"):
		bosses.append(["boss:boss_" + d, Content.table("bosses")[d]["colour"], "headliner", Content.table("bosses")[d]["name"]])
	await _sheet(holder, "sheet_headliners", bosses, 6)
	var pets: Array = []
	for k: String in Content.table("pets"):
		pets.append(["pet:" + k, Content.table("pets")[k]["colour"], "", Content.table("pets")[k]["name"]])
	for r: String in Content.table("races"):
		pets.append(["player:" + r, [255, 255, 255], "player", "race " + r])
	pets.append(["player:crawler", [255, 255, 255], "player", "no race yet"])
	await _sheet(holder, "sheet_pets_players", pets, 5)
	var items: Array = []
	for k: String in Content.table("items")["items"]:
		items.append(["item:" + k, [255, 255, 255], "", k])
	for k: String in Content.table("loot_boxes"):
		items.append(["box:" + k, [255, 255, 255], "", "box " + k])
	for k in ["bed", "bench", "counter"]:
		items.append(["furn:" + k, [255, 255, 255], "", k])
	items.append(["fx:stairs_open", [255, 255, 255], "", "stairs open"])
	items.append(["fx:stairs_locked", [255, 255, 255], "", "stairs locked"])
	await _sheet(holder, "sheet_items_furniture", items, 6)
	await _terrain_sheet(holder)
	holder.queue_free()
	main.visible = true
	app.scene = AppState.GAME


func _image_for(spec: Array) -> Image:
	var key: String = spec[0]
	var kind := key.get_slice(":", 0)
	var nm := key.get_slice(":", 1)
	match kind:
		"item":
			return SpriteArt.item(nm)
		"furn":
			return SpriteArt.furniture(nm)
		"fx":
			return SpriteArt.stairs(nm == "stairs_locked")
		"box":
			var b := SpriteArt.supplied(key)
			return b if b != null else SpriteArt.shadow()
	return SpriteArt.creature(key, spec[1], spec[2])


func _sheet(holder: Control, name: String, specs: Array, cols: int) -> void:
	var grid := GridContainer.new()
	grid.columns = cols
	grid.position = Vector2(16, 16)
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 10)
	holder.add_child(grid)
	var zoom := 5 if specs.size() <= 12 else 4
	for spec: Array in specs:
		var cell := VBoxContainer.new()
		var tr := TextureRect.new()
		tr.texture = ImageTexture.create_from_image(_image_for(spec))
		tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		tr.custom_minimum_size = Vector2(32 * zoom, 32 * zoom)
		tr.stretch_mode = TextureRect.STRETCH_SCALE
		tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		var bgc := ColorRect.new()
		bgc.color = Color8(60, 56, 72)
		bgc.custom_minimum_size = tr.custom_minimum_size
		bgc.add_child(tr)
		tr.size = tr.custom_minimum_size
		cell.add_child(bgc)
		var lb := Label.new()
		lb.text = String(spec[3])
		lb.add_theme_font_size_override("font_size", 12)
		cell.add_child(lb)
		grid.add_child(cell)
	await _save(name)
	grid.queue_free()
	await process_frame


## Walls, floors and ceilings of every floor, tinted as the first-person view tints them, then the top-down tiles.
func _terrain_sheet(holder: Control) -> void:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.position = Vector2(12, 12)
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	holder.add_child(grid)
	var slots := ["wall_a", "wall_b", "floor", "ceiling"]
	for depth in range(1, 7):
		var imgs := FpTextures.images_for_depth(depth)
		var tint := FpLogic.depth_tint(depth)
		for s in slots:
			grid.add_child(_tex_rect(_tinted(imgs[s], tint), 2.0, "floor %d %s (tinted)" % [depth, s]))
	var common := FpTextures.images_for_depth(1)
	for s in ["safe_wall", "safe_floor", "stairs"]:
		grid.add_child(_tex_rect(common[s], 2.0, s + " (never tinted)"))
	var locked := FpTextures.art_image("tex:stairs_locked")
	if locked != null:
		grid.add_child(_tex_rect(locked, 2.0, "stairs locked"))
	await _save("sheet_textures")
	grid.queue_free()
	await process_frame


func _tinted(img: Image, tint: Color) -> Image:
	var out := img.duplicate() as Image
	if out.get_format() != Image.FORMAT_RGBA8:
		out.convert(Image.FORMAT_RGBA8)
	for y in out.get_height():
		for x in out.get_width():
			var c := out.get_pixel(x, y)
			out.set_pixel(x, y, Color(minf(c.r * tint.r, 1.0), minf(c.g * tint.g, 1.0), minf(c.b * tint.b, 1.0), 1.0))
	return out


func _tex_rect(img: Image, zoom: float, text: String) -> Control:
	var box := VBoxContainer.new()
	var tr := TextureRect.new()
	tr.texture = ImageTexture.create_from_image(img)
	tr.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	tr.custom_minimum_size = Vector2(img.get_width(), img.get_height()) * zoom * 0.75
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	box.add_child(tr)
	var lb := Label.new()
	lb.text = text
	lb.add_theme_font_size_override("font_size", 11)
	box.add_child(lb)
	return box


func _parse(args: PackedStringArray) -> Dictionary:
	var out := {}
	var i := 0
	while i < args.size():
		var a := args[i]
		if a.begins_with("--"):
			var k := a.substr(2)
			if "=" in k:
				out[k.get_slice("=", 0)] = k.get_slice("=", 1)
			elif i + 1 < args.size() and not args[i + 1].begins_with("--"):
				out[k] = args[i + 1]
				i += 1
			else:
				out[k] = ""
		i += 1
	return out

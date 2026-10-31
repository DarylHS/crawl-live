extends SceneTree
## Renders scripted first-person views to PNG files (port plan Appendix B: the screenshot sweep).
##
##   xvfb-run -a godot --path godot --rendering-driver opengl3 -s res://tools/screenshots.gd \
##       -- --screenshots=/some/dir [--seed 1] [--pet cat|dog|budgie|mouse|none] [--fps-frames 300]
##
## P9: the pairing shots use the code-drawn placeholder pictures (pygame has no real art); `-- --with-art` keeps the
## real art and the 32 px map tiles are not part of this tool (see tools/art_shots.gd for those).
##
## Needs a display (Xvfb is fine; software GL works). For each shot it writes <name>.png (the
## 320 x 200 frame scaled to 1024 x 640 with hard pixels, the size of Python's MAP_RECT) and a
## record in shots.json: seed, pet, floors made, player tile, look angle, the exact camera
## [x, y, a], and any changes made to the world (monsters cleared or spawned, a key, combat).
## scripts/fp_compare_shots.py replays shots.json in the pygame raycaster for a side by side.
## P6 adds the HUD shots, hud_<name>_fp.png and hud_<name>_top.png (the whole 1280 x 768 window with the
## side panel, log, tracker, toasts and overlays, in both views), replayed in pygame with `Renderer.draw_game`.
## It also writes window_start.png (the whole P4 main scene) and timings.json (mesh build time per
## floor and frames a second for a scripted walk and turn).
## P7 adds every menu and screen of the pygame sweep (tools/menu_sweep.gd: the scenes, overlays, combat and
## attack of opportunity screens of tests/test_render.py, 70+ names) as <name>_top.png and <name>_fp.png, the
## same names pygame writes with CRAWL_SCREENSHOTS, plus menu_shots.json. `--menus-only` writes just those.

const OUT_W := 1024
const OUT_H := 640

var out_dir := ""
var seed_value := 1
var pet: Variant = null
var fps_frames := 300
var menus_only := false
var gv: GameView = null
var view: FpView = null
var hud: Hud = null
var records: Array = []


func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	out_dir = args.get("screenshots", "")
	if out_dir == "":
		push_error("screenshots.gd: pass -- --screenshots=<dir>")
		quit(2)
		return
	seed_value = int(args.get("seed", "1"))
	var species: String = args.get("pet", Content.table("pets").keys()[0])
	pet = null if species == "none" else [species, ""]
	fps_frames = int(args.get("fps-frames", "300"))
	menus_only = args.has("menus-only")
	if not args.has("with-art"):
		SpriteArt.use_set(SpriteArt.PLACEHOLDER_SET)     # the pygame pairing: placeholder pictures, as in P4 to P8 (--with-art keeps the real art)
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	if menus_only:
		await _menu_shots()
		quit(0)
		return
	var scene: PackedScene = load("res://scenes/game_view.tscn")
	gv = scene.instantiate()
	gv.settings_path = ""                    # shots never touch the player's settings or runs
	gv.runs_dir = ""
	gv.input_enabled = false
	gv.set_plain(true)                       # pygame has no effects or weapon view model
	root.add_child(gv)
	gv.set_anchors_preset(Control.PRESET_TOP_LEFT)
	gv.size = Vector2(OUT_W, OUT_H)
	view = gv.fp_view

	await _shot("start_room", _fresh())
	await _shot_corridor()
	await _shot_safe_room()
	await _shot_stairs(false)
	await _shot_stairs(true)
	for d in range(1, 7):
		await _shot("tint_floor_%d" % d, _fresh(d))
	await _shot_fog()
	await _shot_near_wall()
	await _shot_diagonal()
	await _shot_combat()
	await _shot_mid_glide()
	await _shot_sprites()
	await _shot_scales()
	_sprite_sheet()
	await _hud_shots()

	var timings := await _timings()
	gv.queue_free()
	await process_frame
	await _window_shot()
	await _menu_shots()

	_save_json("shots.json", {"seed": seed_value, "pet": pet, "hero": _hero(), "shots": records})
	_save_json("timings.json", timings)
	print("screenshots: %d shots in %s" % [records.size() + 1, out_dir])
	print("screenshots: mesh build ms per floor %s" % str(timings["build_ms"]))
	print("screenshots: %.1f FPS over %d frames (walk and turn), %.2f ms per frame" % [
			timings["fps"], timings["frames"], timings["ms_per_frame"]])
	quit(0)


# --- Worlds and shots -------------------------------------------------------------

func _hero() -> Dictionary:
	return {"name": "Crawler", "gender": Content.table("genders").keys()[0],
			"backstory": Content.table("backstories").keys()[0]}


## A fresh World on the shot seed, moved down to `depth` with new_floor (as Python tests do).
## The record keeps what to replay.
func _fresh(depth: int = 1) -> Dictionary:
	var w := World.new(seed_value, pet, _hero())
	for d in range(2, depth + 1):
		w.new_floor(d)
	return {"world": w, "floors": range(2, depth + 1), "edits": []}


## Show the world, apply `angle` (or face the open way), settle the camera, save the frame.
## `cam` overrides the camera after it settles (the mid-glide shot).
func _shot(shot_name: String, ctx: Dictionary, angle: Variant = null, cam: Array = []) -> void:
	var w: World = ctx["world"]
	w.update_fov()
	gv.start(w)
	if angle != null:
		view.logic.angle = angle
	view.controller.sync_combat()
	view.logic.cam = []
	view.refresh(0.0)
	if not cam.is_empty():
		view.logic.cam = cam
		view.refresh(0.0)
	await _finish(shot_name, ctx)


## Save the first-person frame (the 3D view without the overlays) and its record, then the
## minimap close-up as "mm_<name>" and the top-down view of the same moment as "top_<name>".
func _finish(shot_name: String, ctx: Dictionary, with_top: bool = true) -> void:
	var w: World = ctx["world"]
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := view.capture()
	img.resize(OUT_W, OUT_H, Image.INTERPOLATE_NEAREST if view.render_scale == "retro" else Image.INTERPOLATE_BILINEAR)
	img.save_png(out_dir.path_join(shot_name + ".png"))
	var rec := {"name": shot_name, "view": "fp", "floors": Array(ctx["floors"]), "edits": (ctx["edits"] as Array).duplicate(true),
			"player": [w.player.x, w.player.y], "angle": view.logic.angle,
			"cam": view.logic.cam.duplicate(), "grid": view.logic.grid,
			"combat": w.combat != null, "stairs_locked": w.stairs_locked}
	records.append(rec)
	if not with_top:
		return
	var win := root.get_texture().get_image()
	var mm := view.minimap
	var r := Rect2i(Vector2i(mm.global_position) - Vector2i(2, 2), Vector2i(mm.size) + Vector2i(4, 40))
	var crop := win.get_region(r)
	crop.resize(r.size.x * 3, r.size.y * 3, Image.INTERPOLATE_NEAREST)
	crop.save_png(out_dir.path_join("mm_" + shot_name + ".png"))
	var mrec := rec.duplicate()
	mrec["name"] = "mm_" + shot_name
	mrec["view"] = "minimap"
	records.append(mrec)
	gv.set_view("top")
	gv.top_view.refresh()
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var top := root.get_texture().get_image().get_region(Rect2i(0, 0, OUT_W, OUT_H))
	top.save_png(out_dir.path_join("top_" + shot_name + ".png"))
	var trec := rec.duplicate()
	trec["name"] = "top_" + shot_name
	trec["view"] = "top"
	records.append(trec)
	gv.set_view("fp")
	view.logic.cam = (rec["cam"] as Array).duplicate()


## Move the player (and refresh FOV), recording it for the replay.
func _place(ctx: Dictionary, x: int, y: int) -> void:
	var w: World = ctx["world"]
	w.player.x = x
	w.player.y = y
	w.update_fov()
	ctx["edits"].append(["place", x, y])


## Clear the monsters and down the pet, so the shot shows the dungeon itself.
func _quiet(ctx: Dictionary) -> void:
	var w: World = ctx["world"]
	w.monsters.clear()
	if w.pet != null:
		w.pet.downed = true
	ctx["edits"].append(["quiet"])


func _empty(w: World, x: int, y: int) -> bool:
	return w.floor.walkable(x, y) and w.monster_at(x, y) == null and w.pet_at(x, y) == null


## Python test_render `_corridor`: a tile and a direction (0-7, in `dirs`) with exactly n empty
## tiles ahead, then something solid; null if none.
func _corridor(w: World, n: int, dirs: Array = [0, 1, 2, 3, 4, 5, 6, 7]) -> Variant:
	var f := w.floor
	for y in f.height:
		for x in f.width:
			if not _empty(w, x, y) or f.is_safe(x, y):
				continue
			for d in dirs:
				var s: Vector2i = FpLogic.DIRS8[d]
				var run := 0
				while _empty(w, x + s.x * (run + 1), y + s.y * (run + 1)):
					run += 1
				if run == n and not f.walkable(x + s.x * (n + 1), y + s.y * (n + 1)):
					return [Vector2i(x, y), d]
	return null


## A one-tile-wide corridor (walls both sides for 3 tiles) with at least 5 open tiles ahead.
func _shot_corridor(shot_name: String = "corridor") -> void:
	var ctx := _fresh()
	var w: World = ctx["world"]
	_quiet(ctx)
	var f := w.floor
	for y in f.height:
		for x in f.width:
			if not f.walkable(x, y) or f.is_safe(x, y):
				continue
			for d in 4:
				var s: Vector2i = FpLogic.DIRS[d]
				var side := Vector2i(-s.y, s.x)
				var ok := true
				for k in range(0, 4):
					var cx := x + s.x * k
					var cy := y + s.y * k
					if not f.walkable(cx, cy) or f.walkable(cx + side.x, cy + side.y) \
							or f.walkable(cx - side.x, cy - side.y):
						ok = false
						break
				var run := 0
				while ok and f.walkable(x + s.x * (run + 1), y + s.y * (run + 1)):
					run += 1
				if ok and run >= 5:
					_place(ctx, x, y)
					await _shot(shot_name, ctx, d * 90.0)
					return
	push_error("screenshots.gd: no corridor found")


## Inside the safe room, facing the nearest furniture (as Python's sweep "safe_room").
func _shot_safe_room() -> void:
	var ctx := _fresh()
	var w: World = ctx["world"]
	_quiet(ctx)
	var c := w.floor.safe_room.centre()
	_place(ctx, c.x, c.y)
	var best: Vector2i = w.floor.furniture.keys()[0]
	for t: Vector2i in w.floor.furniture:
		if (t - c).length_squared() < (best - c).length_squared():
			best = t
	var a := PyMath.fmod_py(rad_to_deg(atan2(best.x - c.x, c.y - best.y)), 360.0)
	await _shot("safe_room", ctx, a)


## Two to four tiles from the first stairwell, in its line of sight, facing it. Open: the
## Headliner's key (has_key), as the Python minimap test does.
func _shot_stairs(open: bool) -> void:
	var ctx := _fresh()
	var w: World = ctx["world"]
	_quiet(ctx)
	if open:
		w.has_key = true
		ctx["edits"].append(["has_key"])
	var st: Vector2i = w.floor.stairs[0]
	for r in [3, 2, 4]:
		for dy in range(-r, r + 1):
			for dx in range(-r, r + 1):
				if maxi(absi(dx), absi(dy)) != r or not w.floor.walkable(st.x + dx, st.y + dy):
					continue
				w.player.x = st.x + dx
				w.player.y = st.y + dy
				w.update_fov()
				if w.visible.has(st):
					_place(ctx, st.x + dx, st.y + dy)
					var a := PyMath.fmod_py(rad_to_deg(atan2(-dx, dy)), 360.0)
					await _shot("stairs_open" if open else "stairs_locked", ctx, a)
					return
	push_error("screenshots.gd: no view of the stairs")


## The longest straight open run from any tile (cardinal), so the fog reaches black.
func _shot_fog() -> void:
	var ctx := _fresh()
	var w: World = ctx["world"]
	_quiet(ctx)
	var f := w.floor
	var best := [0, Vector2i.ZERO, 0]
	for y in f.height:
		for x in f.width:
			if not f.walkable(x, y) or f.is_safe(x, y):
				continue
			for d in 4:
				var s: Vector2i = FpLogic.DIRS[d]
				var run := 0
				while f.walkable(x + s.x * (run + 1), y + s.y * (run + 1)):
					run += 1
				if run > best[0]:
					best = [run, Vector2i(x, y), d]
	_place(ctx, best[1].x, best[1].y)
	await _shot("fog_torch", ctx, best[2] * 90.0)


## A wall dead ahead at 0.5 tiles (the eye is at the tile centre): checks the torch never
## brightens a close wall past what Python draws (it only ever darkens with distance).
func _shot_near_wall() -> void:
	var ctx := _fresh()
	var w: World = ctx["world"]
	_quiet(ctx)
	var f := w.floor
	for y in f.height:
		for x in f.width:
			if not f.walkable(x, y) or f.is_safe(x, y):
				continue
			for d in 4:
				var s: Vector2i = FpLogic.DIRS[d]
				var side := Vector2i(-s.y, s.x)
				# a flat wall: the tile ahead and both its neighbours are wall, the way back is open
				if f.walkable(x + s.x, y + s.y) or f.walkable(x + s.x + side.x, y + s.y + side.y) \
						or f.walkable(x + s.x - side.x, y + s.y - side.y) or not f.walkable(x - s.x, y - s.y):
					continue
				_place(ctx, x, y)
				await _shot("near_wall", ctx, d * 90.0)
				return
	push_error("screenshots.gd: no flat wall found")


## Python test_render `test_looking_diagonally_down_a_corridor`: the longest open diagonal (no
## corner cutting, up to 8 tiles), looking along it at 45 degrees.
func _shot_diagonal() -> void:
	var ctx := _fresh()
	var w: World = ctx["world"]
	var f := w.floor
	var best := [0, Vector2i.ZERO, 1]
	for y in f.height:
		for x in f.width:
			if not _empty(w, x, y):
				continue
			for d in [1, 3, 5, 7]:
				var s: Vector2i = FpLogic.DIRS8[d]
				var run := 0
				var cx := x
				var cy := y
				while run < 8 and f.walkable(cx + s.x, cy + s.y) and f.walkable(cx + s.x, cy) \
						and f.walkable(cx, cy + s.y):
					run += 1
					cx += s.x
					cy += s.y
				if run > best[0]:
					best = [run, Vector2i(x, y), d]
	_place(ctx, best[1].x, best[1].y)
	await _shot("diagonal", ctx, best[2] * 45.0)


## Python test_render `_combat`: a stunned goblin two tiles down a straight corridor, a fight on.
## The look angle starts 30 degrees off the grid; the lock rounds it and the camera settles.
func _shot_combat(shot_name: String = "combat_locked") -> void:
	var ctx := _fresh()
	var w: World = ctx["world"]
	_quiet(ctx)
	var found: Variant = _corridor(w, 3, [0, 2, 4, 6])
	if found == null:
		push_error("screenshots.gd: no straight corridor for the combat shot")
		return
	var spot: Vector2i = found[0]
	var d: int = found[1]
	_place(ctx, spot.x, spot.y)
	var s: Vector2i = FpLogic.DIRS8[d]
	var m := Entities.spawn_monster("goblin", spot.x + 2 * s.x, spot.y + 2 * s.y)
	m.hp = 999
	m.max_hp = 999
	w.monsters.append(m)
	w.update_fov()
	gv.start(w)
	view.logic.angle = d * 45.0 + 30.0        # free look, off the grid
	view.logic.cam = []
	view.refresh(0.0)
	w.join_combat(m)                          # the fight starts
	w.combat.round = 1
	m.stunned = 99
	ctx["edits"].append(["spawn_fight", "goblin", m.x, m.y])
	for _i in 60:                             # the lock rounds the angle; the camera glides there
		view.controller.update(1.0 / 30.0, [])
	assert(view.logic.grid)
	await _shot_current(shot_name, ctx)


## One step down a corridor, a tenth of a second into the glide (0.4 of a tile).
func _shot_mid_glide() -> void:
	var ctx := _fresh()
	var w: World = ctx["world"]
	_quiet(ctx)
	var found: Variant = _corridor(w, 3, [0, 2, 4, 6])
	var spot: Vector2i = found[0]
	var d: int = found[1]
	_place(ctx, spot.x, spot.y)
	gv.start(w)
	view.logic.angle = d * 45.0
	view.logic.cam = []
	view.refresh(0.0)
	view.controller.press(&"walk_forward")
	view.controller.update(0.05, [])
	view.controller.update(0.05, [])
	ctx["edits"].append(["place", w.player.x, w.player.y])
	await _shot_current("mid_glide", ctx)


## Save the frame as it is now (no reset), for shots set up by driving the controller.
func _shot_current(shot_name: String, ctx: Dictionary) -> void:
	view.refresh(0.0)
	await _finish(shot_name, ctx)


# --- Sprites, render scales, Tab --------------------------------------------------------

## Put a monster on the floor and record it for the replay. spec: [kind, a, b, x, y, hp_fraction]
## with kind "mon" (a = monster key), "act" (a = tier, b = base monster) or "boss" (a = depth).
func _spawn(ctx: Dictionary, spec: Array) -> void:
	var w: World = ctx["world"]
	var m: Monster
	match spec[0]:
		"mon":
			m = Entities.spawn_monster(spec[1], spec[3], spec[4])
		"act":
			m = Bosses.spawn_act(spec[1], spec[2], spec[3], spec[4])
		_:
			m = Bosses.spawn_boss(int(spec[1]), spec[3], spec[4])
	m.hp = maxi(1, int(m.max_hp * float(spec[5])))
	w.monsters.append(m)
	ctx["edits"].append(spec)


## Drop an item on the floor (the replay does the same).
func _drop_item(ctx: Dictionary, key: String, tile: Vector2i) -> void:
	var w: World = ctx["world"]
	w.floor_items[tile] = [key]
	ctx["edits"].append(["item", key, tile.x, tile.y])


## A stage: a clear open area ahead of a tile (forward tiles deep, half_w to each side), found by
## scanning the floor. Returns [origin, direction index (0-3), forward step, right step].
func _stage(w: World, forward: int, half_w: int) -> Array:
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
					return [Vector2i(x, y), d, s, side]
	return []


func _staged(forward: int, half_w: int) -> Array:
	var ctx := _fresh()
	var w: World = ctx["world"]
	w.monsters.clear()
	ctx["edits"].append(["clear_monsters"])
	var st := _stage(w, forward, half_w)
	if st.is_empty():
		push_error("screenshots.gd: no %d x %d open area" % [forward, half_w * 2 + 1])
		return []
	_place(ctx, st[0].x, st[0].y)
	return [ctx, st]


func _at(st: Array, forward: int, lateral: int) -> Vector2i:
	return (st[0] as Vector2i) + (st[2] as Vector2i) * forward + (st[3] as Vector2i) * lateral


## Billboards: monsters and damaged ones, the three boss tiers, the pet and items, and monsters at
## distances one to seven.
func _shot_sprites() -> void:
	var a := _staged(6, 3)
	if a.is_empty():
		return
	var ctx: Dictionary = a[0]
	var st: Array = a[1]
	for spec in [["mon", "goblin", "", 2, -1, 1.0], ["mon", "goblin", "", 2, 1, 0.5],
			["mon", "vacbot", "", 4, -1, 1.0], ["mon", "brute", "", 4, 1, 0.25],
			["mon", "skeleton", "", 6, 0, 1.0]]:
		_spawn(ctx, _tile_spec(spec, st))
	await _shot("sprites_monsters", ctx, st[1] * 90.0)

	ctx = _staged(6, 3)[0]
	for spec in [["act", "opening", "skeleton", 4, -2, 1.0], ["act", "featured", "brute", 4, 0, 0.6],
			["boss", 1, "", 4, 2, 1.0]]:
		_spawn(ctx, _tile_spec(spec, st))
	await _shot("sprites_tiers", ctx, st[1] * 90.0)

	ctx = _staged(6, 3)[0]
	var w: World = ctx["world"]
	if w.pet != null:
		var p := _at(st, 2, -1)
		w.pet.x = p.x
		w.pet.y = p.y
		ctx["edits"].append(["pet_to", p.x, p.y])
	for it in [["tonic", 2, 1], ["katana", 3, 0], ["plate", 4, -1], ["popper", 4, 1], ["sock", 5, 0],
			["pan", 5, 2], ["brew", 3, -2]]:
		_drop_item(ctx, it[0], _at(st, it[1], it[2]))
	await _shot("sprites_pet_items", ctx, st[1] * 90.0)

	var b := _staged(8, 1)
	if b.is_empty():
		b = _staged(6, 1)
	ctx = b[0]
	st = b[1]
	var dist := 1
	for lat in [-1, 1, -1, 1, -1, 1, -1]:
		_spawn(ctx, _tile_spec(["mon", "goblin", "", dist, lat, 1.0], st))
		dist += 1
	await _shot("sprites_distances", ctx, st[1] * 90.0)


## A spec with its (forward, lateral) put as x, y tiles of the stage.
func _tile_spec(spec: Array, st: Array) -> Array:
	var t := _at(st, int(spec[3]), int(spec[4]))
	var out := spec.duplicate()
	out[3] = t.x
	out[4] = t.y
	return out


## The same corridor and the same fight at the three render scales.
func _shot_scales() -> void:
	for scale_name in UserSettings.RENDER_SCALES:
		view.set_render_scale(scale_name)
		await _shot_corridor("corridor_" + scale_name)
	for scale_name in UserSettings.RENDER_SCALES:
		view.set_render_scale(scale_name)
		await _shot_combat("combat_" + scale_name)
	view.set_render_scale("retro")


## Every placeholder sprite at 4x on one sheet (what the lookup returns for each asset key).
func _sprite_sheet() -> void:
	var keys := SpriteArt.all_keys()
	var cols := 12
	var rows := ceili(keys.size() / float(cols))
	var sheet := Image.create_empty(cols * 36 * 3, rows * 36 * 3, false, Image.FORMAT_RGBA8)
	sheet.fill(Color8(52, 48, 64))
	var names: Array = []
	for i in keys.size():
		var key := keys[i]
		var img: Image
		var kind := key.get_slice(":", 0)
		var nm := key.get_slice(":", 1)
		if kind == "item":
			img = SpriteArt.item(nm)
		elif kind == "furn":
			img = SpriteArt.furniture(nm)
		elif kind == "fx":
			img = SpriteArt.stairs(nm == "stairs_locked")
		else:
			var tier := ""
			var look := nm
			for t in ["opening_", "featured_"]:
				if nm.begins_with(t):
					tier = t.trim_suffix("_")
					look = nm.substr(t.length())
			var col: Array = [200, 100, 50]
			if kind == "mon":
				col = Content.table("monsters")[look]["colour"]
			elif kind == "boss":
				col = Content.boss(int(look.get_slice("_", 1)))["colour"]
			elif kind == "pet":
				col = Content.table("pets")[look]["colour"]
			img = SpriteArt.creature(key, col, tier if kind == "mon" else ("headliner" if kind == "boss" else ""))
		var big := img.duplicate() as Image
		big.resize(96, 96, Image.INTERPOLATE_NEAREST)
		sheet.blend_rect(big, Rect2i(0, 0, 96, 96), Vector2i((i % cols) * 108 + 6, (i / cols) * 108 + 6))
		names.append(key)
	sheet.save_png(out_dir.path_join("sprite_sheet.png"))
	_save_json("sprite_sheet_keys.json", {"columns": cols, "keys": names})


# --- HUD shots (P6) ----------------------------------------------------------------------

## Apply an edit to the world and record it for the pygame replay (scripts/fp_compare_shots.py
## build_world). Kinds: quiet, place, fight [key | "boss", x, y], player_hp, move, wait, toast,
## encounter, class, use_skill, box, gold, state, mon / act / boss (see _spawn).
func _do(ctx: Dictionary, e: Array) -> void:
	var w: World = ctx["world"]
	match e[0]:
		"quiet":
			_quiet(ctx)
			return
		"place":
			_place(ctx, e[1], e[2])
			return
		"mon", "act", "boss":
			_spawn(ctx, e)
			return
		"fight":
			var m: Monster = Bosses.spawn_boss(w.depth, e[2], e[3]) if e[1] == "boss" \
					else Entities.spawn_monster(e[1], e[2], e[3])
			m.hp = 999
			m.max_hp = 999
			w.monsters.append(m)
			w.update_fov()
			w.join_combat(m)
			w.combat.round = 1
			m.stunned = 0 if e.size() > 4 else 99          # a fifth element: awake, so it can react
		"player_hp":
			w.player.max_hp = e[1]
			w.player.hp = e[1]
		"move":
			w.move_player(e[1], e[2])
		"wait":
			w.wait()
		"toast":
			w.add_toast(e[1], e[2], e[3])
		"encounter":
			var enc := Encounter.new(w.player)
			enc.add(w.player, 10, 1)
			for i in int(e[1]):
				enc.add(Entities.spawn_monster("goblin", 0, 0), i, 0)
			w.combat = enc
		"class":
			w.choose_class(e[1], e[2])
		"use_skill":
			w.use_skill()
		"box":
			w.add_box(e[1], "A screenshot test.")
		"gold":
			w.gold = int(e[1])
		"state":
			w.state = e[1]
			w.death_cause = e[2]
	ctx["edits"].append(e)


## A straight corridor spot (cardinal) of n open tiles ahead, in a quiet world, with the player placed.
## Returns [spot, direction index 0-7 (even), step].
func _hud_corridor(ctx: Dictionary, n: int = 3) -> Array:
	_do(ctx, ["quiet"])
	var w: World = ctx["world"]
	var found: Variant = _corridor(w, n, [0, 2, 4, 6])
	if found == null:
		push_error("screenshots.gd: no straight corridor for a HUD shot")
		return []
	var spot: Vector2i = found[0]
	_do(ctx, ["place", spot.x, spot.y])
	_do(ctx, ["player_hp", 999])
	return [spot, found[1], FpLogic.DIRS8[found[1]]]


## A cardinal spot with an open tile ahead and an open tile behind it (Python test_render `_behind_spot`).
func _behind_spot(w: World) -> Array:
	var f := w.floor
	for y in f.height:
		for x in f.width:
			if not _empty(w, x, y) or f.is_safe(x, y):
				continue
			for d in [0, 2, 4, 6]:
				var s: Vector2i = FpLogic.DIRS8[d]
				if _empty(w, x + s.x, y + s.y) and _empty(w, x - s.x, y - s.y) and not f.is_safe(x - s.x, y - s.y):
					return [Vector2i(x, y), d, s]
	return []


## Show the world in both views and save the whole window for each: hud_<name>_fp.png and _top.png.
## angle: the look angle (null = open way); reset_cam false keeps the camera as it is (a mid-glide).
func _hud_shot(shot_name: String, ctx: Dictionary, angle: Variant = null, reset_cam: bool = true) -> void:
	var w: World = ctx["world"]
	if reset_cam:
		w.update_fov()
		gv.start(w)
		if angle != null:
			view.logic.angle = angle
		view.controller.sync_combat()
		view.logic.cam = []
		view.refresh(0.0)
	var cam: Array = view.logic.cam.duplicate()
	var look: float = view.logic.angle
	var grid: bool = view.logic.grid
	for v in ["fp", "top"]:
		gv.set_view(v)
		for _i in 4:
			await RenderingServer.frame_post_draw
		var img := root.get_texture().get_image()
		var file_name := "hud_%s_%s" % [shot_name, v]
		img.save_png(out_dir.path_join(file_name + ".png"))
		records.append({"name": file_name, "view": "hud_" + v, "floors": Array(ctx["floors"]), "edits": (ctx["edits"] as Array).duplicate(true),
				"player": [w.player.x, w.player.y], "angle": look, "cam": cam, "grid": grid,
				"combat": w.combat != null, "stairs_locked": w.stairs_locked})
	gv.set_view("fp")


func _hud_shots() -> void:
	hud = (load("res://scenes/hud.tscn") as PackedScene).instantiate()
	root.add_child(hud)
	hud.bind(gv)
	gv.set_view("fp")

	var ctx := _fresh()                                         # the opening look of a run
	await _hud_shot("start", ctx)

	ctx = _fresh()                                              # a few steps down a corridor, mid-glide
	var c := _hud_corridor(ctx, 3)
	if not c.is_empty():
		var step: Vector2i = c[2]
		gv.start(ctx["world"])
		view.logic.angle = c[1] * 45.0
		view.logic.cam = []
		view.refresh(0.0)
		view.controller.press(&"walk_forward")
		view.controller.update(0.05, [])
		view.controller.update(0.05, [])
		ctx["edits"].append(["move", step.x, step.y])
		view.refresh(0.0)
		await _hud_shot("mid_walk", ctx, null, false)

	# A fight: a stunned goblin two tiles ahead (Python test_render `_combat`).
	ctx = _fresh()
	c = _hud_corridor(ctx, 3)
	if not c.is_empty():
		var spot: Vector2i = c[0]
		var s: Vector2i = c[2]
		_do(ctx, ["fight", "goblin", spot.x + 2 * s.x, spot.y + 2 * s.y])
		await _hud_shot("combat_start", ctx, c[1] * 45.0)
		_do(ctx, ["move", s.x, s.y])
		await _hud_shot("combat_mid", ctx, c[1] * 45.0)
		_do(ctx, ["wait"])
		_do(ctx, ["move", s.x, s.y])
		await _hud_shot("combat_attacked", ctx, c[1] * 45.0)

	# The same fight against the floor's Headliner.
	ctx = _fresh()
	c = _hud_corridor(ctx, 3)
	if not c.is_empty():
		var spot: Vector2i = c[0]
		var s: Vector2i = c[2]
		_do(ctx, ["fight", "boss", spot.x + 2 * s.x, spot.y + 2 * s.y])
		await _hud_shot("combat_boss", ctx, c[1] * 45.0)

	# The tracker with none, one and many fighters (Python test_tracker_draws_with_none_one_and_many_fighters).
	for n in [0, 1, 12]:
		ctx = _fresh()
		_do(ctx, ["encounter", n])
		await _hud_shot("tracker_%d" % n, ctx)

	# A step that would provoke: a goblin right behind you (Python test_a_step_that_would_provoke...).
	ctx = _fresh()
	_do(ctx, ["quiet"])
	var b := _behind_spot(ctx["world"])
	if not b.is_empty():
		var spot: Vector2i = b[0]
		var s: Vector2i = b[2]
		_do(ctx, ["place", spot.x, spot.y])
		_do(ctx, ["player_hp", 999])
		_do(ctx, ["fight", "goblin", spot.x - s.x, spot.y - s.y, "live"])
		await _hud_shot("provoke_behind", ctx, b[1] * 45.0)
		# ... and the log after taking the step the warning named
		_do(ctx, ["move", s.x, s.y])
		await _hud_shot("provoke_taken", ctx, b[1] * 45.0)

	# A monster beside you that you cannot see: a red chevron, no fight.
	ctx = _fresh()
	_do(ctx, ["quiet"])
	b = _behind_spot(ctx["world"])
	if not b.is_empty():
		var spot: Vector2i = b[0]
		var d: int = b[1]
		_do(ctx, ["place", spot.x, spot.y])
		var right: Vector2i = FpLogic.DIRS8[(d + 2) % 8]
		var w: World = ctx["world"]
		if _empty(w, spot.x + right.x, spot.y + right.y):
			_do(ctx, ["mon", "goblin", "", spot.x + right.x, spot.y + right.y, 1.0])
			await _hud_shot("chevron_side", ctx, d * 45.0)

	# Toasts: an achievement, then one over a fight (the banner and the toast stack).
	ctx = _fresh()
	_do(ctx, ["toast", "Achievement: Test", "gold", "Bronze box. Open it in a safe room."])
	await _hud_shot("toast", ctx)
	ctx = _fresh()
	c = _hud_corridor(ctx, 3)
	if not c.is_empty():
		var spot: Vector2i = c[0]
		var s: Vector2i = c[2]
		_do(ctx, ["toast", "Achievement: Test", "gold", "Bronze box. Open it in a safe room."])
		_do(ctx, ["fight", "goblin", spot.x + 2 * s.x, spot.y + 2 * s.y])
		await _hud_shot("toast_combat", ctx, c[1] * 45.0)

	# The Analyst's Scout Report with monsters in sight.
	ctx = _fresh()
	c = _hud_corridor(ctx, 5)
	if not c.is_empty():
		var spot: Vector2i = c[0]
		var s: Vector2i = c[2]
		_do(ctx, ["class", "human", "analyst"])
		_do(ctx, ["use_skill"])
		_do(ctx, ["mon", "goblin", "", spot.x + 2 * s.x, spot.y + 2 * s.y, 1.0])
		_do(ctx, ["mon", "vacbot", "", spot.x + 3 * s.x, spot.y + 3 * s.y, 0.5])
		_do(ctx, ["mon", "brute", "", spot.x + 4 * s.x, spot.y + 4 * s.y, 1.0])
		await _hud_shot("scout", ctx, c[1] * 45.0)

	# A well-stocked panel: class, deal (none), boxes, points to spend.
	ctx = _fresh()
	_do(ctx, ["class", "human", "brawler"])
	_do(ctx, ["box", "bronze"])
	_do(ctx, ["box", "bronze"])
	_do(ctx, ["box", "gold"])
	_do(ctx, ["gold", 1234])
	await _hud_shot("panel_full", ctx)

	# The safe room and the stairwell hints in the panel.
	ctx = _fresh()
	var wr: World = ctx["world"]
	_do(ctx, ["quiet"])
	var sc := wr.floor.safe_room.centre()
	_do(ctx, ["place", sc.x, sc.y])
	await _hud_shot("safe_room", ctx)
	ctx = _fresh()
	wr = ctx["world"]
	_do(ctx, ["quiet"])
	var st: Vector2i = wr.floor.stairs[0]
	_do(ctx, ["place", st.x, st.y])
	await _hud_shot("stairwell", ctx)

	# The end screens.
	ctx = _fresh()
	_do(ctx, ["state", "dead", "Eaten by a Knockoff Goblin on floor 1."])
	await _hud_shot("death", ctx)
	ctx = _fresh()
	_do(ctx, ["state", "victory", null])
	await _hud_shot("victory", ctx)

	hud.queue_free()
	await process_frame


# --- Timings and the whole window ----------------------------------------------------

## Mesh build time per floor (floors 1-6 of the shot seed) and frames a second while turning
## on the spot and gliding (the frame is drawn every time, as in play).
func _timings() -> Dictionary:
	var ctx := _fresh()
	var w: World = ctx["world"]
	var build: Array = []
	var textures: Array = []
	view.materials = FpMaterials.new()       # time the textures too, not the cached ones
	for d in range(1, 7):
		if d > 1:
			w.new_floor(d)
		gv.start(w)
		build.append(snappedf(view.build_ms, 0.01))
		textures.append(snappedf(view.materials_ms, 0.01))
	var frames := 0
	var vp_rid := view.viewport.get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(vp_rid, true)
	var cpu_ms := 0.0
	var gpu_ms := 0.0
	var t0 := Time.get_ticks_usec()
	while frames < fps_frames:
		view.logic.look(3.0)
		view.controller.update(1.0 / 60.0, [])
		view.refresh(1.0 / 60.0)
		await RenderingServer.frame_post_draw
		cpu_ms += RenderingServer.viewport_get_measured_render_time_cpu(vp_rid)
		gpu_ms += RenderingServer.viewport_get_measured_render_time_gpu(vp_rid)
		frames += 1
	var secs := (Time.get_ticks_usec() - t0) / 1e6
	print("screenshots: 3D viewport render time per frame: cpu %.2f ms, gpu %.2f ms" % [
			cpu_ms / frames, gpu_ms / frames])
	return {"build_ms": build, "textures_ms": textures, "frames": frames, "seconds": secs, "fps": frames / secs,
			"ms_per_frame": secs * 1000.0 / frames,
			"renderer": RenderingServer.get_current_rendering_driver_name(),
			"adapter": RenderingServer.get_video_adapter_name()}


## The P4 main scene as a player sees it (placeholder panel and log included).
func _window_shot() -> void:
	var main: Main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	var game: GameView = main.get_node("GameView")
	main.options = {"save-dir": OS.get_cache_dir().path_join("crawl_shots_scratch"),   # never the player's own settings.json
			"runs-dir": OS.get_cache_dir().path_join("crawl_shots_scratch/runs")}
	root.add_child(main)
	game.set_plain(true)                     # after add_child: Main._ready reloads the settings
	main.app.seed_value = seed_value
	for _i in 4:                             # Enter through the title and the creation screens
		main.app.handle_key(KeyEvents.key(KEY_ENTER))
	for _i in 4:
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join("window_start.png"))
	game.press(&"toggle_view")               # Tab: the map
	for _i in 4:
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join("window_tab_top.png"))
	game.press(&"toggle_view")               # Tab again: back to first-person
	for _i in 4:
		await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png(out_dir.path_join("window_tab_back.png"))
	main.queue_free()
	await process_frame


## Every menu and screen of the pygame sweep, in both views (tools/menu_sweep.gd), saved as the whole
## 1280 x 768 window under pygame's names.
func _menu_shots() -> void:
	var sweep := MenuSweep.new(root, _menu_shot)
	await sweep.run_all()
	_save_json("menu_shots.json", {"names": sweep.names})
	print("screenshots: %d menu screens in both views" % sweep.names.size())


func _menu_shot(shot_name: String, app: AppState, h: Hud, g: GameView) -> void:
	for v in ["top", "fp"]:
		if app.scene == AppState.GAME:
			g.set_view(v)
		h.sync()
		for _i in 4:
			await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png(out_dir.path_join("%s_%s.png" % [shot_name, v]))


func _save_json(file_name: String, data: Variant) -> void:
	var f := FileAccess.open(out_dir.path_join(file_name), FileAccess.WRITE)
	f.store_string(JSON.stringify(data, "  ", false))
	f.close()


static func _parse(args: PackedStringArray) -> Dictionary:
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

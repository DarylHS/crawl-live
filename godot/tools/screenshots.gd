extends SceneTree
## Renders scripted first-person views to PNG files (port plan Appendix B: the screenshot sweep).
##
##   xvfb-run -a godot --path godot --rendering-driver opengl3 -s res://tools/screenshots.gd \
##       -- --screenshots=/some/dir [--seed 1] [--pet cat|dog|budgie|mouse|none] [--fps-frames 300]
##
## Needs a display (Xvfb is fine; software GL works). For each shot it writes <name>.png (the
## 320 x 200 frame scaled to 1024 x 640 with hard pixels, the size of Python's MAP_RECT) and a
## record in shots.json: seed, pet, floors made, player tile, look angle, the exact camera
## [x, y, a], and any changes made to the world (monsters cleared or spawned, a key, combat).
## scripts/fp_compare_shots.py replays shots.json in the pygame raycaster for a side by side.
## It also writes window_start.png (the whole P4 main scene) and timings.json (mesh build time per
## floor and frames a second for a scripted walk and turn).

const OUT_W := 1024
const OUT_H := 640

var out_dir := ""
var seed_value := 1
var pet: Variant = null
var fps_frames := 300
var view: FpView = null
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
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var scene: PackedScene = load("res://scenes/fp_view.tscn")
	view = scene.instantiate()
	view.input_enabled = false
	root.add_child(view)
	view.set_anchors_preset(Control.PRESET_TOP_LEFT)
	view.size = Vector2(OUT_W, OUT_H)

	await _shot("start_room", _fresh())
	await _shot_corridor()
	await _shot_safe_room()
	await _shot_stairs(false)
	await _shot_stairs(true)
	for d in range(1, 7):
		await _shot("tint_floor_%d" % d, _fresh(d))
	await _shot_fog()
	await _shot_combat()
	await _shot_mid_glide()

	var timings := await _timings()
	view.queue_free()
	await process_frame
	await _window_shot()

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
	view.start(w)
	if angle != null:
		view.logic.angle = angle
	view.controller.sync_combat()
	view.logic.cam = []
	view.refresh(0.0)
	if not cam.is_empty():
		view.logic.cam = cam
		view.refresh(0.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := view.capture()
	img.resize(OUT_W, OUT_H, Image.INTERPOLATE_NEAREST)
	img.save_png(out_dir.path_join(shot_name + ".png"))
	records.append({"name": shot_name, "floors": Array(ctx["floors"]), "edits": ctx["edits"],
			"player": [w.player.x, w.player.y], "angle": view.logic.angle,
			"cam": view.logic.cam.duplicate(), "grid": view.logic.grid,
			"combat": w.combat != null, "stairs_locked": w.stairs_locked})


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
func _shot_corridor() -> void:
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
					await _shot("corridor", ctx, d * 90.0)
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


## Python test_render `_combat`: a stunned goblin two tiles down a straight corridor, a fight on.
## The look angle starts 30 degrees off the grid; the lock rounds it and the camera settles.
func _shot_combat() -> void:
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
	view.start(w)
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
	await _shot_current("combat_locked", ctx)


## One step down a corridor, a tenth of a second into the glide (0.4 of a tile).
func _shot_mid_glide() -> void:
	var ctx := _fresh()
	var w: World = ctx["world"]
	_quiet(ctx)
	var found: Variant = _corridor(w, 3, [0, 2, 4, 6])
	var spot: Vector2i = found[0]
	var d: int = found[1]
	_place(ctx, spot.x, spot.y)
	view.start(w)
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
	var w: World = ctx["world"]
	view.refresh(0.0)
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := view.capture()
	img.resize(OUT_W, OUT_H, Image.INTERPOLATE_NEAREST)
	img.save_png(out_dir.path_join(shot_name + ".png"))
	records.append({"name": shot_name, "floors": Array(ctx["floors"]), "edits": ctx["edits"],
			"player": [w.player.x, w.player.y], "angle": view.logic.angle,
			"cam": view.logic.cam.duplicate(), "grid": view.logic.grid,
			"combat": w.combat != null, "stairs_locked": w.stairs_locked})


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
		view.start(w)
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
	var main: Control = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.set("_seed", seed_value)
	root.add_child(main)
	for _i in 4:
		await RenderingServer.frame_post_draw
	var img := root.get_texture().get_image()
	img.save_png(out_dir.path_join("window_start.png"))
	main.queue_free()
	await process_frame


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

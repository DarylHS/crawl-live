extends SceneTree
## P8 effect screenshots: frame sequences and contact sheets of every effect, taken from the real Main
## scene (title skipped) under a display (Xvfb is fine).
##
##   xvfb-run -a godot --path godot --rendering-driver opengl3 -s res://tools/fx_shots.gd -- --out=DIR [--seed 1] [--only name,name]
##
## Each effect writes <effect>_NN.png frames (the whole 1280 x 768 window, one every 0.05 s of game time) and a
## sheet_<effect>.png contact sheet. `Engine.time_scale` is turned down to 0.25 so a slow software-GL frame
## still covers only a few hundredths of a second of effect time. Events come from the real rules where a
## fight allows it (attacks, steps) and are emitted on the World's EventBus for the rare ones (a crit, a boss
## phase, a bomb), which is exactly how the rules deliver them. scripts/fx_gif.py turns the frames into GIFs.
## It also measures the frame rate with every effect on (perf.json).

const STEP := 0.05
const SCALE := 0.25

var out_dir := ""
var seed_value := 1
var only: PackedStringArray = PackedStringArray()
var main: Main = null
var app: AppState = null
var gv: GameView = null
var fp: FpView = null
var world: World = null
var dir_idx := 0                 ## direction (0-3) the stage faces
var report: Dictionary = {}
var perf_mode := "on"            ## the effects mode for the whole run (--mode on|reduced|off), for the frame rate test


func _initialize() -> void:
	var args := Main._parse_args(OS.get_cmdline_user_args())
	out_dir = args.get("out", "")
	if out_dir == "":
		push_error("fx_shots.gd: pass -- --out=<dir>")
		quit(2)
		return
	seed_value = int(args.get("seed", "1"))
	perf_mode = String(args.get("mode", "on"))
	if args.has("only"):
		only = String(args["only"]).split(",")
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _wants(effect: String) -> bool:
	return only.is_empty() or only.has(effect)


func _run() -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.summary_on_headless = false
	var tmp := OS.get_cache_dir().path_join("crawl_fx_shots")
	main.options = {"save-dir": tmp, "runs-dir": tmp.path_join("runs")}
	root.add_child(main)
	await process_frame
	app = main.app
	gv = main.game_view
	fp = gv.fp_view
	app.settings["effects"] = perf_mode
	app.pet_name = ""
	_stage(2)
	await _settle()
	Engine.time_scale = SCALE

	if _wants("weapons"):
		await _weapons()
	if _wants("swing"):
		await _swings()
	if _wants("hit"):
		await _hit_and_numbers()
	if _wants("crit"):
		await _crit_shake()
	if _wants("boss"):
		await _boss_phase()
	if _wants("bomb"):
		await _bomb()
	if _wants("heal"):
		await _heal()
	if _wants("slide"):
		await _slide()
	if _wants("torch"):
		await _torches()
	if _wants("box"):
		await _box_reveal()
	if _wants("modes"):
		await _modes()
	Engine.time_scale = 1.0
	if _wants("perf"):
		await _perf()
	var f := FileAccess.open(out_dir.path_join("report.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(report, "  "))
	f.close()
	print("fx_shots: done in ", out_dir)
	quit(0)


# --- Staging ----------------------------------------------------------------------------------

## A straight run of open tiles with `n` tiles ahead, no monsters, you at one end facing along it, and a goblin
## (with plenty of HP) `gap` tiles ahead.
func _stage(gap: int, monster: String = "goblin") -> Monster:
	app.seed_value = seed_value                  # a fresh run each time: no fight left over from the last effect
	app.start_run(null)
	world = app.world
	world.monsters.clear()
	var f := world.floor
	var found := false
	var spot := Vector2i.ZERO
	for y in f.height:
		for x in f.width:
			if found or f.is_safe(x, y):
				continue
			for d in 4:
				var s: Vector2i = FpLogic.DIRS[d]
				var ok := true
				for k in range(0, 6):
					if not f.walkable(x + s.x * k, y + s.y * k) or f.is_safe(x + s.x * k, y + s.y * k) \
							or f.furniture.has(Vector2i(x + s.x * k, y + s.y * k)):
						ok = false
						break
				if ok:
					found = true
					spot = Vector2i(x, y)
					dir_idx = d
					break
	assert(found)
	world.player.x = spot.x
	world.player.y = spot.y
	world.update_fov()
	var s2: Vector2i = FpLogic.DIRS[dir_idx]
	var m := Entities.spawn_monster(monster, spot.x + s2.x * gap, spot.y + s2.y * gap)
	m.hp = 999
	m.max_hp = 999
	world.monsters.append(m)
	world.update_fov()
	fp.logic.angle = dir_idx * 90.0
	fp.logic.cam = []
	fp.refresh(0.0)
	return m


func _settle(frames: int = 6) -> void:
	for _i in frames:
		await RenderingServer.frame_post_draw


func _grab() -> Image:
	return root.get_texture().get_image()


func _press(action: StringName) -> void:
	gv.fx_director.on_key()
	app.press(action)


## Run `trigger`, then save a frame every STEP seconds of game time for `dur` seconds as <name>_NN.png and a sheet.
func _record(effect: String, dur: float, trigger: Callable, cols: int = 6) -> void:
	await _settle(3)
	gv.fx_director.state.finish()
	gv.fx_director.state.numbers.clear()
	await _settle(3)                       # let the cleared state reach the screen before the "before" frame
	var frames: Array[Image] = []
	frames.append(_grab())                 # the frame before the trigger
	trigger.call()
	var t := 0.0
	var next := 0.0
	while t <= dur:
		await RenderingServer.frame_post_draw
		t += main.get_process_delta_time()
		if t >= next:
			frames.append(_grab())
			next += STEP
	var luma: Array = []
	for i in frames.size():
		frames[i].save_png(out_dir.path_join("%s_%02d.png" % [effect, i]))
		luma.append(snappedf(_mean_luma(frames[i].get_region(Rect2i(0, 60, 1024, 380))), 0.001))
	_sheet(effect, frames, cols)
	report[effect] = {"frames": frames.size(), "game_seconds": snappedf(t, 0.01), "mean_luma_per_frame": luma}


## Average brightness (0 to 1) of an image, sampled on a grid.
func _mean_luma(im: Image) -> float:
	var total := 0.0
	var n := 0
	for y in range(0, im.get_height(), 6):
		for x in range(0, im.get_width(), 6):
			var c := im.get_pixel(x, y)
			total += 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
			n += 1
	return total / maxf(1.0, n)


## A contact sheet: every `skip`th frame, scaled down, in a grid.
func _sheet(effect: String, frames: Array[Image], cols: int, crop: Rect2i = Rect2i(0, 0, 1024, 640)) -> void:
	var count := mini(frames.size(), cols * 4)
	var stride := maxi(1, int(ceil(frames.size() / float(count))))
	var picked: Array[Image] = []
	for i in range(0, frames.size(), stride):
		picked.append(frames[i])
	var cw := 320
	var ch := 200
	var rows := int(ceil(picked.size() / float(cols)))
	var sheet := Image.create_empty(cols * cw, rows * ch, false, Image.FORMAT_RGBA8)
	sheet.fill(Color.BLACK)
	for i in picked.size():
		var im := picked[i].get_region(crop)
		im.resize(cw, ch, Image.INTERPOLATE_NEAREST)
		sheet.blit_rect(im, Rect2i(0, 0, cw, ch), Vector2i((i % cols) * cw, (i / cols) * ch))
	sheet.save_png(out_dir.path_join("sheet_%s.png" % effect))


# --- Effects ----------------------------------------------------------------------------------

func _weapons() -> void:
	_stage(4)
	var frames: Array[Image] = []
	var keys: Array = [null, "pan", "cleaver", "katana", "extinguisher", "sledge"]
	for k in keys:
		world.equipment["weapon"] = k
		fp.refresh(0.0)
		await _settle(4)
		var im := _grab()
		im.save_png(out_dir.path_join("weapon_%s.png" % ("unarmed" if k == null else k)))
		frames.append(im)
	_sheet("weapons", frames, 3)
	world.equipment["weapon"] = null


func _swings() -> void:
	for pair in [["unarmed", null], ["blade", "katana"], ["blunt", "sledge"]]:
		_stage(1)
		world.equipment["weapon"] = pair[1]
		fp.refresh(0.0)
		await _record("swing_" + pair[0], 0.55, _attack_once, 6)


func _hit_and_numbers() -> void:
	var m := _stage(1)
	world.equipment["weapon"] = "cleaver"
	fp.refresh(0.0)
	_target = m
	await _record("hit_flash", 1.2, _attack_until_hit, 6)
	m.hp = 999
	await _record("damage_taken", 1.0, _emit_damage, 6)


var _target: Monster = null


## A real attack, repeated until one lands, so the flash and number show.
func _attack_until_hit() -> void:
	for _i in 8:
		var before := _target.hp
		_press(&"walk_forward")
		if _target.hp < before:
			break


func _attack_once() -> void:
	_press(&"walk_forward")


func _emit_damage() -> void:
	world.events.emit("damage_taken", {"source": "goblin", "damage": 4, "hp": 20, "ranged": false})


func _emit_crit() -> void:
	world.events.emit("player_attack", {"target": "goblin", "chance": 0.8, "hit": true, "crit": true,
			"small": true, "boss": false, "roll": 20})
	world.events.emit("nat20", {"foe": "the goblin", "Foe": "The goblin"})
	world.events.emit("player_hit", {"target": "goblin", "damage": 12, "crit": true})


func _emit_phase() -> void:
	world.events.emit("boss_phase", {"boss": "Executive Producer Glorm", "phase": 2})


func _emit_bomb() -> void:
	world.events.emit("bomb", {"item": "popper", "kills": 1})


func _emit_heal() -> void:
	world.events.emit("item_use", {"item": "tonic", "healed": 8})


func _emit_everything() -> void:
	_emit_crit()
	_emit_bomb()


func _step_monster_back() -> void:
	var s: Vector2i = FpLogic.DIRS[dir_idx]
	_target.x -= s.x
	_target.y -= s.y
	world.update_fov()


func _noop() -> void:
	pass


func _crit_shake() -> void:
	_stage(2)
	world.equipment["weapon"] = "katana"
	await _record("crit_shake", 1.0, _emit_crit, 6)


func _boss_phase() -> void:
	_stage(3, "goblin")
	await _record("boss_phase", 1.8, _emit_phase, 6)


func _bomb() -> void:
	_stage(3)
	await _record("bomb", 1.4, _emit_bomb, 6)


func _heal() -> void:
	_stage(3)
	await _record("heal", 1.0, _emit_heal, 6)


## A monster steps one tile: the sprite slides instead of jumping.
func _slide() -> void:
	_target = _stage(4)
	await _record("slide", 0.4, _step_monster_back, 6)


## Put you three tiles from a wall torch, facing it. Returns false when no torch has room.
func _face_torch() -> bool:
	var sites := WallTorches.sites_for(world.floor)
	var f := world.floor
	for s: Dictionary in sites:
		var tile: Vector2i = s["tile"]
		var d: Vector2i = s["dir"]
		var back := tile - d * 3
		if f.walkable(back.x, back.y) and f.walkable(tile.x - d.x, tile.y - d.y) and f.walkable(tile.x - d.x * 2, tile.y - d.y * 2):
			world.monsters.clear()
			world.player.x = back.x
			world.player.y = back.y
			world.update_fov()
			fp.logic.angle = rad_to_deg(atan2(d.x, -d.y))        # 0 is north, 90 east
			fp.logic.cam = []
			fp.refresh(0.0)
			return true
	return false


## The torch light flickering and the wall torches, standing near one.
func _torches() -> void:
	_stage(2)
	_face_torch()
	await _record("torch", 2.0, _noop, 6)


func _box_reveal() -> void:
	_stage(3)
	var w := world
	w.last_reveal = ["gold", "katana"]
	w.last_reason = "Winning the lottery of survival."
	w.box_log.append({"tier": "gold", "item": "katana", "value": 60, "ev": 40.0, "rerolled": false, "turn": 0, "reason": ""})
	if not w.inventory.has("katana"):
		w.inventory.append("katana")
	app.overlay = "reveal"
	await _record("box_reveal", 1.6, _noop, 6)
	app.overlay = ""


## The same hit under each effects mode.
func _modes() -> void:
	for mode in FxSettings.MODES:
		app.settings["effects"] = mode
		_stage(2)
		await _record("mode_" + mode, 0.5, _emit_everything, 6)
	app.settings["effects"] = perf_mode


## Frames a second with everything running: a fight's numbers, bursts and bombs, then wall torches.
func _perf() -> void:
	report["perf"] = {"mode": perf_mode, "renderer": RenderingServer.get_current_rendering_driver_name(),
			"adapter": RenderingServer.get_video_adapter_name(), "window": root.size}
	var m := _stage(2)
	world.equipment["weapon"] = "sledge"
	await _perf_run("fight", 240)
	m.hp = 999
	_stage(2)
	_face_torch()
	await _perf_run("torches", 240)
	print("fx_shots: perf ", report["perf"])


func _perf_run(label: String, count: int) -> void:
	await _settle(10)
	var frames := 0
	var worst := 0.0
	var t_all := 0.0
	var slow := 0
	while frames < count:
		if frames % 20 == 0:
			world.events.emit("player_attack", {"target": "goblin", "chance": 0.8, "hit": true, "crit": true,
					"small": true, "boss": false, "roll": 20})
			world.events.emit("player_hit", {"target": "goblin", "damage": 9, "crit": true})
			if frames % 60 == 0:
				world.events.emit("bomb", {"item": "popper", "kills": 0})
		await process_frame
		var dt := main.get_process_delta_time()
		t_all += dt
		worst = maxf(worst, dt)
		slow += int(dt > 1.0 / 30.0)
		frames += 1
	report["perf"][label] = {"frames": frames, "avg_fps": snappedf(frames / t_all, 0.1),
			"worst_frame_ms": snappedf(worst * 1000.0, 0.1), "frames_under_30fps": slow,
			"torches_showing": fp.torches.shown}

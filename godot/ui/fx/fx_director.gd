class_name FxDirector
extends Node
## Listens to the World's EventBus and turns events into effects (P8 "juice"): sounds, a white flash on a
## struck sprite, floating damage numbers, screen shake, particle bursts and the weapon swing.
##
## What fires for which event is FxPlan's table; what each running effect looks like is FxState; the
## views (FpView, Billboards, FxCanvas, ViewModel) draw FxState. This node is the glue: it subscribes to
## the bus once per world, finds which creature an event is about (FxTargets), projects it to the screen,
## advances FxState every frame and plays due sounds.
##
## It only reads the World, and the rules do not know it exists: the handlers return nothing, change no
## game state, draw nothing from the game's RNG and never delay a turn. The Effects setting
## (settings["effects"]: on, reduced, off) and the sound setting (volume, muted) are read every frame, so
## F3 and F4 take effect at once. A key press calls `on_key()` first, which finishes the moving effects
## (see FxState), so input never waits on an animation.
##
## The subscription is a lambda holding only a WeakRef to this node: the World keeps the lambda alive, and
## a freed director is just ignored, so there is no reference cycle and no call into a freed node.

const FIRED_KEEP := 64

var state := FxState.new()
var sfx := SfxPlayer.new()
var app: AppState = null
var fp_view: FpView = null
var world: World = null
var fired: Array[Dictionary] = []          ## the last effects applied, newest last (tests read it)
var _snapshot: Array[Dictionary] = []      ## monsters as of the last frame (the dead are gone from the live list)
var _last_target: Variant = null           ## the monster your last attack was aimed at: {id, key, tile}
var force_visible: bool = false            ## treat the 3D view as showing (headless tests and the parity runs, with no view)
var _volume: int = -1
var _muted: bool = false


## A director with no scene, listening to `w` and running every effect through FxState and the sound mixer
## with no view to draw on: what the parity runs (CRAWL_FX=1 in tools/trace_run.gd and tools/chaos.gd) and
## the tests use to prove the effects never touch the rules. Free it (`free()`) when the run is over.
static func attach_headless(w: World) -> FxDirector:
	var d := FxDirector.new()
	d.force_visible = true
	d.attach_world(w)
	return d


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and sfx != null and not sfx.is_inside_tree() and not sfx.is_queued_for_deletion():
		sfx.free()                                # never entered the tree (a headless director)


func _ready() -> void:
	sfx.process_mode = Node.PROCESS_MODE_ALWAYS     # menu clicks play on the title too, where the game view is switched off
	add_child(sfx)


## Attach to the app (settings and world changes) and the first-person view that shows the effects.
func bind(new_app: AppState, view: FpView) -> void:
	app = new_app
	fp_view = view
	if fp_view != null:
		fp_view.fx = state
	app.world_started.connect(attach_world)
	if app.world != null:
		attach_world(app.world)
	_sync_settings()


## Start listening to a world (a new run or a loaded one).
func attach_world(w: World) -> void:
	world = w
	_snapshot = []
	_last_target = null
	state.forget_actors()
	var me: WeakRef = weakref(self)           # a lambda keeps what it captures alive: the bus holds only this weak reference
	var forward: Callable = func(event_name: String, data: Dictionary) -> void:
		var d := me.get_ref() as FxDirector
		if d != null:
			d.handle(event_name, data)
	for e in FxPlan.events():
		w.events.subscribe(e, forward)


## A key is about to be handled: finish the moving effects (shake, flashes, slides, swing, bursts).
func on_key() -> void:
	state.on_key()
	if fp_view != null:
		fp_view.particles.clear()


## Play the menu "select" sound (a menu opened, closed or moved).
func ui_select() -> void:
	sfx.play("select")


func _process(delta: float) -> void:
	if app == null:
		return
	_sync_settings()
	for sound_name in state.advance(delta):
		sfx.play(sound_name)
	if world != null:
		_snapshot = FxTargets.snapshot(world)


func _sync_settings() -> void:
	var mode := String(app.settings.get("effects", "on"))
	if mode != state.mode:
		state.set_mode(mode)
		if mode == "off" and fp_view != null:
			fp_view.particles.clear()
	var vol := int(app.settings.get("volume", 70))
	var muted := bool(app.settings.get("muted", false))
	if vol != _volume or muted != _muted:
		_volume = vol
		_muted = muted
		sfx.configure(vol, muted)


## One event from the world: plan its effects and apply them.
func handle(event: String, data: Dictionary) -> void:
	if world == null:
		return
	var tgt: Variant = _target_for(event, data)
	var ctx := {"mode": state.mode, "max_hp": world.player.max_hp}
	for e in FxPlan.plan(event, data, ctx):
		_apply(e, tgt)


## Which creature an event is about, or null: the nearest monster of the event's key (see FxTargets).
func _target_for(event: String, data: Dictionary) -> Variant:
	var p := Vector2i(world.player.x, world.player.y)
	match event:
		"player_attack":
			_last_target = FxTargets.nearest(FxTargets.snapshot(world), p, String(data.get("target", "")))
			return _last_target
		"player_hit", "nat20":
			return _last_target
		"kill":
			var key := String(data.get("monster", ""))
			var by := String(data.get("by", ""))
			if _last_target != null and _last_target["key"] == key and (by == "melee" or by == "skill"):
				return _last_target
			var from := p
			if by == "pet" and world.active_pet != null:
				from = Vector2i(world.active_pet.x, world.active_pet.y)
			return FxTargets.nearest(_snapshot, from, key)
		"bomb":
			var seen: Array = []
			for a in _snapshot:
				if world.visible.has(a["tile"]):
					seen.append(a)
			return FxTargets.nearest(seen, p)
		"pet_hit":
			if world.active_pet != null:
				return FxTargets.nearest(FxTargets.snapshot(world), Vector2i(world.active_pet.x, world.active_pet.y))
	return null


func _apply(e: Dictionary, tgt: Variant) -> void:
	fired.append(e)
	if fired.size() > FIRED_KEEP:
		fired.remove_at(0)
	var kind: String = e["k"]
	if kind == "sound":
		if float(e["delay"]) > 0.0:
			state.delay_sound(e["name"], float(e["delay"]))
		else:
			sfx.play(e["name"])
		return
	if not _visible():
		return                                   # the map view shows none of these (sounds above still play)
	match kind:
		"flash":
			if tgt != null:
				state.flash(tgt["id"], float(e["strength"]), float(e["dur"]))
		"number":
			state.add_number(e["text"], e["tone"], _number_pos(e["at"], tgt), float(e["dur"]))
		"shake":
			state.kick(float(e["amp"]), float(e["dur"]))
		"burst":
			_burst(e, tgt)
		"swing":
			state.start_swing(world.weapon_style())


func _visible() -> bool:
	return force_visible or fp_view != null and fp_view.active and app != null and app.view == "fp" and app.scene == AppState.GAME


func _burst(e: Dictionary, tgt: Variant) -> void:
	if fp_view == null:
		return
	var pos := Vector3.ZERO
	match String(e["at"]):
		"player":
			var cam := fp_view.logic.cam
			if cam.is_empty():
				return
			pos = Vector3(cam[0] + cos(cam[2]) * 0.45, 0.3, cam[1] + sin(cam[2]) * 0.45)
		_:
			if tgt == null:
				return
			var tile: Vector2i = tgt["tile"]
			pos = Vector3(tile.x + 0.5, 0.3, tile.y + 0.5)
	fp_view.particles.burst(e["kind"], pos, int(e["count"]))
	if e["kind"] == "bomb":
		fp_view.bomb_light(pos)


## Where a floating number starts, in the view's pixels: over the struck monster's head, low and centred
## for your own damage and healing, or near the middle for banners. A monster behind the camera falls back
## to the middle.
func _number_pos(at: String, tgt: Variant) -> Vector2:
	if fp_view == null:
		return Vector2(512.0, 300.0)
	var sz := fp_view.size if fp_view.size.x > 0.0 else Vector2(1024, 640)
	match at:
		"player":
			return Vector2(sz.x * 0.5, sz.y * 0.74)
		"screen":
			return Vector2(sz.x * 0.5, sz.y * 0.34)
	if tgt != null and fp_view.rig.camera != null:
		var tile: Vector2i = tgt["tile"]
		var head := Vector3(tile.x + 0.5, FloorMeshBuilder.WALL_H * 0.55, tile.y + 0.5)
		if not fp_view.rig.camera.is_position_behind(head):
			var to_view := sz / Vector2(fp_view.viewport.size)
			var sp := fp_view.rig.camera.unproject_position(head) * to_view
			return Vector2(clampf(sp.x, 60.0, sz.x - 60.0), clampf(sp.y, 90.0, sz.y * 0.62))
	return Vector2(sz.x * 0.5, sz.y * 0.4)

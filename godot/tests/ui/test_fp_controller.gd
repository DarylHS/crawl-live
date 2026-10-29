extends TestCase
## First-person input in play: the first-person tests of tests/test_render.py (held walking,
## free look, tapped turns, bumps, slow frames, menus, the combat grid lock), run on FpController
## with action names where Python passed pygame keys. Headless.

const FW := &"walk_forward"
const BACK := &"walk_back"
const RIGHT := &"strafe_right"
const TL := &"turn_left"
const TR := &"turn_right"


## Python test_render `_start`: seed 1, the first companion, the default hero.
func _start() -> FpController:
	var hero := {"name": "Crawler", "gender": Content.table("genders").keys()[0],
			"backstory": Content.table("backstories").keys()[0]}
	var c := FpController.new()
	c.start(World.new(1, [Content.table("pets").keys()[0], ""], hero))
	return c


func _empty(w: World, x: int, y: int) -> bool:
	return w.floor.walkable(x, y) and w.monster_at(x, y) == null and w.pet_at(x, y) == null


## Python `_corridor`: a tile and a direction (0-7) with exactly n empty tiles ahead, then solid.
func _corridor(w: World, n: int, dirs: Array = [0, 1, 2, 3, 4, 5, 6, 7]) -> Array:
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
	fail_test("no corridor")
	return [Vector2i.ZERO, 0]


## Python `_place`: stand there, look 10 degrees off the line, snap the camera.
func _place(c: FpController, spot: Vector2i, d: int) -> void:
	c.world.player.x = spot.x
	c.world.player.y = spot.y
	c.world.update_fov()
	c.view.angle = d * 45 + 10
	c.view.reset_camera()
	c.view.update_camera(c.world)


func _quiet(w: World) -> void:
	w.monsters.clear()
	w.pet.downed = true


func _record(w: World, event_name: String) -> Array:
	var seen: Array = []
	w.events.subscribe(event_name, func(_n: String, d: Dictionary) -> void: seen.append(d))
	return seen


func test_movement_follows_the_view() -> void:
	var c := _start()
	var w := c.world
	w.monsters.clear()
	var v := c.view
	var step := Vector2i.ZERO
	for _i in 8:                                   # face somewhere D can strafe to
		step = v.relative("right")
		if _empty(w, w.player.x + step.x, w.player.y + step.y):
			break
		c.press(TR)
	var turn := w.turn
	var at := Vector2i(w.player.x, w.player.y)
	assert_eq(turn, 0)                             # turning was free
	v.prepare_floor(w)                             # what drawing a frame does first
	v.update_camera(w)
	assert_false(v.animating(w))
	c.press(RIGHT)
	assert_eq(Vector2i(w.player.x, w.player.y), at + step)
	assert_eq(w.turn, turn + 1)
	c.update(0.05, [])                             # mid-glide: keep drawing
	assert_true(v.animating(w))
	v.update_camera(w, 1)
	assert_false(v.animating(w))
	var angle := v.angle
	c.press(TL)                                    # a tap turns 45 degrees
	assert_eq(v.angle, PyMath.fmod_py(angle - 45, 360))
	assert_eq(w.turn, turn + 1)


func test_numpad_moves_keep_their_compass_meaning() -> void:
	var c := _start()
	var w := c.world
	_quiet(w)
	var spot := Vector2i.ZERO
	for y in w.floor.height:
		for x in w.floor.width:
			if spot == Vector2i.ZERO and _empty(w, x, y) and _empty(w, x + 1, y):
				spot = Vector2i(x, y)
	w.player.x = spot.x
	w.player.y = spot.y
	c.view.angle = 0                               # looking north: the numpad 6 still goes east
	c.press(&"move_e")
	assert_eq(Vector2i(w.player.x, w.player.y), spot + Vector2i(1, 0))


func test_holding_w_walks_a_tile_per_turn_and_stops_at_a_wall() -> void:
	var c := _start()
	var w := c.world
	_quiet(w)
	var found := _corridor(w, 3)
	var spot: Vector2i = found[0]
	var d: int = found[1]
	_place(c, spot, d)
	var s: Vector2i = FpLogic.DIRS8[d]
	var turn := w.turn
	var frames := 0
	while w.turn < turn + 3:
		c.update(1.0 / 30, [FW])
		frames += 1
		assert_lt(frames, 60)
		if frames >= 60:
			return
	assert_between(frames / 30.0, 0.4, 1.0)        # about 4 tiles a second
	for _i in 60:                                  # keep holding into the wall
		c.update(1.0 / 30, [FW])
	assert_eq(w.turn, turn + 3)
	assert_eq(Vector2i(w.player.x, w.player.y), spot + s * 3)
	c.update(1.0 / 30, [])
	assert_eq(c.view.glide_left(w), 0.0)           # rests on the tile centre
	assert_eq(c.view.cam.slice(0, 2), [w.player.x + 0.5, w.player.y + 0.5])
	var back := w.turn                             # S walks back the way you came
	for _i in 12:
		c.update(1.0 / 30, [BACK])
	assert_gt(w.turn, back)
	assert_lt((w.player.x - spot.x) * s.x + (w.player.y - spot.y) * s.y, 3)


func test_holding_w_into_a_monster_attacks_once() -> void:
	var c := _start()
	var w := c.world
	_quiet(w)
	var found := _corridor(w, 3)
	var spot: Vector2i = found[0]
	var d: int = found[1]
	_place(c, spot, d)
	var s: Vector2i = FpLogic.DIRS8[d]
	var goblin := Entities.spawn_monster("goblin", spot.x + s.x, spot.y + s.y)
	goblin.hp = 999
	goblin.max_hp = 999
	w.monsters.append(goblin)
	var attacks := _record(w, "player_attack")
	for _i in 30:
		c.update(1.0 / 30, [FW])
	assert_eq(attacks.size(), 1)
	assert_eq(Vector2i(w.player.x, w.player.y), spot)
	assert_not_null(w.combat)
	assert_false(w.combat.has("action"))           # the bump started combat as your action


func test_holding_q_looks_around_for_free() -> void:
	var c := _start()
	var w := c.world
	var v := c.view
	var turn := w.turn
	var angle := v.angle
	for _i in 5:                                   # 0.25 s
		c.update(0.05, [TL])
	assert_ne(v.angle, angle)
	assert_eq(w.turn, turn)
	c.update(0.05, [])
	angle = v.angle
	c.press(TR)                                    # a tap lands on the next 45 degree line
	assert_eq(PyMath.fmod_py(v.angle, 45), 0.0)
	assert_between(PyMath.fmod_py(v.angle - angle, 360), 0.001, 45.0)
	assert_eq(w.turn, turn)
	c.blocked = true                               # held keys do nothing under a menu
	for _i in 10:
		c.update(0.05, [TL, FW])
	assert_eq(PyMath.fmod_py(v.angle, 45), 0.0)
	assert_eq(w.turn, turn)


func test_strafing_into_a_monster_attacks_once() -> void:
	var c := _start()
	var w := c.world
	_quiet(w)
	var found := _corridor(w, 3)
	var spot: Vector2i = found[0]
	var d: int = found[1]
	_place(c, spot, d)
	c.view.angle = PyMath.fmod_py(d * 45 - 90, 360)   # the corridor is on your right
	var r := c.view.relative("right")
	var goblin := Entities.spawn_monster("goblin", spot.x + r.x, spot.y + r.y)
	goblin.hp = 999
	goblin.max_hp = 999
	w.monsters.append(goblin)
	var attacks := _record(w, "player_attack")
	for _i in 60:                                  # hold D for 2 s: one bump, no more
		c.update(1.0 / 30, [RIGHT])
	assert_eq(attacks.size(), 1)
	assert_eq(Vector2i(w.player.x, w.player.y), spot)


func test_a_slow_frame_is_capped() -> void:
	var c := _start()
	var w := c.world
	var v := c.view
	var angle := v.angle
	c.update(5.0, [TL])                            # a 5 s hitch: still a tap, no spin
	assert_eq(v.angle, angle)
	assert_eq(c.held_for(TL), FpController.MAX_DT)
	assert_lt(FpController.MAX_DT, FpController.HOLD_DELAY)
	for _i in 5:
		c.update(5.0, [TL])
	var turned := PyMath.fmod_py(angle - v.angle, 360)
	assert_between(turned, 0.001, FpController.TURN_RATE * FpController.MAX_DT * 2 + 1e-6)
	w.player.x += 1                                # a glide moves a capped amount per frame
	c.update(5.0, [])
	assert_between(v.glide_left(w), 0.001, 0.999)


func test_camera_lands_on_the_tile_under_a_menu() -> void:
	var c := _start()
	var w := c.world
	w.monsters.clear()
	var v := c.view
	v.update_camera(w)
	var step := Vector2i.ZERO
	for _i in 8:
		step = v.relative("forward")
		if _empty(w, w.player.x + step.x, w.player.y + step.y):
			break
		v.tap_turn(1)
	c.press(FW)
	c.update(1.0 / 30, [])
	assert_between(v.glide_left(w), 0.001, 0.999)
	c.blocked = true                               # a menu opens mid-glide
	for _i in 30:
		c.update(1.0 / 30, [FW])
	assert_eq(v.glide_left(w), 0.0)
	w.state = "dead"
	c.blocked = false
	w.player.x -= step.x
	w.player.y -= step.y
	for _i in 30:
		c.update(1.0 / 30, [])
	assert_eq(v.glide_left(w), 0.0)


func test_after_walking_three_tiles() -> void:
	var c := _start()
	var w := c.world
	_quiet(w)
	var found := _corridor(w, 3)
	_place(c, found[0], found[1])
	for _i in 40:
		c.update(1.0 / 30, [FW])
	c.update(1.0 / 30, [])
	assert_eq(w.turn, 3)


## Python `_combat`: the player at the start of a straight 3-tile corridor, a sturdy stunned
## monster `gap` tiles ahead, a fight on, facing it.
func _combat(c: FpController, gap: int = 2) -> Array:
	var w := c.world
	_quiet(w)
	w.player.max_hp = 999
	w.player.hp = 999
	var found := _corridor(w, 3, [0, 2, 4, 6])
	var spot: Vector2i = found[0]
	var d: int = found[1]
	_place(c, spot, d)
	var s: Vector2i = FpLogic.DIRS8[d]
	var m := Entities.spawn_monster("goblin", spot.x + gap * s.x, spot.y + gap * s.y)
	m.hp = 999
	m.max_hp = 999
	w.monsters.append(m)
	w.update_fov()
	assert_true(w.join_combat(m))
	w.combat.round = 1
	m.stunned = 99
	c.view.angle = d * 45
	return [m, s]


func test_fp_combat_is_grid_locked() -> void:
	var c := _start()
	var w := c.world
	var s: Vector2i = _combat(c, 3)[1]
	c.update(1.0 / 30, [])
	assert_true(c.view.grid)
	assert_eq(PyMath.fmod_py(c.view.angle, 90), 0.0)
	var start := Vector2i(w.player.x, w.player.y)
	c.press(FW)
	for _i in 60:                                  # holding W: no more steps (move spent)
		c.update(1.0 / 30, [FW])
	assert_eq(Vector2i(w.player.x, w.player.y), start + s)
	c.press(FW)                                    # a second step is refused
	assert_eq(Vector2i(w.player.x, w.player.y), start + s)
	var angle := c.view.angle
	c.press(TL)                                    # a quarter turn, for free
	assert_eq(c.view.angle, PyMath.fmod_py(angle - 90, 360))
	for _i in 20:                                  # holding Q: no free look
		c.update(1.0 / 30, [TL])
	assert_eq(c.view.angle, PyMath.fmod_py(angle - 90, 360))
	w.combat = null                                # the fight ends: free look again
	c.update(1.0 / 30, [])
	assert_false(c.view.grid)


func test_combat_rounds_an_off_grid_look_and_the_camera_glides_there() -> void:
	var c := _start()
	var w := c.world
	_combat(c)
	var a := c.view.angle
	c.view.angle = a + 30
	c.view.prepare_floor(w)
	c.view.update_camera(w, 1)
	c.update(1.0 / 30, [])
	assert_eq(c.view.angle, a)                     # rounded to the nearest 90
	assert_true(c.view.animating(w))               # and the camera turns there, no jump
	for _i in 30:
		c.update(1.0 / 30, [])
	assert_false(c.view.animating(w))


func test_held_walk_stops_when_a_fight_starts() -> void:
	var c := _start()
	var w := c.world
	_quiet(w)
	var found := _corridor(w, 3)
	var spot: Vector2i = found[0]
	var d: int = found[1]
	_place(c, spot, d)
	var s: Vector2i = FpLogic.DIRS8[d]
	var goblin := Entities.spawn_monster("goblin", spot.x + 3 * s.x, spot.y + 3 * s.y)
	goblin.hp = 999
	goblin.max_hp = 999
	w.monsters.append(goblin)
	for _i in 90:                                  # hold W: it sees you within a step
		c.update(1.0 / 30, [FW])
		if w.combat != null:
			break
	assert_not_null(w.combat)
	assert_true(c.view.grid)
	for _i in 60:
		c.update(1.0 / 30, [FW])
	assert_true(w.combat == null or w.combat.has("move"))   # the held key didn't spend your move


func test_descend_and_wait_go_to_the_rules() -> void:
	var c := _start()
	var w := c.world
	_quiet(w)
	var turn := w.turn
	assert_true(c.press(&"wait"))
	assert_eq(w.turn, turn + 1)
	var st: Vector2i = w.floor.stairs[0]
	w.player.x = st.x
	w.player.y = st.y
	w.has_key = true
	var old_floor := w.floor
	assert_true(c.press(&"descend"))
	assert_eq(w.depth, 2)
	assert_true(w.floor != old_floor)
	assert_true(c.view.cam.is_empty())             # a new floor: face the open way and snap
	var p := w.player
	var best := 0
	var runs: Array[int] = []
	for dd in 4:
		var n := 0
		var step := FpLogic.DIRS[dd]
		while w.floor.walkable(p.x + step.x * (n + 1), p.y + step.y * (n + 1)):
			n += 1
		runs.append(n)
		best = maxi(best, n)
	assert_eq(runs[c.view.facing], best)
	assert_false(c.press(&"pickup"))               # not a P4 action: left for the caller

extends TestCase
## First-person camera maths (P4 parts of tests/test_firstperson.py): angles, steps, target_ahead,
## open_facing, the glide, the combat lock and the hurt flash. Headless: FpLogic has no Nodes.


func _monster(key: String, x: int, y: int) -> Monster:
	return Entities.spawn_monster(key, x, y)


func test_steps_are_relative_to_facing() -> void:
	var v := FpLogic.new()
	v.facing = 0                                   # north
	assert_eq(v.relative("forward"), Vector2i(0, -1))
	assert_eq(v.relative("right"), Vector2i(1, 0))
	v.turn(1)                                      # east
	assert_eq(v.relative("forward"), Vector2i(1, 0))
	assert_eq(v.relative("left"), Vector2i(0, -1))
	v.turn(-2)                                     # west
	assert_eq(v.relative("back"), Vector2i(1, 0))


func test_forward_attacks_a_diagonal_monster_ahead() -> void:
	var w := World.new(5)
	w.monsters.clear()
	var p := w.player
	var v := FpLogic.new()
	v.facing = 1
	var m := _monster("goblin", p.x + 1, p.y - 1)  # front-left when facing east
	w.monsters.append(m)
	var hit := v.target_ahead(w)
	assert_true(hit[0] == m)
	assert_eq(hit[1], Vector2i(1, -1))


func test_step_for_angle_rounds_to_the_nearest_of_8() -> void:
	var cases := [[0, Vector2i(0, -1)], [22, Vector2i(0, -1)], [23, Vector2i(1, -1)],
			[44, Vector2i(1, -1)], [46, Vector2i(1, -1)], [68, Vector2i(1, 0)], [90, Vector2i(1, 0)],
			[135, Vector2i(1, 1)], [180, Vector2i(0, 1)], [359, Vector2i(0, -1)], [360, Vector2i(0, -1)],
			[-45, Vector2i(-1, -1)], [-90, Vector2i(-1, 0)], [-135, Vector2i(-1, 1)],
			[-400, Vector2i(-1, -1)]]
	for c in cases:
		assert_eq(FpLogic.step_for_angle(c[0]), c[1], "angle %s" % c[0])
	# Python rounds half to even: 22.5 / 45 = 0.5 -> 0 (north), 67.5 / 45 = 1.5 -> 2 (east).
	assert_eq(FpLogic.step_for_angle(22.5), Vector2i(0, -1))
	assert_eq(FpLogic.step_for_angle(67.5), Vector2i(1, 0))


func test_angle_gap_is_the_shortest_turn() -> void:
	assert_eq(FpLogic.angle_gap(10.0, 350.0), 20.0)
	assert_eq(FpLogic.angle_gap(350.0, 10.0), -20.0)
	assert_eq(FpLogic.angle_gap(180.0, 0.0), -180.0)
	assert_eq(FpLogic.angle_gap(90.0, 90.0), 0.0)


func test_back_and_strafe_at_45_degrees() -> void:
	var v := FpLogic.new()
	v.angle = 45                                   # north-east
	assert_eq(v.relative("forward"), Vector2i(1, -1))
	assert_eq(v.relative("back"), Vector2i(-1, 1))
	assert_eq(v.relative("left"), Vector2i(-1, -1))
	assert_eq(v.relative("right"), Vector2i(1, 1))
	v.angle = 50                                   # off the line: still the nearest 45
	assert_eq(v.relative("right"), Vector2i(1, 1))
	assert_eq(v.facing, 1)
	assert_eq(v.compass(), "NE")


func test_tapped_turns_land_on_45_degree_lines() -> void:
	var v := FpLogic.new()
	v.angle = 90
	v.tap_turn(-1)
	assert_eq(v.angle, 45.0)
	v.tap_turn(-1)
	v.tap_turn(-1)
	assert_eq(v.angle, 315.0)
	v.angle = 30                                   # after free look: on to the next line
	v.tap_turn(1)
	assert_eq(v.angle, 45.0)
	v.angle = 30
	v.tap_turn(-1)
	assert_eq(v.angle, 0.0)


func test_target_ahead_in_8_ways() -> void:
	var w := World.new(5)
	w.monsters.clear()
	var p := w.player
	var v := FpLogic.new()
	v.angle = 10                                   # just east of north: ahead is north
	var nw := _monster("goblin", p.x - 1, p.y - 1)
	var ne := _monster("goblin", p.x + 1, p.y - 1)
	var n := _monster("goblin", p.x, p.y - 1)
	w.monsters.append_array([nw, ne, n])
	var hit := v.target_ahead(w)
	assert_true(hit[0] == n)                       # straight ahead first
	assert_eq(hit[1], Vector2i(0, -1))
	w.monsters.erase(n)
	hit = v.target_ahead(w)
	assert_true(hit[0] == ne)                      # then the diagonal nearer in angle
	assert_eq(hit[1], Vector2i(1, -1))
	v.angle = 350
	hit = v.target_ahead(w)
	assert_true(hit[0] == nw)
	assert_eq(hit[1], Vector2i(-1, -1))
	w.monsters.assign([_monster("goblin", p.x + 1, p.y)])
	v.angle = 40                                   # ahead is NE; east is 45 degrees off it
	assert_eq(v.target_ahead(w)[1], Vector2i(1, 0))
	v.angle = 180
	assert_eq(v.target_ahead(w), [null, null])


func test_camera_glides_at_walking_speed_and_settles_on_the_tile_centre() -> void:
	var w := World.new(4)
	var v := FpLogic.new()
	v.update_camera(w)
	w.player.x += 1
	v.update_camera(w, 0.1)                        # a tenth of a second: 0.4 of a tile
	assert_almost_eq(v.glide_left(w), 1 - FpLogic.WALK_SPEED * 0.1, 1e-6)
	for _i in 10:
		v.update_camera(w, 0.05)
	assert_eq(v.glide_left(w), 0.0)
	assert_eq(v.cam.slice(0, 2), [w.player.x + 0.5, w.player.y + 0.5])


func test_a_big_jump_or_a_long_frame_snaps() -> void:
	var w := World.new(4)
	var v := FpLogic.new()
	v.update_camera(w)
	w.player.x += 3                                # more than 2.5 tiles: a load or a new floor
	v.update_camera(w, 0.02)
	assert_eq(v.glide_left(w), 0.0)
	w.player.x -= 1
	v.update_camera(w, 1.0)                        # dt >= 1 snaps
	assert_eq(v.glide_left(w), 0.0)


func test_open_facing_picks_the_longest_open_run() -> void:
	var f := _FakeFloor.new()                      # a plus shape: short north arm, long west arm
	f.open = {Vector2i(5, 5): true, Vector2i(5, 4): true, Vector2i(6, 5): true, Vector2i(4, 5): true,
			Vector2i(3, 5): true, Vector2i(2, 5): true, Vector2i(5, 6): true, Vector2i(5, 7): true}
	assert_eq(FpLogic.open_facing(f, 5, 5), 3)
	assert_eq(FpLogic.open_facing(f, 5, 4), 2)     # the dead end faces back down the corridor
	f.open = {Vector2i(5, 5): true}
	assert_eq(FpLogic.open_facing(f, 5, 5, 2), 2)  # boxed in: keep the old facing


func test_combat_settles_the_angle_and_glides_to_the_tile_centre() -> void:
	var w := World.new(4)
	var v := FpLogic.new()
	var p := w.player
	v.prepare_floor(w)
	v.angle = 130
	v.update_camera(w, 1)                          # snapped where we were looking
	v.cam[0] += 0.4                                # mid-glide, a little off the tile centre
	v.set_combat(true)
	assert_true(v.grid)
	assert_eq(v.angle, 90.0)
	v.update_camera(w, 0.02)
	assert_ne(v.cam, [p.x + 0.5, p.y + 0.5, v.cam[2]])   # glides, doesn't jump
	for _i in 100:
		v.update_camera(w, 0.02)
	assert_eq(v.cam.slice(0, 2), [p.x + 0.5, p.y + 0.5])
	assert_false(v.animating(w))
	assert_eq(v.relative("forward"), Vector2i(1, 0))
	assert_eq(v.relative("left"), Vector2i(0, -1))
	v.set_combat(false)
	assert_false(v.grid)
	assert_eq(v.angle, 90.0)                       # free look resumes from the settled angle


func test_new_floors_face_the_most_open_way_and_snap() -> void:
	var w := World.new(7)
	var v := FpLogic.new()
	v.reset(w)
	assert_true(v.prepare_floor(w))
	assert_false(v.prepare_floor(w))               # same floor object: nothing to rebuild
	v.update_camera(w)
	var p := w.player
	var best := 0
	for d in 4:
		best = maxi(best, _run(w.floor, p.x, p.y, d))
	assert_eq(_run(w.floor, p.x, p.y, v.facing), best)
	for depth in [2, 3, 2, 3]:                     # the floor object, not its id, is the key
		w.new_floor(depth)
		v.turn(1)
		v.follow_floor(w)
		assert_true(v.cam.is_empty())
		assert_true(v.prepare_floor(w))
		best = 0
		for d in 4:
			best = maxi(best, _run(w.floor, p.x, p.y, d))
		assert_eq(_run(w.floor, p.x, p.y, v.facing), best)


func test_hurt_flash_only_on_real_damage() -> void:
	var w := World.new(4)
	var v := FpLogic.new()
	var p := w.player
	v.note_hp(w)
	p.max_hp -= 1                                  # choosing Elf: a lower max HP
	p.hp = mini(p.hp, p.max_hp)
	v.note_hp(w)
	assert_eq(v.flash, 0.0)
	p.hp -= 2                                      # a real hit
	v.note_hp(w)
	assert_gt(v.flash, 0.0)
	v.flash = 0
	p.max_hp -= 1                                  # a hit in the same turn as a max HP change
	p.hp -= 3
	v.note_hp(w)
	assert_gt(v.flash, 0.0)
	v.fade_flash(1.0)                              # a second at 30 frames a second: gone
	assert_lt(v.flash, 0.02)
	p.hp -= 1
	v.note_hp(w, false)                            # behind a menu: no flash
	assert_eq(v.flash, 0.0)
	v.reset_camera()
	p.hp -= 1
	v.note_hp(w)                                   # first look after a reset: no stale flash
	assert_eq(v.flash, 0.0)


func test_depth_tints_follow_the_art_bible() -> void:
	assert_eq(FpLogic.depth_tint(1), Color(1.0, 1.0, 1.0))
	assert_eq(FpLogic.depth_tint(6), Color(1.05, 0.72, 0.66))
	assert_eq(FpLogic.depth_tint(7), FpLogic.depth_tint(1))


func _run(f: DungeonFloor, x: int, y: int, d: int) -> int:
	var s := FpLogic.DIRS[d]
	var n := 0
	while f.walkable(x + s.x * (n + 1), y + s.y * (n + 1)):
		n += 1
	return n


class _FakeFloor:
	var open: Dictionary = {}

	func walkable(x: int, y: int) -> bool:
		return open.has(Vector2i(x, y))

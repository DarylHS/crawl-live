extends TestCase
## P8 effects, the timing and the skip rules (headless): shake, flashes, floating numbers, slides, the
## weapon swing and delayed sounds in FxState, the weapon poses (ViewModelPose), the loot box timeline
## (FxReveal) and which creature an event is about (FxTargets). No window: all of it is plain maths.


func _state(mode: String = "on") -> FxState:
	var s := FxState.new()
	s.set_mode(mode)
	return s


# --- Shake ----------------------------------------------------------------------------------

func test_shake_wobbles_then_dies_away_on_time() -> void:
	var s := _state()
	assert_eq(s.shake_offset(), Vector2.ZERO)
	s.kick(0.6, 0.4)
	assert_true(s.shaking())
	s.advance(0.05)
	assert_ne(s.shake_offset(), Vector2.ZERO)
	var early := s.shake_offset().length()
	for _i in 6:
		s.advance(0.05)
	assert_lt(s.shake_offset().length(), early)                  # decaying
	s.advance(0.2)
	assert_false(s.shaking())
	assert_eq(s.shake_offset(), Vector2.ZERO)


func test_shake_adds_up_but_never_past_one_and_extends_the_time() -> void:
	var s := _state()
	for _i in 5:
		s.kick(0.8, 0.3)
	var worst := 0.0
	for i in 20:
		s.advance(0.01)
		worst = maxf(worst, s.shake_offset().length())
	assert_lte(worst, sqrt(2.0) * FxState.SHAKE_MAX + 0.001)
	var t := _state()
	t.kick(0.5, 0.2)
	t.kick(0.5, 0.9)
	t.advance(0.5)
	assert_true(t.shaking())


func test_shake_is_ignored_when_reduced_or_off() -> void:
	for mode in ["reduced", "off"]:
		var s := _state(mode)
		s.kick(1.0, 1.0)
		assert_false(s.shaking(), mode)
		assert_eq(s.shake_offset(), Vector2.ZERO, mode)


# --- Flashes, numbers, slides, swing, sounds ----------------------------------------------------------

func test_a_flash_starts_full_fades_and_goes() -> void:
	var s := _state()
	s.flash(42, 1.0, 0.2)
	assert_eq(s.flash_of(42), 1.0)
	assert_eq(s.flash_of(7), 0.0)
	s.advance(0.1)
	assert_almost_eq(s.flash_of(42), 0.5, 0.001)
	s.advance(0.11)
	assert_eq(s.flash_of(42), 0.0)
	var r := _state("reduced")
	r.flash(1, 0.5, 0.2)                                         # reduced still flashes, FxPlan halves the strength
	assert_eq(r.flash_of(1), 0.5)
	var off := _state("off")
	off.flash(1, 1.0, 0.2)
	assert_eq(off.flash_of(1), 0.0)


func test_numbers_climb_fade_stack_and_are_capped() -> void:
	var s := _state()
	s.add_number("-5", "hit", Vector2(500, 300), 1.0)
	var n: Dictionary = s.numbers[0]
	var y0 := FxState.number_pos(n).y
	assert_eq(FxState.number_alpha(n), 1.0)
	s.advance(0.5)
	assert_lt(FxState.number_pos(s.numbers[0]).y, y0)             # climbs
	assert_eq(FxState.number_alpha(s.numbers[0]), 1.0)
	s.advance(0.4)
	assert_lt(FxState.number_alpha(s.numbers[0]), 1.0)            # fading over the last 40%
	s.advance(0.2)
	assert_eq(s.numbers.size(), 0)
	s.add_number("a", "hit", Vector2(100, 100), 1.0)
	s.add_number("b", "crit", Vector2(110, 100), 1.0)             # nearly the same spot: stacked above
	assert_lt(FxState.number_pos(s.numbers[1]).y, FxState.number_pos(s.numbers[0]).y)
	for i in 30:
		s.add_number("n%d" % i, "hit", Vector2(i * 90, 50), 1.0)
	assert_lte(s.numbers.size(), FxState.MAX_NUMBERS)
	var off := _state("off")
	off.add_number("x", "hit", Vector2.ZERO, 1.0)
	assert_eq(off.numbers.size(), 0)
	s.set_mode("off")
	assert_eq(s.numbers.size(), 0)                                # switching off clears them


func test_an_actor_that_steps_slides_over_to_its_tile() -> void:
	var s := _state()
	s.track_actor(9, Vector2i(3, 3))
	assert_eq(s.slide_offset(9), Vector2.ZERO)                    # first sight: nothing to slide from
	s.track_actor(9, Vector2i(4, 3))
	assert_eq(s.slide_offset(9), Vector2(-1, 0))                  # drawn one tile back, where it was
	s.advance(FxState.SLIDE_DUR / 2.0)
	assert_almost_eq(s.slide_offset(9).x, -0.5, 0.001)
	s.advance(FxState.SLIDE_DUR)
	assert_eq(s.slide_offset(9), Vector2.ZERO)
	s.track_actor(9, Vector2i(9, 9))                              # a jump of several tiles just snaps
	assert_eq(s.slide_offset(9), Vector2.ZERO)
	var off := _state("off")
	off.track_actor(1, Vector2i(0, 0))
	off.track_actor(1, Vector2i(1, 0))
	assert_eq(off.slide_offset(1), Vector2.ZERO)
	s.forget_actors()
	s.track_actor(9, Vector2i(5, 9))
	assert_eq(s.slide_offset(9), Vector2.ZERO)                    # a new floor: no slide from the old tile


func test_a_swing_runs_for_its_duration_and_restarts() -> void:
	var s := _state()
	assert_eq(s.swing_progress(), -1.0)
	s.start_swing("blade")
	assert_eq(s.swing_progress(), 0.0)
	s.advance(ViewModelPose.duration("blade") / 2.0)
	assert_almost_eq(s.swing_progress(), 0.5, 0.001)
	s.start_swing("blunt")                                        # a new swing overrides
	assert_eq(s.swing_progress(), 0.0)
	assert_eq(s.swing_style(), "blunt")
	s.advance(1.0)
	assert_eq(s.swing_progress(), -1.0)
	var off := _state("off")
	off.start_swing("blade")
	assert_eq(off.swing_progress(), -1.0)


func test_delayed_sounds_come_due_in_order() -> void:
	var s := _state()
	s.delay_sound("box_open", 0.75)
	s.delay_sound("late", 2.0)
	assert_eq(s.advance(0.5).size(), 0)
	assert_eq(s.advance(0.3), ["box_open"] as Array[String])
	assert_eq(s.advance(1.5), ["late"] as Array[String])
	assert_eq(s.advance(5.0).size(), 0)


# --- The skip rule ----------------------------------------------------------------------------

func test_a_key_press_finishes_the_moving_effects_but_not_the_numbers() -> void:
	var s := _state()
	s.kick(1.0, 1.0)
	s.flash(1, 1.0, 1.0)
	s.start_swing("blunt")
	s.track_actor(3, Vector2i(0, 0))
	s.track_actor(3, Vector2i(1, 0))
	s.delay_sound("box_open", 0.75)
	s.add_number("-9", "crit", Vector2(300, 300), 1.0)
	assert_true(s.busy())
	s.on_key()
	assert_false(s.shaking())
	assert_eq(s.shake_offset(), Vector2.ZERO)
	assert_eq(s.flash_of(1), 0.0)
	assert_eq(s.swing_progress(), -1.0)
	assert_eq(s.slide_offset(3), Vector2.ZERO)
	assert_eq(s.advance(5.0).size(), 0, "delayed sounds are dropped")
	var n := _state()
	n.add_number("-9", "crit", Vector2(300, 300), 1.0)
	n.on_key()
	assert_eq(n.numbers.size(), 1)                                # still drifting after a key press


func test_input_never_waits_a_thousand_key_presses_leave_nothing_queued() -> void:
	var s := _state()
	for i in 1000:
		s.on_key()
		s.kick(1.0, 5.0)
		s.start_swing("blade")
		s.flash(i % 7, 1.0, 5.0)
		s.delay_sound("box_open", 5.0)
		s.advance(0.001)
	s.on_key()
	assert_false(s.busy())
	assert_false(s.shaking())
	assert_eq(s.swing_progress(), -1.0)


# --- Weapon poses ------------------------------------------------------------------------------

func test_every_swing_starts_and_ends_at_rest_and_moves_in_between() -> void:
	for style in ["blade", "blunt", "unarmed"]:
		var a := ViewModelPose.swing(style, 0.0)
		var b := ViewModelPose.swing(style, 1.0)
		assert_eq(a["off"], Vector2.ZERO, style)
		assert_eq(b["off"], Vector2.ZERO, style)
		assert_eq(float(b["rot"]), 0.0, style)
		var far := 0.0
		for i in 21:
			far = maxf(far, (ViewModelPose.swing(style, i / 20.0)["off"] as Vector2).length())
		assert_gt(far, 15.0, "%s swings through a real distance" % style)
		assert_gt(ViewModelPose.duration(style), 0.1)
		assert_lt(ViewModelPose.duration(style), 0.5, "short enough never to feel slow")
	assert_ne(ViewModelPose.swing("blade", 0.55)["off"], ViewModelPose.swing("blunt", 0.55)["off"])
	assert_eq(ViewModelPose.swing("nonsense", 0.5), ViewModelPose.swing("blunt", 0.5))
	assert_eq(ViewModelPose.swing("blade", 7.0)["off"], Vector2.ZERO)    # clamped


func test_the_idle_sway_follows_walking_and_switches_off() -> void:
	assert_eq(ViewModelPose.idle(1.0, 3.0, 1.0, 0.0), Vector2.ZERO)
	var still := ViewModelPose.idle(1.0, 3.0, 0.0, 1.0)
	var walking := ViewModelPose.idle(1.0, 3.3, 1.0, 1.0)
	assert_lt(still.length(), 1.5)
	assert_ne(walking, still)


# --- The loot box timeline -----------------------------------------------------------------------

func test_the_box_rattles_then_opens_and_a_key_ends_it_at_once() -> void:
	var r := FxReveal.new()
	assert_true(r.is_done())
	r.start()
	assert_true(r.item_hidden())
	r.advance(0.3)
	assert_gt(r.shake_offset().length(), 0.0)
	assert_eq(r.lid_lift(), 0.0)
	assert_false(r.should_burst())
	r.advance(FxReveal.SHAKE_END)
	assert_false(r.item_hidden())
	assert_true(r.should_burst())
	assert_false(r.should_burst(), "the burst fires once")
	assert_gt(r.light(), 0.0)
	r.advance(1.0)
	assert_true(r.is_done())
	assert_eq(r.lid_lift(), 1.0)
	r.start()
	r.skip()
	assert_true(r.is_done())
	assert_false(r.item_hidden())


# --- Which creature ------------------------------------------------------------------------------

func test_the_nearest_creature_of_the_events_key_is_the_target() -> void:
	var actors := [{"id": 1, "key": "rat", "tile": Vector2i(5, 5)}, {"id": 2, "key": "goblin", "tile": Vector2i(9, 5)},
			{"id": 3, "key": "goblin", "tile": Vector2i(6, 5)}, {"id": 4, "key": "goblin", "tile": Vector2i(6, 6)}]
	assert_eq(FxTargets.nearest(actors, Vector2i(5, 5), "goblin")["id"], 3)      # nearest, first in the list on a tie
	assert_eq(FxTargets.nearest(actors, Vector2i(9, 5))["id"], 2)
	assert_eq(FxTargets.nearest(actors, Vector2i(0, 0), "troll"), null)
	assert_eq(FxTargets.nearest([], Vector2i(0, 0)), null)

extends TestCase
## The HUD (P6): the P6 tests of tests/test_render.py (provoke flags, tracker and banner, boss fight,
## none / one / many fighters, menus hiding the first-person overlays, boxes keeping clear of you, long
## boss names) run on the real Hud over a GameView, plus the model classes in ui/hud/ (panel wording,
## log wrapping and fade, toast pruning, the two-round combat banner, pips, scout report numbers).

const GAME := preload("res://scenes/game_view.tscn")
const HUD := preload("res://scenes/hud.tscn")

var style := HudStyle.new()


## A GameView with a Hud over it on a seed-1 world, as main.tscn lays them out.
func _screen(seed_value: int = 1) -> Array:
	var holder := Control.new()
	holder.size = Vector2(1280, 768)
	add_child_autofree(holder)
	var g: GameView = GAME.instantiate()
	g.settings_path = ""
	g.runs_dir = ""
	g.input_enabled = false
	holder.add_child(g)
	g.size = Vector2(1024, 640)
	var h: Hud = HUD.instantiate()
	holder.add_child(h)
	var hero := {"name": "Crawler", "gender": Content.table("genders").keys()[0],
			"backstory": Content.table("backstories").keys()[0]}
	var w := World.new(seed_value, [Content.table("pets").keys()[0], ""], hero)
	g.start(w)
	h.bind(g)
	return [g, h, w]


func _empty(w: World, x: int, y: int) -> bool:
	return w.floor.walkable(x, y) and w.monster_at(x, y) == null and w.pet_at(x, y) == null


## Python `_corridor`: a tile and a direction (0-7) with exactly n empty tiles ahead, then solid.
func _corridor(w: World, n: int, dirs: Array) -> Array:
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


## Python `_place`: stand there, look along d, snap the camera.
func _place(g: GameView, spot: Vector2i, d: int) -> void:
	var w := g.world
	w.player.x = spot.x
	w.player.y = spot.y
	w.update_fov()
	g.fp_view.logic.angle = d * 45
	g.fp_view.logic.reset_camera()
	g.fp_view.refresh(0.0)


## Python test_render `_combat`: a sturdy stunned monster `gap` tiles down a straight corridor, a fight on.
func _combat(g: GameView, h: Hud, gap: int = 2, boss: bool = false) -> Array:
	var w := g.world
	w.monsters.clear()
	w.pet.downed = true
	w.player.max_hp = 999
	w.player.hp = 999
	var found := _corridor(w, 3, [0, 2, 4, 6])
	var spot: Vector2i = found[0]
	var d: int = found[1]
	_place(g, spot, d)
	var s: Vector2i = FpLogic.DIRS8[d]
	var m := Bosses.spawn_boss(w.depth, spot.x + gap * s.x, spot.y + gap * s.y) if boss \
			else Entities.spawn_monster("goblin", spot.x + gap * s.x, spot.y + gap * s.y)
	m.hp = 999
	m.max_hp = 999
	w.monsters.append(m)
	w.update_fov()
	assert_true(w.join_combat(m))
	w.combat.round = 1
	m.stunned = 99
	g.fp_view.logic.angle = d * 45
	h.sync()
	return [m, s]


## Both views' HUD for the same world: calls fn(view_name) once in each.
func _each_view(g: GameView, h: Hud, fn: Callable) -> void:
	for v in ["top", "fp"]:
		g.set_view(v)
		h.sync()
		fn.call(v)


func _pips(h: Hud) -> Array:
	return HudTracker.pips(h.game_view.world.combat)


# --- Python tests ---------------------------------------------------------------------------

func test_combat_tracker_and_screens_in_both_views() -> void:
	var a := _screen()
	var g: GameView = a[0]
	var h: Hud = a[1]
	var w: World = a[2]
	var c := _combat(g, h)
	var s: Vector2i = c[1]
	var banner := false
	for t: Array in w.toasts:
		banner = banner or t[1] == "COMBAT: roll for initiative"
	assert_true(banner)
	_each_view(g, h, func(_v: String) -> void:
		assert_ne(h.last_tracker, Rect2i())                # the tracker is up in both views
		assert_eq(h.last_toasts.size(), 1))                # with the combat banner
	assert_true(w.move_player(s.x, s.y))
	assert_false(w.combat.has("move"))
	h.sync()
	assert_false(_pips(h)[0]["available"])                 # move spent
	assert_true(w.wait())
	assert_eq(w.combat.round, 2)                           # Space ends your turn
	assert_true(w.move_player(s.x, s.y))                   # a real attack: the action is spent
	assert_false(w.combat.has("action"))
	assert_true(w.combat.has("move"))
	h.sync()
	assert_false(_pips(h)[1]["available"])
	w.inventory.append("tonic")                            # a potion to drink as the bonus action
	h.covered = true                                       # the inventory covers the view...
	h.tracker_over_menu = true                             # ...but keeps the tracker so the pips show
	h.sync()
	assert_ne(h.last_tracker, Rect2i())
	assert_true(w.combat.has("bonus"))
	assert_true(h.last_toasts.is_empty())                  # menus hide the toasts
	h.covered = false
	h.tracker_over_menu = false
	w.player.attack = 100
	(c[0] as Monster).hp = 1
	w.wait()
	assert_true(w.move_player(s.x, s.y))
	assert_null(w.combat)
	h.sync()
	assert_eq(h.last_tracker, Rect2i())                    # the fight is over


func test_combat_with_a_boss_draws() -> void:
	var a := _screen()
	var g: GameView = a[0]
	var h: Hud = a[1]
	var w: World = a[2]
	var c := _combat(g, h, 2, true)
	assert_true(w.combat.has_entity(c[0]))
	var rows := HudTracker.rows(w)
	var boss_row: Dictionary = rows.filter(func(r: Dictionary) -> bool: return not r["you"] and r["name"] == (c[0] as Monster).name)[0]
	assert_eq(boss_row["colour"], HudTracker.TIER_COLOURS["headliner"])   # boss rows take their tier colour
	_each_view(g, h, func(_v: String) -> void: assert_ne(h.last_tracker, Rect2i()))
	assert_true((h.last_tracker.size.y) > 0)


func test_tracker_draws_with_none_one_and_many_fighters() -> void:
	for view_name in ["top", "fp"]:
		var a := _screen()
		var g: GameView = a[0]
		var h: Hud = a[1]
		var w: World = a[2]
		g.set_view(view_name)
		var enc := Encounter.new(w.player)
		enc.add(w.player, 10, 1)
		w.combat = enc
		var sizes: Array[int] = []
		for n in [0, 1, 12]:
			while enc.monsters.size() < n:
				enc.add(Entities.spawn_monster("goblin", 0, 0), enc.monsters.size(), 0)
			h.sync()
			var box := h.last_tracker
			sizes.append(box.size.y)
			assert_lt(box.end.x, 512 - 210)                # clear of the toasts and ahead label
			assert_lt(box.end.y, 320 - 60)                 # clear of the side chevrons
			if view_name == "fp":
				var mm := g.fp_view.minimap
				assert_false(box.intersects(Rect2i(Vector2i(mm.global_position), Vector2i(mm.size))))
		assert_true(sizes[0] < sizes[1] and sizes[1] < sizes[2])


func test_the_hud_rebuilds_only_when_something_changed() -> void:
	var a := _screen()
	var h: Hud = a[1]
	var w: World = a[2]
	var n := h.rebuilds
	for i in 5:
		h.sync()
	assert_eq(h.rebuilds, n)                                # nothing changed: nothing rebuilt
	w.wait()
	h.sync()
	assert_eq(h.rebuilds, n + 1)
	h.covered = true
	h.sync()
	assert_eq(h.rebuilds, n + 2)


func test_menus_hide_the_first_person_overlays() -> void:
	var a := _screen()
	var g: GameView = a[0]
	var h: Hud = a[1]
	var w: World = a[2]
	h.sync()
	assert_true(g.fp_view.minimap.visible)                 # the minimap is drawn while playing
	assert_true(g.fp_view.hud)
	for setup in [func() -> void: h.covered = true,        # inventory or help open
			func() -> void: w.state = "dead"]:
		h.covered = false
		w.state = "playing"
		g.fp_view.logic.flash = 0.0
		setup.call()
		w.player.hp -= 1                                   # a hit behind the menu doesn't flash later
		h.sync()
		g.fp_view.refresh(0.0)
		assert_false(g.fp_view.minimap.visible)
		assert_eq(h.ahead_text, "")
		assert_eq(h.last_toasts.size(), 0)
		assert_eq(g.fp_view.logic.flash, 0.0)


func test_a_step_that_would_provoke_is_flagged_in_both_views() -> void:
	var a := _screen()
	var g: GameView = a[0]
	var h: Hud = a[1]
	var w: World = a[2]
	w.monsters.clear()
	w.pet.downed = true
	w.player.max_hp = 999
	w.player.hp = 999
	var f := w.floor
	var spot := Vector2i.ZERO
	var d := -1
	for y in f.height:
		for x in f.width:
			if d >= 0 or not _empty(w, x, y) or f.is_safe(x, y):
				continue
			for dd in [0, 2, 4, 6]:
				var s: Vector2i = FpLogic.DIRS8[dd]
				if _empty(w, x + s.x, y + s.y) and _empty(w, x - s.x, y - s.y) and not f.is_safe(x - s.x, y - s.y):
					spot = Vector2i(x, y)
					d = dd
					break
	assert_gte(d, 0)
	_place(g, spot, d)
	var s: Vector2i = FpLogic.DIRS8[d]
	var gob := Entities.spawn_monster("goblin", spot.x - s.x, spot.y - s.y)   # right behind you
	gob.hp = 999
	gob.max_hp = 999
	w.monsters.append(gob)
	assert_true(w.join_combat(gob))
	g.fp_view.controller.update(1.0 / 30, [])
	assert_eq(w.threats(), [gob])
	assert_eq(HudFp.provoking(w, g.fp_view.logic), [gob])
	g.set_view("fp")
	h.sync()
	assert_true(h.ahead_text.begins_with("W provokes the Knockoff Goblin"))
	assert_false(h.last_toasts.is_empty())                  # the COMBAT banner is up...
	for r in h.last_toasts:
		assert_false(h.ahead_rect.intersects(r))            # ...and the label is clear of it
	var chev := HudFp.chevrons(w, g.fp_view.logic.angle, HudPlace.map_rect(), [gob])
	assert_eq(chev.size(), 1)
	assert_eq(chev[0]["text"], "BEHIND YOU")
	assert_true(chev[0]["provoked"])                        # orange, not red
	g.set_view("top")                                       # the map view flags it with brackets
	g.top_view.refresh()
	await get_tree().process_frame
	await get_tree().process_frame
	assert_eq(g.top_view.marks.drawn["brackets"], 1)
	var log_before := w.messages.lines.size()
	g.set_view("fp")
	assert_true(g.press(&"walk_forward"))
	assert_true((w.player.x == spot.x + s.x and w.player.y == spot.y + s.y) or w.state != "playing")
	var opportunity := false
	for line in w.messages.lines.slice(log_before):
		opportunity = opportunity or String(line[0]).contains("Attack of opportunity")
	assert_true(opportunity)


func test_boxes_over_the_map_never_hide_you_in_a_top_left_corner() -> void:
	var a := _screen()
	var g: GameView = a[0]
	var h: Hud = a[1]
	var w: World = a[2]
	g.set_view("top")
	w.monsters.clear()
	var f := w.floor
	var best := Vector2i(-1, -1)
	for y in f.height:
		for x in f.width:
			if not _empty(w, x, y) or f.is_safe(x, y):
				continue
			var open := false
			for dd in FpLogic.DIRS8:
				open = open or _empty(w, x + dd.x, y + dd.y)
			if open and (best.x < 0 or x + y < best.x + best.y):
				best = Vector2i(x, y)
	w.player.x = best.x
	w.player.y = best.y
	w.update_fov()
	for n in FpLogic.DIRS8.size():                          # Python: the first three of the eight directions
		var dd: Vector2i = FpLogic.DIRS8[n]
		if _empty(w, best.x + dd.x, best.y + dd.y) and n < 3:
			var m := Entities.spawn_monster("goblin", best.x + dd.x, best.y + dd.y)
			m.stunned = 99
			w.monsters.append(m)
			w.join_combat(m)
	w.add_toast("Achievement: Test", "gold", "Bronze box. Open it in a safe room.")
	h.sync()
	var actors := h.actor_rects(w)
	assert_lt(actors[0].position.x, 18 * 16)
	assert_lt(actors[0].position.y, 15 * 16)
	assert_gt(actors.size(), 2)                             # you and the fighters
	assert_ne(h.last_tracker, Rect2i())
	assert_false(h.last_toasts.is_empty())
	for r: Rect2i in actors:
		assert_false(h.last_tracker.intersects(r))
		for t in h.last_toasts:
			assert_false(t.intersects(r))


func test_long_boss_names_fit_the_tracker_cleanly() -> void:
	var room := style.width("small", " 12 Grease Trap King") - 4
	var text := HudTracker.fit_name(style, " 12 ", "The Grease Trap King", room)
	assert_eq(text, " 12 Grease Trap...")
	assert_lte(style.width("small", text), room)
	assert_eq(HudTracker.fit_name(style, " 3 ", "Goblin", 200), " 3 Goblin")
	var one := HudTracker.fit_name(style, " 3 ", "Supercalifragilisticexpialidocious", 80)
	assert_true(one.ends_with("..."))
	assert_lte(style.width("small", one), 80)


# --- Models -------------------------------------------------------------------------------

func test_toasts_expire_and_the_combat_banner_is_short() -> void:
	var a := _screen()
	var w: World = a[2]
	w.toasts = []
	w.turn = 10
	w.toasts.append([10, "COMBAT: roll for initiative", "combat"])
	w.toasts.append([10, "Achievement: A", "gold", "Sub"])
	assert_eq(HudToasts.live(w).size(), 2)
	w.turn = 11
	assert_eq(HudToasts.live(w).size(), 2)                  # one turn on: both up
	w.turn = 12
	assert_eq(HudToasts.live(w).size(), 1)                  # the banner lasts COMBAT_TOAST_TURNS (2)
	w.turn = 10 + GameConfig.TOAST_TURNS - 1
	assert_eq(HudToasts.live(w).size(), 1)
	w.turn = 10 + GameConfig.TOAST_TURNS
	assert_eq(HudToasts.live(w).size(), 0)
	w.turn = 10
	for i in 5:
		w.toasts.append([10, "T%d" % i, "bronze"])
	assert_eq(HudToasts.live(w).size(), 3)                  # at most three, the newest
	assert_eq(HudToasts.live(w)[2][1], "T4")
	var lay := HudToasts.layout(w)
	assert_eq(lay[0]["rect"].position.y, 10)
	assert_eq(lay[0]["rect"].size.y, 30)
	w.toasts = [[10, "Sub", "gold", "x"]]
	assert_eq(HudToasts.layout(w)[0]["rect"].size.y, 46)    # a sub line makes it taller


func test_toasts_move_to_the_bottom_when_the_top_would_hide_you() -> void:
	var a := _screen()
	var w: World = a[2]
	w.toasts = [[w.turn, "Hello", "gold"]]
	var top := HudToasts.layout(w, [Rect2i(400, 10, 16, 16)])
	assert_eq(top[0]["rect"].position.y, 640 - 10 - 30)
	assert_eq(HudToasts.layout(w, [Rect2i(400, 200, 16, 16)])[0]["rect"].position.y, 10)


func test_clear_spot_prefers_not_covering_you() -> void:
	var tl := Rect2i(0, 0, 100, 100)
	var br := Rect2i(0, 200, 100, 100)
	assert_eq(HudPlace.clear_spot([tl, br], []), tl)
	assert_eq(HudPlace.clear_spot([tl, br], [Rect2i(10, 10, 16, 16)]), br)
	assert_eq(HudPlace.clear_spot([tl, br], [Rect2i(500, 500, 16, 16), Rect2i(10, 10, 16, 16)]), br)   # fewest others covered
	assert_eq(HudPlace.clear_spot([tl, br], [Rect2i(500, 500, 16, 16), Rect2i(10, 10, 16, 16), Rect2i(10, 210, 16, 16)]), tl)   # a tie keeps the first
	assert_eq(HudPlace.clear_spot([tl, br], [Rect2i(100, 0, 16, 16)]), tl)   # touching is not covering


func test_pips_are_move_action_bonus_and_follow_the_budget() -> void:
	var a := _screen()
	var w: World = a[2]
	w.combat = Encounter.new(w.player)
	var pips := HudTracker.pips(w.combat)
	assert_eq(pips.map(func(p: Dictionary) -> String: return p["label"]), ["Move", "Action", "Bonus"])
	assert_true(pips.all(func(p: Dictionary) -> bool: return p["available"]))
	w.combat.spend("action")
	assert_eq(HudTracker.pips(w.combat).map(func(p: Dictionary) -> bool: return p["available"]), [true, false, true])


func test_tracker_lists_eight_rows_then_more() -> void:
	var a := _screen()
	var h: Hud = a[1]
	var w: World = a[2]
	w.combat = Encounter.new(w.player)
	w.combat.add(w.player, 10, 1)
	for i in 12:
		w.combat.add(Entities.spawn_monster("goblin", 0, 0), i, 0)
	var list := HudList.new(style)
	var box := HudTracker.new().build(list, w, HudPlace.map_rect(), [])
	assert_eq(box.size.y, HudTracker.box_height(13))
	assert_true(list.strings().has("  +5 more"))              # 13 fighters, 8 shown
	assert_true(list.strings().has("COMBAT"))
	assert_true(list.strings().has("round 1"))
	assert_true(list.strings().has("Space ends your turn"))
	assert_eq(h.last_tracker, Rect2i())


func test_scout_report_numbers() -> void:
	var a := _screen()
	var w: World = a[2]
	w.monsters.clear()
	w.choose_class("human", "analyst")
	assert_true(w.use_skill())
	assert_eq(HudScout.title(w), "SCOUT REPORT (%d)" % w.scout_turns)
	var p := w.player
	var m := Entities.spawn_monster("goblin", p.x + 1, p.y)
	w.monsters.append(m)
	w.visible[Vector2i(m.x, m.y)] = true
	var rows := HudScout.rows(w)
	assert_eq(rows.size(), 1)
	assert_eq(rows[0]["head"], "g Knockoff Goblin  %d/%d" % [m.hp, m.max_hp])
	var need_you := Dice.needed_roll(p.attack, m.ac)
	var line: String = rows[0]["lines"][0]
	assert_true(line.begins_with("you need %2d+ " % need_you))
	assert_true(line.ends_with(" dmg"))
	assert_true(line.contains("~%s dmg" % PyFmt.fixed(Combat.expected_damage(p, m), 1)))
	assert_true(line.contains(PyFmt.rjust(PyFmt.percent(Combat.hit_chance(p, m), 0), 4)))
	assert_true((rows[0]["lines"][1] as String).begins_with(" it need "))
	for i in 5:                                             # only the three nearest are listed
		var extra := Entities.spawn_monster("goblin", p.x, p.y + 1 + i)
		w.monsters.append(extra)
		w.visible[Vector2i(extra.x, extra.y)] = true
	assert_eq(HudScout.rows(w).size(), 3)
	var list := HudPanel.build(w, style)
	assert_true(list.strings().has(HudScout.title(w)))
	w.scout_turns = 0
	assert_false(HudPanel.build(w, style).strings().has("SCOUT REPORT (0)"))
	w.scout_turns = 5
	w.monsters.clear()
	assert_true(HudPanel.build(w, style).strings().has("Nothing in sight."))


func test_panel_wording_and_numbers() -> void:
	var a := _screen()
	var w: World = a[2]
	var s := HudPanel.build(w, style).strings()
	for line in ["CRAWL LIVE!", "Crawler, Military Veteran", "Floor 1 of 6", "Floor collapses in", w.timer_text(),
			"Stairs unlock in %s" % w.timer_text(w.stairs_wait), "HP %d/%d" % [w.player.hp, w.player.max_hp],
			"Armour Class", "To hit", "Damage", "Kills", "Gold", "Viewers", "? for all the controls"]:
		assert_true(s.has(line), line)
	assert_true(s.has(PyFmt.thousands(w.viewers)))
	assert_true(s.has("L: 6 points to spend"))
	w.player.stat_points = 1
	assert_true(HudPanel.build(w, style).strings().has("L: 1 point to spend"))
	w.exit_sealed = true
	assert_true(HudPanel.build(w, style).strings().has("Exit sealed: beat the Headliner"))
	w.exit_sealed = false
	w.gold = 1234
	assert_true(HudPanel.build(w, style).strings().has("1234"))   # gold has no thousands separator, as Python
	w.add_box("bronze", "x")
	w.add_box("bronze", "x")
	assert_true(HudPanel.build(w, style).strings().has("2xB"))
	assert_eq(HudPanel.stairs_line(w)[1], "TEXT_DIM")
	w.pet.downed = true
	assert_true(HudPanel.build(w, style).strings().has("DOWN: revive in a safe room"))
	var c := w.floor.safe_room.centre()
	w.player.x = c.x
	w.player.y = c.y
	var safe := HudPanel.build(w, style).strings()
	assert_true(safe.has("SAFE ROOM") and safe.has("R: rest   M: menu"))


func test_log_wraps_at_words_and_fades() -> void:
	var log := MessageLog.new()
	var long_text := " ".join(PackedStringArray(Array(range(60)).map(func(i: int) -> String: return "word%d" % i)))
	log.add(long_text)
	log.add("short")
	var lines := HudLog.wrapped(style, log, HudPlace.MAP_W - 24)
	assert_gt(lines.size(), 2)
	for l in lines:
		assert_lte(style.width("font", l[0]), HudPlace.MAP_W - 24)
	assert_true((lines[1][0] as String).begins_with("  ") or (lines[1][0] as String).begins_with("word"))
	assert_eq(lines[lines.size() - 1][0], "short")
	var back: Array = Content.table("ui_config")["colours"]["PANEL_BG"]
	assert_eq(HudLog.faded([200, 100, 50], back, 0), Color8(200, 100, 50))
	var f := HudLog.faded([200, 100, 50], back, 3)
	assert_eq(f.r8, int(200 * 0.7 + back[0] * 0.3))
	var many := MessageLog.new()
	for i in 20:
		many.add("line %d" % i)
	assert_eq(HudLog.wrapped(style, many, 1000).size(), HudPlace.LOG_LINES)


func test_theme_matches_the_config_colours_and_font() -> void:
	for n: String in Content.table("ui_config")["colours"]:
		assert_eq(style.colour(n), UiColours.c(n), n)
	assert_eq(style.face_size("font"), 15)
	assert_eq(style.face_size("small"), 13)
	assert_eq(style.face_size("big"), 22)
	assert_eq(style.face_size("huge"), 56)
	assert_eq(style.face_size("fp_big"), 18)                  # the first-person labels' own bold face
	assert_eq(style.font("fp_big"), style.font("big"))        # the same bold font file
	assert_eq([style.advance("small"), style.advance("font"), style.advance("big"), style.advance("huge")], [8, 9, 13, 34])
	assert_true(style.font("big").get_font_name().begins_with("DejaVu Sans Mono"))
	assert_eq(style.width("font", "abcd") % 4, 0)             # monospace, whole pixels


func test_end_screens_say_what_python_says() -> void:
	var a := _screen()
	var w: World = a[2]
	assert_eq(HudEnd.build(w, style).items.size(), 0)         # nothing while playing
	w.state = "dead"
	w.death_cause = "Eaten by a Knockoff Goblin on floor 1."
	var s := HudEnd.build(w, style).strings()
	assert_true(s.has("YOU DIED") and s.has("Eaten by a Knockoff Goblin on floor 1."))
	assert_true(s.has("Reached floor 1 of 6") and s.has("Seed 1"))
	assert_true(s.has("Enter: new run   R: run report   Esc: title"))
	w.state = "victory"
	s = HudEnd.build(w, style).strings()
	assert_true(s.has("YOU SURVIVED") and s.has("The ratings were... acceptable."))


func test_chevrons_name_the_side_and_the_shot_sits_on_screen() -> void:
	var a := _screen()
	var w: World = a[2]
	w.monsters.clear()
	var p := w.player
	var rect := HudPlace.map_rect()
	var m := Entities.spawn_monster("goblin", p.x + 1, p.y)    # east of you
	w.monsters.append(m)
	assert_eq(HudFp.chevrons(w, 90.0, rect, []).size(), 0)       # looking east: it is ahead
	assert_eq(HudFp.chevrons(w, 0.0, rect, [])[0]["text"], "RIGHT")
	assert_eq(HudFp.chevrons(w, 180.0, rect, [])[0]["text"], "LEFT")
	assert_eq(HudFp.chevrons(w, 270.0, rect, [])[0]["text"], "BEHIND YOU")
	assert_false(HudFp.chevrons(w, 0.0, rect, [])[0]["provoked"])
	assert_true(HudFp.chevrons(w, 0.0, rect, [m])[0]["provoked"])

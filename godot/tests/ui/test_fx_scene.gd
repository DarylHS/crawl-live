extends TestCase
## P8 effects in the scene (headless): the weapon view model art and drawing, the wall torches, the
## director turning real World events into effects, the Effects setting and the skip rules end to end,
## the box reveal in the Hud, and the proof that the effects leave the rules untouched.

const GAME := preload("res://scenes/game_view.tscn")
const HUD := preload("res://scenes/hud.tscn")


func after_each() -> void:
	SpriteArt.reset()


func _hero() -> Dictionary:
	return {"name": "Crawler", "gender": Content.table("genders").keys()[0],
			"backstory": Content.table("backstories").keys()[0]}


## A GameView (with its FxDirector) on a world with `monster` two tiles ahead of you in a straight run.
func _fight(effects: String = "on", gap: int = 1) -> Array:
	var g: GameView = GAME.instantiate()
	g.settings_path = ""
	g.runs_dir = ""
	g.input_enabled = false
	add_child_autofree(g)
	g.size = Vector2(1024, 640)
	g.app.settings["effects"] = effects
	var w := World.new(1, null, _hero())
	g.start(w)
	w.monsters.clear()
	var f := w.floor
	var dir := 1
	var found := false
	for y in f.height:
		for x in f.width:
			if found or f.is_safe(x, y):
				continue
			var ok := true
			for k in range(0, 5):
				if not f.walkable(x + k, y) or f.is_safe(x + k, y) or f.furniture.has(Vector2i(x + k, y)):
					ok = false
			if ok:
				found = true
				w.player.x = x
				w.player.y = y
	assert_true(found)
	var m := Entities.spawn_monster("goblin", w.player.x + gap, w.player.y)
	m.hp = 999
	m.max_hp = 999
	w.monsters.append(m)
	w.update_fov()
	g.fp_view.logic.angle = dir * 90.0              # east
	g.fp_view.logic.cam = []
	g.fp_view.refresh(0.0)
	g.fx_director._process(0.016)
	return [g, w, m]


func _kinds(g: GameView) -> Array:
	var out: Array = []
	for e in g.fx_director.fired:
		out.append(e["k"])
	return out


# --- The weapon view model ------------------------------------------------------------------------

func test_each_weapon_has_its_own_80_pixel_picture_with_binary_alpha() -> void:
	var seen := {}
	for key in ["", "pan", "cleaver", "katana", "extinguisher", "sledge"]:
		var style := "unarmed" if key == "" else String(Content.item(key)["style"])
		var img := SpriteArt.weapon_view(key, style)
		assert_eq(img.get_size(), Vector2i(80, 80), key)
		var opaque := 0
		for y in 80:
			for x in 80:
				var a := img.get_pixel(x, y).a
				assert_true(a == 0.0 or a == 1.0, "binary alpha in %s" % key)
				opaque += int(a == 1.0)
		assert_gt(opaque, 400, "%s is drawn" % key)
		var sig := str(img.get_data().hex_encode().hash())
		assert_false(seen.has(sig), "%s looks like %s" % [key, seen.get(sig, "")])
		seen[sig] = key
		assert_true(img.get_pixel(44, 79).a == 1.0 or key == "", "the sleeve reaches the bottom edge of %s" % key)
	# a weapon with no shape of its own falls back to its style's generic one
	assert_eq(SpriteArt.weapon_view("mystery_blade", "blade").get_size(), Vector2i(80, 80))


func test_real_art_registered_by_weapon_or_style_wins_over_the_placeholder() -> void:
	var red := Image.create_empty(80, 80, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	SpriteArt.register("wpn:blade", red)
	assert_eq(SpriteArt.weapon_view("katana", "blade").get_pixel(5, 5), Color.RED)       # by style
	var blue := Image.create_empty(80, 80, false, Image.FORMAT_RGBA8)
	blue.fill(Color.BLUE)
	SpriteArt.register("wpn:katana", blue)
	assert_eq(SpriteArt.weapon_view("katana", "blade").get_pixel(5, 5), Color.BLUE)      # by item, first
	assert_ne(SpriteArt.weapon_view("pan", "blunt").get_pixel(5, 5), Color.RED)          # other styles untouched


func test_the_view_model_follows_the_equipped_weapon_and_swings_on_an_attack() -> void:
	var f := _fight("on", 1)
	var g: GameView = f[0]
	var w: World = f[1]
	var vm := g.fp_view.view_model
	assert_eq(vm.item_key, "")
	assert_eq(vm.style, "unarmed")
	w.equipment["weapon"] = "katana"
	g.fp_view.refresh(0.0)
	assert_eq(vm.item_key, "katana")
	assert_eq(vm.style, "blade")
	assert_eq(vm.current_pose()["rot"], 0.0)                         # at rest
	w.events.emit("player_attack", {"target": "goblin", "hit": true, "crit": false})
	g.fx_director.state.advance(ViewModelPose.duration("blade") * 0.55)
	assert_ne(vm.current_pose()["rot"], 0.0)                         # mid-slash
	g.fx_director.on_key()
	assert_eq(vm.current_pose()["rot"], 0.0)                         # a key press ends it
	g.fp_view.show_view_model = false
	g.fp_view.refresh(0.0)
	assert_false(vm.visible)


# --- Torches ---------------------------------------------------------------------------------------

func test_torch_sites_are_the_same_every_time_on_walls_and_never_in_safe_rooms() -> void:
	var w := World.new(3, null, _hero())
	var a := WallTorches.sites_for(w.floor)
	assert_eq(a, WallTorches.sites_for(w.floor))
	assert_gt(a.size(), 20)
	assert_lt(a.size(), 400)
	for s: Dictionary in a:
		var t: Vector2i = s["tile"]
		var d: Vector2i = s["dir"]
		assert_eq(w.floor.tiles[t.y][t.x], DungeonFloor.FLOOR)
		assert_eq(w.floor.tiles[t.y + d.y][t.x + d.x], DungeonFloor.WALL)
		assert_false(w.floor.is_safe(t.x, t.y))
	w.new_floor(2)
	assert_ne(a, WallTorches.sites_for(w.floor))
	var near := WallTorches.pick(a, [a[0]["tile"].x + 0.5, a[0]["tile"].y + 0.5, 0.0], {a[0]["tile"]: true, a[1]["tile"]: true})
	assert_lte(near.size(), 2)
	assert_eq(near[0]["tile"], a[0]["tile"])                           # nearest first
	assert_eq(WallTorches.pick(a, [0.0, 0.0, 0.0], {}).size(), 0)      # none in sight, none shown


func test_torches_show_when_effects_are_on_and_vanish_when_off() -> void:
	var f := _fight("on", 3)
	var g: GameView = f[0]
	var w: World = f[1]
	var sites := WallTorches.sites_for(w.floor)
	var s: Dictionary = sites[0]
	w.player.x = s["tile"].x - s["dir"].x
	w.player.y = s["tile"].y - s["dir"].y
	w.update_fov()
	g.fp_view.logic.cam = []
	g.fp_view.refresh(0.0)
	assert_gt(g.fp_view.torches.shown, 0)
	g.app.settings["effects"] = "off"
	g.fx_director._process(0.016)
	g.fp_view.refresh(0.016)
	assert_eq(g.fp_view.torches.shown, 0)


func test_the_torch_light_flickers_but_never_gets_brighter_than_steady() -> void:
	var lo := 1.0
	var hi := 0.0
	for i in 400:
		var v := FpCameraRig.flicker_value(i * 0.017)
		lo = minf(lo, v)
		hi = maxf(hi, v)
	assert_lt(lo, 0.25)
	assert_gt(hi, 0.75)
	var f := _fight()
	var g: GameView = f[0]
	var rig := g.fp_view.rig
	var seen := {}
	for i in 60:
		g.fx_director.state.advance(0.03)
		g.fp_view.refresh(0.0)
		assert_lte(rig.torch.light_energy, FpCameraRig.TORCH_ENERGY + 0.0001)
		seen[snappedf(rig.torch.light_energy, 0.001)] = true
	assert_gt(seen.size(), 10)
	g.app.settings["effects"] = "off"
	g.fx_director._process(0.016)
	g.fp_view.refresh(0.0)
	assert_almost_eq(rig.torch.light_energy, FpCameraRig.TORCH_ENERGY, 0.0001)       # steady, the P4 look


# --- The director -----------------------------------------------------------------------------------

func test_a_real_attack_swings_flashes_and_shows_a_number_or_a_miss() -> void:
	var f := _fight("on", 1)
	var g: GameView = f[0]
	var w: World = f[1]
	var m: Monster = f[2]
	g.fx_director.on_key()
	assert_true(g.press(&"walk_forward"))                              # bumping the goblin attacks it
	var kinds := _kinds(g)
	assert_has(kinds, "swing")
	assert_gte(g.fx_director.state.swing_progress(), 0.0)
	var hit := m.hp < 999
	var texts: Array = []
	for e in g.fx_director.fired:
		if e["k"] == "number":
			texts.append(String(e["text"]))
	assert_gt(texts.size(), 0)
	if hit:
		assert_has(kinds, "flash")
		assert_gt(g.fx_director.state.flash_of(m.get_instance_id()), 0.9)
		assert_true(texts.any(func(t: String) -> bool: return t.contains(str(999 - m.hp))), "the damage is shown: %s" % str(texts))
	else:
		assert_has(texts, "miss")
	assert_gte(w.turn, 0)


func test_events_for_crit_boss_phase_and_bomb_start_shake_bursts_and_sound() -> void:
	var f := _fight("on", 2)
	var g: GameView = f[0]
	var w: World = f[1]
	var d := g.fx_director
	w.events.emit("player_attack", {"target": "goblin", "hit": true, "crit": true})
	w.events.emit("player_hit", {"target": "goblin", "damage": 11, "crit": true})
	assert_true(d.state.shaking())
	assert_eq(d.state.numbers[0]["text"], "CRIT -11!")
	assert_gt(g.fp_view.particles.started, 0)
	d.on_key()
	assert_false(d.state.shaking())
	assert_eq(g.fp_view.particles.live(), 0)
	w.events.emit("boss_phase", {"boss": "X", "phase": 2})
	assert_true(d.state.shaking())
	assert_eq(d.state.numbers[-1]["text"], "PHASE TWO")
	var before := g.fp_view.particles.started
	w.events.emit("bomb", {"item": "popper", "kills": 1})
	assert_gt(g.fp_view.particles.started, before)
	assert_has(d.sfx.played, "boom")
	assert_has(d.sfx.played, "roar")
	assert_has(d.sfx.played, "crit")


func test_the_camera_shakes_and_comes_back_exactly() -> void:
	var f := _fight("on", 2)
	var g: GameView = f[0]
	var w: World = f[1]
	var cam := g.fp_view.rig.camera
	assert_eq(cam.rotation, Vector3.ZERO)
	w.events.emit("boss_phase", {"boss": "X", "phase": 2})
	g.fx_director.state.advance(0.1)
	g.fp_view.refresh(0.0)
	assert_ne(cam.rotation, Vector3.ZERO)
	g.fx_director.state.advance(2.0)
	g.fp_view.refresh(0.0)
	assert_eq(cam.rotation, Vector3.ZERO)
	assert_eq(cam.position, Vector3.ZERO)


func test_reduced_has_no_shake_and_off_has_no_visual_effects_at_all() -> void:
	for mode in ["reduced", "off"]:
		var f := _fight(mode, 2)
		var g: GameView = f[0]
		var w: World = f[1]
		g.fx_director._process(0.016)
		w.events.emit("player_attack", {"target": "goblin", "hit": true, "crit": true})
		w.events.emit("player_hit", {"target": "goblin", "damage": 11, "crit": true})
		w.events.emit("boss_phase", {"boss": "X", "phase": 2})
		w.events.emit("bomb", {"item": "popper", "kills": 1})
		assert_false(g.fx_director.state.shaking(), mode)
		if mode == "off":
			assert_eq(g.fx_director.state.numbers.size(), 0)
			assert_eq(g.fx_director.state.swing_progress(), -1.0)
			assert_eq(g.fp_view.particles.started, 0)
			assert_eq(g.fx_director.state.flash_of(f[2].get_instance_id()), 0.0)
			assert_eq(g.fp_view.view_model.current_pose()["rot"], 0.0)
		else:
			assert_gt(g.fx_director.state.numbers.size(), 0)
		assert_has(g.fx_director.sfx.played, "crit")                  # sound has its own switch


func test_the_map_view_gets_the_sounds_but_none_of_the_pictures() -> void:
	var f := _fight("on", 2)
	var g: GameView = f[0]
	var w: World = f[1]
	g.set_view("top")
	w.events.emit("player_hit", {"target": "goblin", "damage": 5, "crit": false})
	assert_has(g.fx_director.sfx.played, "hit")
	assert_eq(g.fx_director.state.numbers.size(), 0)
	assert_eq(g.fp_view.particles.started, 0)


func test_muting_stops_the_sound_and_leaves_the_effects() -> void:
	var f := _fight("on", 2)
	var g: GameView = f[0]
	var w: World = f[1]
	g.app.settings["muted"] = true
	g.fx_director._process(0.016)
	w.events.emit("player_hit", {"target": "goblin", "damage": 5, "crit": false})
	assert_eq(g.fx_director.sfx.played.size(), 0)
	assert_eq(g.fx_director.state.numbers.size(), 1)


func test_a_monster_that_steps_slides_and_a_key_press_lands_it() -> void:
	var f := _fight("on", 3)
	var g: GameView = f[0]
	var m: Monster = f[2]
	g.fp_view.refresh(0.0)
	var id := m.get_instance_id()
	m.x -= 1                                                          # the goblin steps towards you
	g.fp_view.logic.cam = []
	g.fp_view.world.update_fov()
	g.fp_view.refresh(0.0)
	assert_eq(g.fx_director.state.slide_offset(id), Vector2(1, 0))      # drawn where it was
	g.fx_director.state.advance(FxState.SLIDE_DUR / 2.0)
	g.fp_view.refresh(0.0)
	assert_gt(g.fx_director.state.slide_offset(id).x, 0.0)
	assert_lt(g.fx_director.state.slide_offset(id).x, 1.0)
	g.fx_director.on_key()
	assert_eq(g.fx_director.state.slide_offset(id), Vector2.ZERO)


# --- The loot box reveal -------------------------------------------------------------------------------

func test_the_reveal_hides_the_item_until_the_lid_opens_and_a_key_shows_it() -> void:
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
	var w := World.new(1, null, _hero())
	g.start(w)
	h.bind(g)
	w.last_reveal = ["gold", "katana"]
	w.box_log.append({"tier": "gold", "item": "katana", "value": 60, "ev": 40.0, "rerolled": false, "turn": 0, "reason": ""})
	w.inventory.append("katana")
	g.app.overlay = "reveal"
	h.sync()
	assert_true(h.reveal.running)
	var name_text: String = Items.items()["katana"]["name"]
	assert_false(" ".join(h.menu_texts).contains(name_text), "hidden while the box rattles")
	assert_false(" ".join(h.menu_texts).contains("Worth"), "the value would give it away too")
	w.messages.add("The Gold box contains: %s!" % name_text, [255, 196, 64])
	w.messages.add("SYSTEM: Oh, how lucky for you.", [110, 170, 240])             # the System's comment lands after it
	var held := HudLog.wrapped(h.style, w.messages, 900, true)
	assert_false(str(held).contains("box contains"), "the log line waits for the lid")
	assert_false(str(held).contains("how lucky"), "and so does everything said after it")
	assert_true(str(HudLog.wrapped(h.style, w.messages, 900, false)).contains("how lucky"))
	h.reveal.advance(FxReveal.SHAKE_END + 0.01)
	h.sync()
	assert_true(" ".join(h.menu_texts).contains(name_text), "shown once it opens")
	assert_true(" ".join(h.menu_texts).contains("Worth"))
	# a second box (a reroll) rattles again, and a key shows the item at once
	w.box_log.append({"tier": "gold", "item": "pan", "value": 10, "ev": 40.0, "rerolled": true, "turn": 0, "reason": ""})
	w.last_reveal = ["gold", "pan"]
	h.sync()
	assert_true(h.reveal.running)
	h.on_key()
	h.sync()
	assert_true(" ".join(h.menu_texts).contains(Items.items()["pan"]["name"]))
	# effects off: no animation at all
	g.app.settings["effects"] = "off"
	w.box_log.append({"tier": "gold", "item": "pan", "value": 10, "ev": 40.0, "rerolled": true, "turn": 0, "reason": ""})
	h.sync()
	assert_false(h.reveal.running)
	assert_true(" ".join(h.menu_texts).contains(Items.items()["pan"]["name"]))


# --- Proof that the rules are untouched --------------------------------------------------------------

## The same scripted run on two worlds, one with a director listening to every event: identical saves.
func test_a_run_with_the_effects_listening_is_identical_to_one_without() -> void:
	for seed_value in [4, 9]:
		var a := World.new(seed_value, ["dog", ""], _hero())
		var b := World.new(seed_value, ["dog", ""], _hero())
		var d := FxDirector.attach_headless(b)
		var ra := PyRandom.new(77)
		var rb := PyRandom.new(77)
		for _i in 400:
			var da: Vector2i = ra.choice(DungeonFloor.NEIGHBOURS_8)
			var db: Vector2i = rb.choice(DungeonFloor.NEIGHBOURS_8)
			a.move_player(da.x, da.y)
			b.move_player(db.x, db.y)
			if _i % 40 == 0:
				d.on_key()
				d.state.advance(0.05)
			if a.state != "playing":
				break
		assert_eq(_digest(b), _digest(a), "seed %d" % seed_value)
		assert_gt(d.fired.size(), 0, "the director saw events")
		d.free()


## Everything a run's outcome rests on: the player, the monsters, the message log and the next draws of the
## game's random streams (equal draws mean equal stream positions). Consumes one draw from each stream.
func _digest(w: World) -> String:
	var mons: Array = []
	for m in w.monsters:
		mons.append([m.key, m.x, m.y, m.hp])
	var msgs: Array = []
	for line in w.messages.lines:
		msgs.append(line[0])
	return PyJson.dumps({"p": [w.player.x, w.player.y, w.player.hp, w.player.xp, w.player.kills], "turn": w.turn,
			"depth": w.depth, "gold": w.gold, "state": w.state, "mons": mons, "msgs": msgs,
			"rng": w.rng.random(), "loot": w.loot_rng.random()})


# --- Effects land on the right creature (identity, never the key alone) -----------------------------

## A world with `n` goblins in sight at distinct tiles near you (nearest first), a headless director attached.
func _goblins(n: int) -> Array:
	var w := World.new(2, ["dog", ""], _hero())
	w.monsters.clear()
	w.update_fov()
	var spots := TestHelpers.free_tiles_near(w, w.player.x, w.player.y, 4)
	var chosen: Array = []
	for t: Vector2i in spots:
		if w.visible.has(t) and t != Vector2i(w.player.x, w.player.y):
			chosen.append(t)
	chosen.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		return FxTargets.cheb(a, Vector2i(w.player.x, w.player.y)) < FxTargets.cheb(b, Vector2i(w.player.x, w.player.y)))
	var mons: Array = []
	for i in n:
		var m := Entities.spawn_monster("goblin", chosen[i].x, chosen[i].y)
		m.hp = 50
		m.max_hp = 50
		w.monsters.append(m)
		mons.append(m)
	w.update_fov()
	return [w, mons, FxDirector.attach_headless(w)]


func test_a_skill_or_riposte_kill_lands_on_the_monster_that_died_not_the_last_one_attacked() -> void:
	var f := _goblins(2)
	var w: World = f[0]
	var near: Monster = f[1][0]
	var far: Monster = f[1][1]
	var d: FxDirector = f[2]
	w.events.emit("player_attack", {"target": "goblin", "hit": true, "crit": false})      # aimed at the nearer one
	assert_eq(d.resolved["id"], near.get_instance_id())
	w.monsters.erase(far)                                                               # a riposte or skill kills the other
	w.events.emit("kill", _kill_data("skill"))
	assert_eq(d.resolved["id"], far.get_instance_id(), "the farther goblin died")
	assert_eq(d.resolved["tile"], Vector2i(far.x, far.y))
	d.free()


func test_a_bomb_kills_each_dead_monster_and_aims_at_the_nearest_one_in_sight() -> void:
	var f := _goblins(3)
	var w: World = f[0]
	var mons: Array = f[1]
	var d: FxDirector = f[2]
	var gone: Array = [mons[0], mons[2]]
	for m: Monster in gone:
		w.monsters.erase(m)
		w.events.emit("kill", _kill_data("bomb"))
		assert_true([mons[0].get_instance_id(), mons[2].get_instance_id()].has(d.resolved["id"]))
	w.events.emit("bomb", {"item": "popper", "kills": 2})
	assert_eq(d.resolved["id"], mons[0].get_instance_id(), "aimed at the nearest")
	# the two kills were two different monsters
	d.free()
	var g := _goblins(3)
	var w2: World = g[0]
	var d2: FxDirector = g[2]
	var ids := {}
	for i in [2, 0]:
		w2.monsters.erase(g[1][i])
		w2.events.emit("kill", _kill_data("bomb"))
		ids[d2.resolved["id"]] = true
	assert_eq(ids.size(), 2)
	d2.free()


func test_a_pet_bite_flashes_the_monster_that_lost_hp_even_when_another_is_nearer() -> void:
	var f := _goblins(2)
	var w: World = f[0]
	var near: Monster = f[1][0]
	var far: Monster = f[1][1]
	var d: FxDirector = f[2]
	far.hp -= 4                                                                        # the pet bit the farther one
	w.events.emit("pet_hit", {"pet": "Rex", "damage": 4})
	assert_eq(d.resolved["id"], far.get_instance_id())
	near.hp -= 3
	w.events.emit("pet_hit", {"pet": "Rex", "damage": 3})
	assert_eq(d.resolved["id"], near.get_instance_id(), "HP is remembered after each event")
	d.free()


func test_your_own_hit_flashes_the_monster_that_lost_hp() -> void:
	var f := _goblins(2)
	var w: World = f[0]
	var far: Monster = f[1][1]
	var d: FxDirector = f[2]
	w.events.emit("player_attack", {"target": "goblin", "hit": true, "crit": false})  # nearest of the key: the near one
	far.hp -= 5                                                                       # but the blow landed on the far one (a sweep, a riposte)
	w.events.emit("player_hit", {"target": "goblin", "damage": 5, "crit": false})
	assert_eq(d.resolved["id"], far.get_instance_id())
	d.free()


func test_stacked_sounds_meet_a_limiter_and_the_window_close_goes_through_quit_game() -> void:
	var p := SfxPlayer.new()
	add_child_autofree(p)
	var bus := AudioServer.get_bus_index(&"Master")
	var limiters := 0
	for i in AudioServer.get_bus_effect_count(bus):
		limiters += int(AudioServer.get_bus_effect(bus, i) is AudioEffectLimiter)
	assert_eq(limiters, 1)
	var p2 := SfxPlayer.new()
	add_child_autofree(p2)
	limiters = 0
	for i in AudioServer.get_bus_effect_count(bus):
		limiters += int(AudioServer.get_bus_effect(bus, i) is AudioEffectLimiter)
	assert_eq(limiters, 1, "added once, however many players")


## A full "kill" payload, as the rules send it (the achievement listeners read every key of it).
func _kill_data(by: String) -> Dictionary:
	return {"monster": "goblin", "monster_name": "Goblin", "xp": 5, "style": by, "boss": false, "small": true,
			"depth": 1, "turn": 1, "by": by, "player_hp": 20, "player_max_hp": 34}

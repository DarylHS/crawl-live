extends SceneTree
## A scripted end-to-end run of the real main scene with real key events (pushed through the window's
## input pipeline, so they reach Main._unhandled_input exactly as typed keys do): title, character
## creation, pet pick, a few floors with the class picker and a sponsor offer, the safe-room menu (shop
## buy and sell, box odds, trade up, open, reroll, craft, rest), save and quit to the title, continue
## with L, the map view, and on to the victory screen, the run report and back to the title.
## Game state is only set up (teleporting next to the stairs or the safe room, boxes and gold) where
## walking there would need the whole dungeon explored; every action itself is a key press.
##
##   godot --headless --path godot -s res://tools/e2e_run.gd -- [--seed 1] [--shots DIR]
##   xvfb-run -a godot --path godot --rendering-driver opengl3 -s res://tools/e2e_run.gd -- --shots DIR
##
## Prints one line per step and "e2e: PASS" (exit 0) or the failed checks (exit 1). With --shots (needs a
## display) it saves the window after the main steps.

const K := preload("res://tools/key_events.gd")

var main: Main = null
var app: AppState = null
var failures: Array[String] = []
var shots_dir := ""
var step_no := 0


func _initialize() -> void:
	var args := Main._parse_args(OS.get_cmdline_user_args())
	shots_dir = args.get("shots", "")
	if shots_dir != "":
		DirAccess.make_dir_recursive_absolute(shots_dir)
	_run.call_deferred(int(args.get("seed", "1")))


func _check(ok: bool, what: String) -> void:
	print("e2e:   %s %s" % ["ok  " if ok else "FAIL", what])
	if not ok:
		failures.append(what)


func _say(what: String) -> void:
	print("e2e: %s" % what)


func _press(k: InputEventKey) -> void:
	root.push_input(k)
	await process_frame


func _keys(list: Array) -> void:
	for k in list:
		await _press(k)


func _type(text: String) -> void:
	for ch in text:
		await _press(K.letter(ch))


func _shot(shot_name: String) -> void:
	if shots_dir == "" or DisplayServer.get_name() == "headless":
		return
	for _i in 4:
		await RenderingServer.frame_post_draw
	step_no += 1
	root.get_texture().get_image().save_png(shots_dir.path_join("e2e_%02d_%s.png" % [step_no, shot_name]))


## Move to the Down key presses that put the safe-menu cursor on `action`.
func _choose(action: String) -> void:
	var idx := MenuModels.menu_actions(app.world).find(action)
	app.cursor = 0
	for _i in idx:
		await _press(K.key(KEY_DOWN))
	await _press(K.key(KEY_ENTER))


func _stand(x: int, y: int) -> void:
	var w := app.world
	w.player.x = x
	w.player.y = y
	w.update_fov()


func _quiet() -> void:
	var w := app.world
	w.monsters.clear()
	w.pet.downed = true
	w.player.max_hp = 99
	w.player.hp = 99


## Walk onto the stairwell (set up) and press ">" until the next floor, answering what pops up.
func _descend() -> void:
	var w := app.world
	_quiet()
	var from := w.depth
	var st: Vector2i = w.floor.stairs[0]
	_stand(st.x, st.y)
	w.has_key = true                                   # the Headliner's key opens the stairs early
	w.exit_sealed = false                              # and the last floor's boss is dealt with
	await _press(K.greater())
	_check(w.depth == from + 1 or w.state == "victory", "descended from floor %d" % from)
	await _handle_popups()


func _run(seed_value: int) -> void:
	main = (load("res://scenes/main.tscn") as PackedScene).instantiate()
	main.summary_on_headless = false
	var dir := "user://e2e/"
	DirAccess.make_dir_recursive_absolute(dir)
	DirAccess.remove_absolute(dir + "slot1.json")
	root.add_child(main)
	await process_frame
	app = main.app
	app.save_path = dir + "slot1.json"
	app.settings_path = ""
	app.runs_dir = ""
	app.seed_value = seed_value

	_say("title and character creation")
	_check(app.scene == "title", "starts on the title")
	await _shot("title")
	await _press(K.question())
	_check(app.show_help, "? opens the help")
	await _shot("help")
	await _press(K.question())
	await _press(K.key(KEY_ENTER))
	_check(app.scene == "identity", "Enter goes to character creation")
	await _type("Daz")
	await _press(K.key(KEY_RIGHT))
	await _shot("identity")
	await _press(K.key(KEY_ENTER))
	await _keys([K.key(KEY_DOWN), K.key(KEY_DOWN)])
	await _shot("backstory")
	await _press(K.key(KEY_ENTER))
	await _press(K.key(KEY_RIGHT))
	await _type("Rex")
	await _shot("pet_select")
	await _press(K.key(KEY_ENTER))
	var w := app.world
	_check(app.scene == "game" and w != null, "a run starts")
	_check(w.hero_name == "Daz" and w.pet.name == "Rex" and w.pet.species == "dog", "hero Daz with dog Rex")
	_check(main.game_view.visible and app.view == "fp", "the game shows in first-person")
	await _shot("game")

	_say("walking and the map view")
	w.monsters.clear()
	var turn := w.turn
	await _press(K.letter("w"))
	await _press(K.key(KEY_SPACE, " "))
	_check(w.turn > turn, "keys advance the game")
	await _press(K.key(KEY_TAB))
	_check(app.view == "top", "Tab switches to the map")
	await _shot("map")
	await _press(K.key(KEY_TAB))
	await _press(K.letter("i"))
	_check(app.overlay == "inventory", "I opens the inventory")
	await _shot("inventory")
	await _press(K.key(KEY_ESCAPE))
	await _press(K.letter("l"))
	await _shot("attributes")
	await _press(K.key(KEY_ENTER))
	_check(w.player.attrs["str"] == 11 or w.player.attrs["dex"] == 11 or w.player.stat_points < 6, "a point is spent")
	await _press(K.letter("l"))

	_say("the safe room")
	_quiet()
	var c := w.floor.safe_room.centre()
	_stand(c.x, c.y)
	w.gold = 300
	for _i in 4:
		w.add_box("bronze", "an end to end test")
	w.inventory.append_array(["sock", "mug"])
	w.player.hp = 5
	await _press(K.letter("m"))
	_check(app.overlay == "safe", "M opens the safe-room menu")
	await _shot("safe_menu")
	await _choose("shop")
	_check(app.overlay == "shop", "the shop opens")
	var gold := w.gold
	await _press(K.key(KEY_ENTER))
	_check(w.gold < gold, "a purchase costs gold")
	await _press(K.key(KEY_TAB))
	_check(app.shop_mode == "sell", "Tab switches to selling")
	await _shot("shop_sell")
	gold = w.gold
	await _press(K.key(KEY_ENTER))
	_check(w.gold > gold, "a sale pays gold")
	await _press(K.key(KEY_ESCAPE))
	await _choose("box")
	_check(app.overlay == "box" and app.box_tier == "bronze", "box odds show")
	await _shot("box_odds")
	await _press(K.letter("t"))
	_check(w.boxes.has("silver") and w.boxes.count("bronze") == 1, "three bronze trade up to a silver")
	await _press(K.key(KEY_ENTER))
	_check(app.overlay == "reveal", "the box opens to the reveal")
	await _shot("reveal")
	gold = w.gold
	await _press(K.letter("r"))
	_check(w.box_log.size() == 2 and w.gold < gold, "R rerolls for a fee")
	await _press(K.key(KEY_ENTER))
	_check(app.overlay == "safe", "keeping it returns to the menu")
	await _choose("craft")
	_check(app.overlay == "craft", "the bench opens")
	await _press(K.key(KEY_ENTER))
	_check(w.inventory.has("tonic") or w.inventory.size() > 0, "a craft is attempted")
	await _press(K.key(KEY_ESCAPE))
	await _choose("rest")
	_check(app.overlay == "" and w.player.hp == w.player.max_hp, "resting heals to full")

	_say("save, quit to the title and continue")
	w.gold = 123
	await _press(K.letter("m"))
	await _choose("save")
	_check(app.scene == "title" and FileAccess.file_exists(app.save_path), "saved and back on the title")
	_check(not main.game_view.visible, "the game view is hidden on the title")
	await _shot("title_with_save")
	await _press(K.letter("l"))
	await process_frame
	await process_frame
	_check(app.scene == "game" and app.world.gold == 123 and app.world.hero_name == "Daz", "continue restores the run")
	await _shot("continued")
	w = app.world

	_say("floors, class picker and contracts")
	for _i in 5:
		await _descend()                               # floors 2 to 6; the class picker comes up on floor 3
	_check(w.cls != null, "race and class were chosen with the keys")
	await _shot("floor6")
	await _descend()                                   # the way out of floor 6
	_check(w.state == "victory", "the run ends in victory (floor %d)" % w.depth)
	await _shot("victory")
	await _press(K.letter("r"))
	_check(app.overlay == "report", "R opens the run report")
	await _shot("report")
	await _press(K.key(KEY_ESCAPE))
	await _press(K.key(KEY_ESCAPE))
	_check(app.scene == "title", "Esc goes back to the title")
	app.handle_key(K.key(KEY_ESCAPE))                  # (a real Esc would quit this script at once)
	_check(not app.running, "Esc on the title quits")

	main.queue_free()
	if failures.is_empty():
		print("e2e: PASS")
		quit(0)
	else:
		print("e2e: FAILED %d checks" % failures.size())
		quit(1)


## Answer a sponsor offer (Y) and the race / class picker (second row of each) with real keys.
func _handle_popups() -> void:
	for _i in 4:
		if app.overlay == "contract":
			await _press(K.letter("y"))
		elif app.overlay == "class":
			await _keys([K.key(KEY_DOWN), K.key(KEY_ENTER), K.key(KEY_DOWN), K.key(KEY_ENTER)])
		else:
			break

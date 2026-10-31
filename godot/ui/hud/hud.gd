class_name Hud
extends Control
## The game screen's HUD (scenes/hud.tscn; crawler/ui/hud.py `draw_game` and the first-person
## overlays): side panel, message log, initiative tracker, toasts, the combat banner, first-person
## chevrons and "ahead" label, and the death and victory overlays. It draws over a GameView.
##
## Scene tree (all HudCanvas nodes cover the 1280 x 768 window; each paints one list):
##   Hud (Control, this script, theme = crawl_theme.tres)
##     Panel      the side panel
##     Log        the message log
##     Chevrons   first-person side / behind warnings
##     Ahead      the "ahead" label (below any toasts)
##     Tracker    the initiative tracker with Move / Action / Bonus pips
##     Toasts     achievement toasts and the "COMBAT: roll for initiative" banner
##     End        the death / victory overlay
##     Menu       the title, creation screens or the open overlay menu (P7, from AppState)
##     TrackerOver  the tracker again, above the inventory's shade (Python draws it after the menu)
##     Help       the help overlay
##
## This node only wires things together each frame: it asks the models (HudPanel, HudLog, HudTracker,
## HudToasts, HudFp, HudEnd) what to show and hands the lists to the canvases. While `covered` (a menu
## or help is open) or the run has ended, the map-area overlays and the 3D minimap are hidden, as
## Python's `draw_game(hud=False)`; the panel and log stay. What the menu and help canvases show comes
## from the GameView's AppState (`scene`, `overlay`, `cursor`) through MenuModels, ScreenModels and
## ReportModel; the title and creation screens cover the whole window.

@onready var panel: HudCanvas = $Panel
@onready var log_canvas: HudCanvas = $Log
@onready var chevrons: HudCanvas = $Chevrons
@onready var ahead: HudCanvas = $Ahead
@onready var tracker: HudCanvas = $Tracker
@onready var toasts: HudCanvas = $Toasts
@onready var end: HudCanvas = $End
@onready var menu: HudCanvas = $Menu
@onready var tracker_over: HudCanvas = $TrackerOver
@onready var help: HudCanvas = $Help
@onready var reveal_canvas: RevealCanvas = $RevealCanvas

var style := HudStyle.new()
var game_view: GameView = null
var icons_auto: bool = false       ## P9: switch the menu pictures on while real art is active (Main sets it; tests and pairing tools leave it off)
var covered: bool = false          ## force the map-area overlays hidden (an open menu or help does so too)
var tracker_over_menu: bool = false   ## force the tracker over the menu (the open inventory does so too)
var menu_texts: PackedStringArray = PackedStringArray()   ## every string the menu canvas shows (tests)
var last_tracker := Rect2i()       ## the tracker box drawn last, an empty Rect2i when not shown
var last_toasts: Array[Rect2i] = []   ## the toast rectangles drawn last
var ahead_text: String = ""        ## the "ahead" label's text ("" when not shown)
var ahead_rect := Rect2i()         ## the "ahead" label's text rectangle
var _tracker_model := HudTracker.new()
var reveal := FxReveal.new()       ## the loot box opening animation (P8); hides the item for the first moments
var _reveal_id: int = -1           ## box_log size when the reveal started: a new box or a reroll starts it again


## Attach to the GameView this HUD draws for and draw once.
func bind(view: GameView) -> void:
	game_view = view
	sync()


func _process(delta: float) -> void:
	reveal.advance(delta)
	sync()


## A key is about to be handled: end the box animation at once (nobody waits for a box).
func on_key() -> void:
	reveal.skip()


## Bring every canvas up to date with the world and the view that is showing.
func sync() -> void:
	if icons_auto:
		style.icons = SpriteArt.has_art("item:tonic") and not game_view.plain
	var app := game_view.app if game_view != null else null
	var w: World = null if game_view == null else game_view.world
	var in_game := w != null and (app == null or app.scene == AppState.GAME)
	_sync_menus(app, w if in_game else null)
	if not in_game:
		for c: HudCanvas in [panel, log_canvas, chevrons, ahead, tracker, toasts, end, tracker_over]:
			c.show_list(null)
		last_tracker = Rect2i()
		last_toasts = []
		ahead_text = ""
		ahead_rect = Rect2i()
		return
	var is_covered := covered or (app != null and app.covered())
	var over_menu := tracker_over_menu or (app != null and app.overlay == "inventory")
	var playing := w.state == "playing"
	var overlays := playing and not is_covered
	game_view.fp_view.hud = overlays
	panel.show_list(HudPanel.build(w, style))
	var log_list := HudList.new(style)
	HudLog.build(log_list, w, reveal.item_hidden())
	log_canvas.show_list(log_list)
	last_tracker = Rect2i()
	last_toasts = []
	ahead_text = ""
	ahead_rect = Rect2i()
	var fp := game_view.view == "fp"
	var rect := HudPlace.map_rect()
	var chev_list := HudList.new(style)
	var ahead_list := HudList.new(style)
	var tracker_list := HudList.new(style)
	var over_list := HudList.new(style)
	var toast_list := HudList.new(style)
	if overlays:
		var logic := game_view.fp_view.logic
		var avoid: Array = [] if (fp or (w.combat == null and w.toasts.is_empty())) else actor_rects(w)
		var toast_rects := HudToasts.build(toast_list, w, avoid)
		last_toasts = toast_rects
		if fp:
			HudFp.build_chevrons(chev_list, w, logic, rect)
			var top := -1
			if not toast_rects.is_empty():
				top = 0
				for r in toast_rects:
					top = maxi(top, r.end.y)
				top += 8
			ahead_rect = HudFp.build_ahead(ahead_list, w, logic, rect, top)
			ahead_text = HudFp.ahead_text(w, logic)
		if w.combat != null:
			last_tracker = _tracker_model.build(tracker_list, w, rect, avoid if not fp else actor_rects(w))
	elif playing and over_menu and w.combat != null:
		last_tracker = _tracker_model.build(over_list, w, rect, actor_rects(w))
	chevrons.show_list(chev_list)
	ahead.show_list(ahead_list)
	tracker.show_list(tracker_list)
	tracker_over.show_list(over_list)
	toasts.show_list(toast_list)
	end.show_list(HudEnd.build(w, style))


## The menu and help canvases: the scene's screen (title, creation) or the open overlay over the game.
func _sync_menus(app: AppState, w: World) -> void:
	_sync_reveal(app, w)
	var list: HudList = null
	if app != null:
		match app.scene:
			AppState.TITLE:
				list = ScreenModels.build_title(style, SaveGame.has_save(app.save_path), app.loading)
			AppState.IDENTITY:
				list = ScreenModels.build_identity(style, app.hero_name, app.gender_idx)
			AppState.BACKSTORY:
				list = ScreenModels.build_backstory(style, app.backstory_idx)
			AppState.PET_SELECT:
				list = ScreenModels.build_pet_select(style, app.pet_idx, app.pet_name)
			_:
				if w != null:
					list = overlay_list(app, w)
	menu.show_list(list)
	menu_texts = list.strings() if list != null else PackedStringArray()
	help.show_list(ScreenModels.build_help(style, game_view.view) if app != null and app.show_help else null)


## Start the box animation when a reveal opens (or a reroll makes a new one), draw it while it runs.
func _sync_reveal(app: AppState, w: World) -> void:
	var on := app != null and w != null and app.overlay == "reveal" and w.last_reveal != null
	if not on:
		if reveal.running:
			reveal.skip()
		_reveal_id = -1
	elif w.box_log.size() != _reveal_id:
		_reveal_id = w.box_log.size()
		if FxSettings.profile(String(app.settings.get("effects", "on")))["reveal"]:
			reveal.start()
		else:
			reveal.skip()
	if on:
		var tier: String = w.last_reveal[0]
		var prof := FxSettings.profile(String(app.settings.get("effects", "on")))
		reveal_canvas.update_from(reveal, UiColours.of(Content.box(tier)["colour"]),
				Vector2(MenuModels.X0 + MenuModels.WIDTH / 2.0, 312.0), float(prof["particles"]))
	else:
		reveal_canvas.update_from(null, Color.WHITE, Vector2.ZERO, 0.0)


## The open overlay menu's list, or null when none is open.
func overlay_list(app: AppState, w: World) -> HudList:
	match app.overlay:
		"inventory":
			return MenuModels.build_inventory(style, w, app.cursor)
		"safe":
			return MenuModels.build_safe_menu(style, w, app.cursor)
		"reveal":
			return MenuModels.build_reveal(style, w, reveal.item_hidden()) if w.last_reveal != null else null
		"box":
			return MenuModels.build_box_info(style, w, app.box_tier)
		"shop":
			return MenuModels.build_shop(style, w, app.cursor, app.shop_mode)
		"contract":
			return MenuModels.build_contract(style, w) if PyMath.truthy(w.pending_offer) else null
		"report":
			return ReportModel.build(style, w)
		"skills":
			return MenuModels.build_practice(style, w)
		"attributes":
			return MenuModels.build_attributes(style, w, app.cursor)
		"craft":
			return MenuModels.build_craft(style, w, app.cursor)
		"class":
			return MenuModels.build_class_select(style, w, app.class_step, app.class_race, app.cursor)
	return null


## Screen rectangles that boxes over the map keep clear of: in the map view you, your pet and the
## monsters in sight (tile rectangles, `Renderer.actor_rects`); in first-person the pet and monsters
## in sight, projected with Camera3D.unproject_position (you are not on screen).
func actor_rects(w: World) -> Array:
	if game_view.view == "fp":
		var out: Array = [Rect2i(-100000, -100000, 0, 0)]       # avoid[0] is "you" in the map view: nobody here
		out.append_array(game_view.fp_view.actor_rects())
		return out
	var top := game_view.top_view
	var tile := top.tile_px
	var cam := TopView.camera(w, top.view_w, top.view_h)
	var ents: Array = [w.player]
	if w.active_pet != null:
		ents.append(w.active_pet)
	for m: Monster in w.monsters:
		if w.visible.has(Vector2i(m.x, m.y)):
			ents.append(m)
	var out: Array = []
	for e: Entity in ents:
		out.append(Rect2i((e.x - cam.x) * tile, (e.y - cam.y) * tile, tile, tile))
	return out



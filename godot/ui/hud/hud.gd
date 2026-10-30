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
##
## This node only wires things together each frame: it asks the models (HudPanel, HudLog, HudTracker,
## HudToasts, HudFp, HudEnd) what to show and hands the lists to the canvases. While `covered` (a menu
## or help is open, P7) or the run has ended, the map-area overlays and the 3D minimap are hidden, as
## Python's `draw_game(hud=False)`; the panel and log stay.

@onready var panel: HudCanvas = $Panel
@onready var log_canvas: HudCanvas = $Log
@onready var chevrons: HudCanvas = $Chevrons
@onready var ahead: HudCanvas = $Ahead
@onready var tracker: HudCanvas = $Tracker
@onready var toasts: HudCanvas = $Toasts
@onready var end: HudCanvas = $End

var style := HudStyle.new()
var game_view: GameView = null
var covered: bool = false          ## a menu or help hides the map-area overlays (P7 sets it)
var tracker_over_menu: bool = false   ## the inventory shows the tracker over its dimmed view (so you see the Bonus pip)
var last_tracker := Rect2i()       ## the tracker box drawn last, an empty Rect2i when not shown
var last_toasts: Array[Rect2i] = []   ## the toast rectangles drawn last
var ahead_text: String = ""        ## the "ahead" label's text ("" when not shown)
var ahead_rect := Rect2i()         ## the "ahead" label's text rectangle
var _tracker_model := HudTracker.new()


## Attach to the GameView this HUD draws for and draw once.
func bind(view: GameView) -> void:
	game_view = view
	sync()


func _process(_delta: float) -> void:
	sync()


## Bring every canvas up to date with the world and the view that is showing.
func sync() -> void:
	var w: World = null if game_view == null else game_view.world
	if w == null:
		for c: HudCanvas in [panel, log_canvas, chevrons, ahead, tracker, toasts, end]:
			c.show_list(null)
		return
	var playing := w.state == "playing"
	var overlays := playing and not covered
	game_view.fp_view.hud = overlays
	panel.show_list(HudPanel.build(w, style))
	var log_list := HudList.new(style)
	HudLog.build(log_list, w)
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
	elif playing and tracker_over_menu and w.combat != null:
		last_tracker = _tracker_model.build(tracker_list, w, rect, actor_rects(w))
	chevrons.show_list(chev_list)
	ahead.show_list(ahead_list)
	tracker.show_list(tracker_list)
	toasts.show_list(toast_list)
	end.show_list(HudEnd.build(w, style))


## Screen rectangles that boxes over the map keep clear of: in the map view you, your pet and the
## monsters in sight (tile rectangles, `Renderer.actor_rects`); in first-person the pet and monsters
## in sight, projected with Camera3D.unproject_position (you are not on screen).
func actor_rects(w: World) -> Array:
	if game_view.view == "fp":
		return game_view.fp_view.actor_rects()
	var tile := TopView.TILE
	var cam := TopView.camera(w)
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


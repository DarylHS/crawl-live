class_name HudPlace
extends RefCounted
## Layout constants shared by the HUD models (crawler/config.py and crawler/ui/hud.py) and the rule
## for where a box over the map goes (`Renderer._clear_spot`).

static var _layout: Dictionary = Content.table("ui_config")["layout"]
static var _hud: Dictionary = Content.table("ui_config")["hud"]
static var SCREEN_W: int = _layout["SCREEN_W"]
static var SCREEN_H: int = _layout["SCREEN_H"]
static var PANEL_W: int = _layout["PANEL_W"]
static var LOG_LINES: int = _layout["LOG_LINES"]
static var MAP_W: int = _layout["VIEW_W"] * _layout["TILE"]      ## 1024: the map or 3D view
static var MAP_H: int = _layout["VIEW_H"] * _layout["TILE"]      ## 640
static var TRACKER_W: int = _hud["TRACKER_W"]
static var TRACKER_ROWS: int = _hud["TRACKER_ROWS"]
static var COMBAT_TOAST_TURNS: int = _hud["COMBAT_TOAST_TURNS"]


## The map or 3D view's screen rectangle (Python MAP_RECT).
static func map_rect() -> Rect2i:
	return Rect2i(0, 0, MAP_W, MAP_H)


## The first candidate that covers none of `avoid`; avoid[0] (you) matters most, so otherwise the one
## that does not cover you and covers the fewest others. Rectangles that only touch do not cover.
static func clear_spot(candidates: Array, avoid: Array) -> Rect2i:
	var best: Rect2i = candidates[0]
	var best_cost := [true, 1 << 30]
	for c: Rect2i in candidates:
		var hits := 0
		var covers_first := false
		for i in avoid.size():
			if c.intersects(avoid[i]):
				hits += 1
				if i == 0:
					covers_first = true
		var cost := [covers_first, hits]
		if cost[0] != best_cost[0]:
			if best_cost[0] and not cost[0]:
				best = c
				best_cost = cost
		elif cost[1] < best_cost[1]:
			best = c
			best_cost = cost
	return best

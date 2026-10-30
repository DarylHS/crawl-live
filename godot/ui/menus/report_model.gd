class_name ReportModel
extends RefCounted
## The post-run report screen (crawler/ui/report.py `draw_report`): three small charts (damage taken
## by floor, loot box luck against average, viewers over time), the sponsor deals and a note. The
## numbers and sentences come from RunReport; this fills a HudList at pygame's layout, with the chart
## geometry (plot area, axes, bars, lines) computed here so a test can read it.

const GRID := Color(48.0 / 255.0, 45.0 / 255.0, 62.0 / 255.0)
const EXPECTED := Color(150.0 / 255.0, 146.0 / 255.0, 170.0 / 255.0)


## pygame `Rect.center`: integer halves.
static func _centre(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)


## A chart panel (frame, title, subtitle); returns the plot area inside it.
static func _panel(list: HudList, rect: Rect2i, title: String, subtitle: String) -> Rect2i:
	var st := list.style
	list.fill(rect, st.colour("PANEL_BG"))
	list.frame(rect, st.colour("WALL_DIM"), 1)
	list.text(title, rect.position.x + 14, rect.position.y + 10, st.colour("ACCENT"))
	list.text(subtitle, rect.position.x + 14, rect.position.y + 30, st.colour("TEXT_DIM"), "small")
	return Rect2i(rect.position.x + 50, rect.position.y + 60, rect.size.x - 70, rect.size.y - 95)


## A 1 px horizontal line from x0 to x1 inclusive, as pygame draws it.
static func _hline(list: HudList, x0: int, x1: int, y: int, colour: Color) -> void:
	list.fill(Rect2i(x0, y, x1 - x0 + 1, 1), colour)


static func _vline(list: HudList, x: int, y0: int, y1: int, colour: Color) -> void:
	list.fill(Rect2i(x, y0, 1, y1 - y0 + 1), colour)


## Grid lines at 0, half and the maximum, labelled on the left.
static func _axes(list: HudList, plot: Rect2i, ymax: int, thousands: bool = false) -> void:
	var st := list.style
	for frac in [0.0, 0.5, 1.0]:
		var yy := plot.end.y - PyMath.round_half_even(plot.size.y * frac)
		_hline(list, plot.position.x, plot.end.x, yy, GRID)
		var v: float = ymax * frac
		var label := PyFmt.thousands_fixed(v, 0) if thousands else PyFmt.fixed(v, 0)
		list.text(label, plot.position.x - 6 - st.width("small", label), yy - 7, st.colour("TEXT_DIM"), "small")


static func _bars(list: HudList, plot: Rect2i, pairs: Array, colour: Color) -> void:
	var st := list.style
	var top := 0
	for p: Array in pairs:
		top = maxi(top, int(p[1]))
	var ymax := RunReport.nice_max(top)
	_axes(list, plot, ymax)
	var n := maxi(1, pairs.size())
	var slot := float(plot.size.x) / n
	for i in pairs.size():
		var label: Variant = pairs[i][0]
		var v: int = pairs[i][1]
		var h := PyMath.round_half_even(float(plot.size.y) * v / ymax)
		var bx := plot.position.x + PyMath.round_half_even(i * slot + slot * 0.2)
		list.fill(Rect2i(bx, plot.end.y - h, maxi(2, PyMath.round_half_even(slot * 0.6)), h), colour)
		list.centred(str(label), bx + PyMath.round_half_even(slot * 0.3), plot.end.y + 12, st.colour("TEXT_DIM"), "small")


static func _line(list: HudList, plot: Rect2i, xs: Array, ys: Array, xmax: int, ymax: int, colour: Color,
		w: int = 2) -> void:
	if xs.size() < 2:
		return
	var pts := PackedVector2Array()
	for i in xs.size():
		pts.append(Vector2(plot.position.x + PyMath.round_half_even(float(plot.size.x) * xs[i] / maxi(1, xmax)),
				plot.end.y - PyMath.round_half_even(float(plot.size.y) * ys[i] / maxi(1, ymax))))
	list.polyline(pts, colour, w)


## The report for `world`. `rects` collects what tests check: "caption" (the loot box caption's
## second line, when there are boxes) and "plots" (the three chart panels).
static func build(st: HudStyle, world: World, rects: Dictionary = {}) -> HudList:
	var list := HudList.new(st)
	var data := RunReport.build(world)
	MenuKit.shade(list, 255)                 # fully opaque: the end screen mustn't show through
	var cx := HudPlace.SCREEN_W / 2
	list.centred("RUN REPORT", cx, 34, st.colour("ACCENT"), "big")
	var t: Dictionary = data["totals"]
	list.centred(RunReport.summary_line(t), cx, 64, st.colour("TEXT"), "small")
	rects["panels"] = []

	# 1. Damage taken by floor.
	var panel := Rect2i(40, 90, 380, 300)
	rects["panels"].append(panel)
	var plot := _panel(list, panel, "Damage taken by floor", "Where the run hurt most")
	_bars(list, plot, data["damage_by_floor"], st.colour("DANGER"))

	# 2. Loot boxes: expected vs realised value, cumulative.
	panel = Rect2i(450, 90, 380, 300)
	rects["panels"].append(panel)
	plot = _panel(list, panel, "Loot boxes: luck vs average", "Running total of gold value")
	plot.size.y -= 20                        # room for the two-line caption inside the panel
	var exp: Array = data["box_expected"]
	var got: Array = data["box_realised"]
	if not exp.is_empty():
		var top := 0.0
		for v: float in exp:
			top = maxf(top, v)
		for v: float in got:
			top = maxf(top, v)
		var ymax := RunReport.nice_max(top)
		_axes(list, plot, ymax)
		var xs: Array = range(exp.size() + 1)
		_line(list, plot, xs, [0] + exp, exp.size(), ymax, EXPECTED)
		_line(list, plot, xs, [0] + got, exp.size(), ymax, st.colour("ACCENT"), 3)
		var cap := RunReport.box_caption(exp, got)
		list.text(cap[0], plot.position.x - 36, plot.end.y + 6, st.colour("TEXT"), "small")
		rects["caption"] = list.text(cap[1], plot.position.x - 36, plot.end.y + 21, st.colour("TEXT"), "small")
		list.text("average", plot.end.x - 60, plot.position.y - 4, EXPECTED, "small")
		list.text("yours", plot.end.x - 60, plot.position.y + 12, st.colour("ACCENT"), "small")
	else:
		var c := _centre(plot)
		list.centred("No boxes opened this run.", c.x, c.y, st.colour("TEXT_DIM"), "small")

	# 3. Viewer curve.
	panel = Rect2i(860, 90, 380, 300)
	rects["panels"].append(panel)
	plot = _panel(list, panel, "Viewers over time", "Your score, turn by turn")
	var samples: Array = data["viewers"]
	var vmax := 0
	var xs2: Array = []
	var ys2: Array = []
	for p: Array in samples:
		vmax = maxi(vmax, int(p[1]))
		xs2.append(p[0])
		ys2.append(p[1])
	var ymax2 := RunReport.nice_max(vmax)
	_axes(list, plot, ymax2, true)
	var last_turn: int = samples[-1][0]
	_line(list, plot, xs2, ys2, last_turn, ymax2, st.colour("INFO"), 3)
	var hist: Array = world.showrunner.history
	for i in range(1, hist.size()):              # floor boundaries
		var xx := plot.position.x + PyMath.round_half_even(float(plot.size.x) * hist[i][0] / maxi(1, last_turn))
		_vline(list, xx, plot.position.y, plot.end.y, GRID)
	list.text("turns", plot.end.x - 30, plot.end.y + 12, st.colour("TEXT_DIM"), "small")

	# Contracts and notes.
	var y := 420
	list.text("Sponsor deals", 40, y, st.colour("ACCENT"))
	y += 26
	if data["contracts"].is_empty():
		list.text("None signed.", 40, y, st.colour("TEXT_DIM"), "small")
	else:
		for line: String in RunReport.contract_lines(data):
			list.text(line, 40, y, st.colour("TEXT"), "small")
			y += 20
	list.text(RunReport.notes_line(t), 40, maxi(y + 10, 500), st.colour("TEXT_DIM"), "small")
	list.centred("Enter or Esc: back", cx, HudPlace.SCREEN_H - 40, st.colour("TEXT_DIM"))
	return list

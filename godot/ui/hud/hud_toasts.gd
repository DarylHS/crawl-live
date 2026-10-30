class_name HudToasts
extends RefCounted
## Toasts over the map or 3D view (crawler/ui/hud.py `toast_layout` / `draw_toasts`): up to three
## recent banners stacked at the top, or at the bottom of the map when the top would hide you or a
## fighter. Achievement toasts last TOAST_TURNS turns; the "COMBAT: roll for initiative" banner
## lasts COMBAT_TOAST_TURNS (two rounds). World.toasts rows are [turn, text, tier] or
## [turn, text, tier, sub]; the rules already drop expired ones when a new one is added, and this
## prunes the rest at draw time.

const WIDTH := 420
const GAP := 6
const MARGIN := 10


## The toasts still showing, oldest first, at most three. A toast is up while
## world.turn - its turn < its lifetime.
static func live(world: World) -> Array:
	var out: Array = []
	for t: Array in world.toasts:
		var life := HudPlace.COMBAT_TOAST_TURNS if t[2] == "combat" else GameConfig.TOAST_TURNS
		if world.turn - int(t[0]) < life:
			out.append(t)
	return out.slice(maxi(0, out.size() - 3))


## [{toast, rect}] for the live toasts. `avoid` lists the screen rectangles to keep clear of
## (avoid[0] is you); with none the stack sits at the top.
static func layout(world: World, avoid: Array = []) -> Array:
	var toasts := live(world)
	var sizes: Array[int] = []
	var total := 0
	for t: Array in toasts:
		var h := 46 if t.size() > 3 and PyMath.truthy(t[3]) else 30
		sizes.append(h)
		total += h
	total += GAP * maxi(0, sizes.size() - 1)
	var x := (HudPlace.MAP_W - WIDTH) / 2
	var y := MARGIN
	if not toasts.is_empty():
		var top := Rect2i(x, MARGIN, WIDTH, total)
		var bottom := Rect2i(x, HudPlace.MAP_H - MARGIN - total, WIDTH, total)
		y = HudPlace.clear_spot([top, bottom], avoid).position.y
	var out: Array = []
	for i in toasts.size():
		out.append({"toast": toasts[i], "rect": Rect2i(x, y, WIDTH, sizes[i])})
		y += sizes[i] + GAP
	return out


## Draw the toasts into `list`; returns their rectangles.
static func build(list: HudList, world: World, avoid: Array = []) -> Array[Rect2i]:
	var rects: Array[Rect2i] = []
	var st := list.style
	for entry: Dictionary in layout(world, avoid):
		var toast: Array = entry["toast"]
		var rect: Rect2i = entry["rect"]
		var tier: String = toast[2]
		var sub: Variant = toast[3] if toast.size() > 3 else null
		rects.append(rect)
		list.fill(rect, st.colour("PANEL_BG"))
		var colour := st.colour("DANGER") if tier == "combat" else UiColours.of(Content.box(tier)["colour"])
		list.frame(rect, colour, 2)
		list.centred(toast[1], rect.position.x + rect.size.x / 2, rect.position.y + 15, st.colour("TEXT"))
		if PyMath.truthy(sub):
			list.centred(sub, rect.position.x + rect.size.x / 2, rect.position.y + 33, colour, "small")
	return rects

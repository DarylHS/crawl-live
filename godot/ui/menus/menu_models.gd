class_name MenuModels
extends RefCounted
## What each overlay menu lists and says (crawler/ui/menus.py): inventory, safe room, box odds and
## reveal, shop, crafting, class picker, sponsor offer, practice skills and attributes. Headless:
## each `build_*` fills a HudList in 1280 x 768 pixels at pygame's positions with pygame's wording,
## and the row helpers (`inventory_rows`, `menu_options`, `shop_rows`, `class_rows`) are what
## AppState moves its cursor over. The MenuCanvas only paints the list.

const X0 := MenuKit.X0
const WIDTH := MenuKit.WIDTH
## Shop buy columns: heading and x offset in the panel (the last one ends well inside the right edge).
const SHOP_COLS := [["Item", 30], ["Price", 200], ["Stock", 255], ["Forecast", 320],
		["Reorder at", 420], ["On order", 515]]
const ATTR_SOURCE_X := 300       ## where "bought 10, +2 ..." starts on the attributes screen
const INV_STATS_X := 304         ## where an item's stats start, clear of the longest name and tag
const PRACTICE_TEXT_X := 222     ## where a practice skill's effect and how it trains start


# --- Rows the cursor moves over -------------------------------------------------------------

## Selectable inventory rows as [where, ref, key]: equipped items first ("equip", slot), then the
## pack ("pack", index).
static func inventory_rows(world: World) -> Array:
	var rows: Array = []
	for slot: String in world.equipment:
		var key: Variant = world.equipment[slot]
		if PyMath.truthy(key):
			rows.append(["equip", slot, key])
	for i in world.inventory.size():
		rows.append(["pack", i, world.inventory[i]])
	return rows


## Safe-room menu entries as [action, tier ("" for none), label].
static func menu_options(world: World) -> Array:
	var opts: Array = [["rest", "", "Rest to full HP"]]
	if world.pet != null and world.pet.downed:
		opts.append(["revive", "", "Revive %s (%d min)" % [world.pet.name, GameConfig.PET_REVIVE_TURNS]])
	for tier: String in Loot.TIERS:
		var n := world.boxes.count(tier)
		if n > 0:
			opts.append(["box", tier, "%s boxes (x%d): odds, open, trade" % [Content.box(tier)["name"], n]])
	opts.append(["shop", "", "Shop (%d gold)" % world.gold])
	opts.append(["craft", "", "Crafting bench"])
	opts.append(["save", "", "Save and quit to title"])
	return opts


## The action names of the safe-room menu, in order (Python tests read `o[0]`).
static func menu_actions(world: World) -> Array:
	var out: Array = []
	for o: Array in menu_options(world):
		out.append(o[0])
	return out


## Shop rows: the item keys on sale in buy mode, the pack indices in sell mode.
static func shop_rows(world: World, mode: String) -> Array:
	if mode == "buy":
		return Shop.base_demand().keys()
	var out: Array = []
	for i in world.inventory.size():
		out.append(i)
	return out


## The race list in the first step of the class picker, the class list in the second.
static func class_rows(step: String) -> Array:
	return Content.table("races").keys() if step == "race" else Content.table("classes").keys()


# --- Small text helpers ---------------------------------------------------------------------

## Where a score comes from, short enough for the attributes panel.
static func attr_source(bought: int, score: int) -> String:
	var extra := score - bought
	return "bought %d" % bought + (", %s backstory/race/class" % PyFmt.signed_int(extra) if extra != 0 else "")


static func _item_colour(key: String) -> Color:
	return UiColours.of(Items.items()[key]["colour"])


## Python `f"{p:.0%}"`.
static func _percent(p: float) -> String:
	return PyFmt.fixed(p * 100.0, 0) + "%"


# --- Inventory ------------------------------------------------------------------------------

static func build_inventory(st: HudStyle, world: World, cursor: int) -> HudList:
	var list := HudList.new(st)
	MenuKit.frame(list, "INVENTORY")
	var rows := inventory_rows(world)
	var y := 140
	for i in rows.size():
		var row: Array = rows[i]
		var key: String = row[2]
		var it: Dictionary = Items.items()[key]
		if i == cursor:
			list.fill(Rect2i(X0 + 10, y - 2, WIDTH - 20, 22), MenuKit.SEL_COLOUR)
		var tag := "[%s]" % row[1] if row[0] == "equip" else ""
		list.text(Items.glyph(key), X0 + 22, y, _item_colour(key))
		list.text("%s %s" % [it["name"], tag], X0 + 46, y, st.colour("TEXT"))
		list.text(MenuKit.fit(st, Items.describe(key), WIDTH - INV_STATS_X - 14), X0 + INV_STATS_X, y,
				st.colour("TEXT_DIM"), "small")
		y += 24
	if rows.is_empty():
		list.text("Nothing but lint.", X0 + 46, y, st.colour("TEXT_DIM"))
	list.text("Pack %d/%d   Boxes %d" % [world.inventory.size(), GameConfig.INVENTORY_SIZE, world.boxes.size()],
			X0 + 22, 560, st.colour("TEXT_DIM"), "small")
	if not rows.is_empty() and cursor < rows.size():
		list.text(Items.items()[rows[cursor][2]]["desc"], X0 + 22, 585, st.colour("TEXT"), "small")
	list.centred("Up/Down select   Enter use/equip   U unequip   D drop   Esc close", X0 + WIDTH / 2, 625,
			st.colour("TEXT_DIM"), "small")
	return list


# --- Safe room ------------------------------------------------------------------------------

static func build_safe_menu(st: HudStyle, world: World, cursor: int) -> HudList:
	var list := HudList.new(st)
	MenuKit.frame(list, "SAFE ROOM", 160, 380)
	var y := 220
	var opts := menu_options(world)
	for i in opts.size():
		var o: Array = opts[i]
		if i == cursor:
			list.fill(Rect2i(X0 + 10, y - 2, WIDTH - 20, 26), MenuKit.SEL_COLOUR)
		var colour := UiColours.of(Content.box(o[1])["colour"]) if o[1] != "" else st.colour("TEXT")
		list.text(o[2], X0 + 30, y, colour)
		y += 30
	list.centred("Up/Down select   Enter choose   Esc close", X0 + WIDTH / 2, 510, st.colour("TEXT_DIM"), "small")
	return list


# --- Box reveal and odds ----------------------------------------------------------------------

static func build_reveal(st: HudStyle, world: World) -> HudList:
	var list := HudList.new(st)
	var tier: String = world.last_reveal[0]
	var key: String = world.last_reveal[1]
	var box := Content.box(tier)
	var box_colour := UiColours.of(box["colour"])
	MenuKit.frame(list, "%s BOX" % String(box["name"]).to_upper(), 180, 380)
	var it: Dictionary = Items.items()[key]
	var cx := X0 + WIDTH / 2
	if PyMath.truthy(world.last_reason):         # remind the player why they got this box
		var lines := MenuKit.wrap(st, "Earned for: %s" % world.last_reason, WIDTH - 60)
		for i in mini(2, lines.size()):
			list.centred(lines[i], cx, 232 + 17 * i, box_colour, "small")
	list.centred(Items.glyph(key), cx, 305, _item_colour(key), "huge")
	list.centred(it["name"], cx, 365, _item_colour(key), "big")
	list.centred(Items.describe(key), cx, 397, st.colour("TEXT"))
	list.centred(it["desc"], cx, 423, st.colour("TEXT_DIM"), "small")
	var stats := Loot.box_stats(tier)
	var ev: float = stats[0]
	var sd: float = stats[1]
	var v: int = it["value"]
	var verdict := "above" if v > ev else ("below" if v < ev else "exactly")
	list.centred("Worth %d gold: %s this box's average of %s (give or take %s)." % [
			v, verdict, PyFmt.fixed(ev, 1), PyFmt.fixed(sd, 1)], cx, 450, st.colour("TEXT"), "small")
	var fee := world.reroll_fee(tier)
	if world.inventory.has(key):
		list.centred("R: hand it back and reroll for %d gold (you have %d)." % [fee, world.gold], cx, 475,
				st.colour("TEXT_DIM"), "small")
		list.centred("A reroll pays on average only if this is worth under %s - %d = %s gold." % [
				PyFmt.fixed(ev, 1), fee, PyFmt.fixed(ev - fee, 1)], cx, 493, st.colour("TEXT_DIM"), "small")
	list.centred("Enter: keep it", cx, 525, st.colour("GOOD"))
	return list


## The odds disclosure: the real drop table, expected value and spread, before opening.
static func build_box_info(st: HudStyle, world: World, tier: String) -> HudList:
	var list := HudList.new(st)
	var box := Content.box(tier)
	var box_colour := UiColours.of(box["colour"])
	MenuKit.frame(list, "%s BOX" % String(box["name"]).to_upper(), 110, 520)
	list.centred("The System is legally required to show you the odds.", X0 + WIDTH / 2, 160,
			st.colour("TEXT_DIM"), "small")
	var y := 195
	list.text("Item", X0 + 40, y, st.colour("TEXT_DIM"), "small")
	list.text("Chance", X0 + 330, y, st.colour("TEXT_DIM"), "small")
	list.text("Worth", X0 + 470, y, st.colour("TEXT_DIM"), "small")
	y += 22
	var rows := Loot.odds(tier)
	var sorted := PyMath.stable_sort_by(rows, func(row: Array) -> float: return -row[1])
	for row: Array in sorted:
		var key: String = row[0]
		var p: float = row[1]
		var it: Dictionary = Items.items()[key]
		list.text(it["name"], X0 + 40, y, _item_colour(key))
		list.fill(Rect2i(X0 + 330, y + 4, 100, 10), st.colour("WALL_DIM"))
		list.fill(Rect2i(X0 + 330, y + 4, PyMath.round_half_even(100 * p), 10), box_colour)
		list.text(_percent(p), X0 + 436, y, st.colour("TEXT"), "small")
		list.text("%d gold" % it["value"], X0 + 470, y, st.colour("TEXT"), "small")
		y += 26
	var stats := Loot.box_stats(tier)
	var ev: float = stats[0]
	var sd: float = stats[1]
	y += 10
	list.text("Expected value %s gold, give or take %s." % [PyFmt.fixed(ev, 1), PyFmt.fixed(sd, 1)], X0 + 40, y,
			st.colour("TEXT"))
	list.text("('Give or take' is one standard deviation: most boxes land within it.)", X0 + 40, y + 20,
			st.colour("TEXT_DIM"), "small")
	y += 50
	var to := Loot.next_tier(tier)
	var have := world.boxes.count(tier)
	if to != "":
		var stats2 := Loot.box_stats(to)
		list.text("T: trade %d for one %s box (you have %d)." % [Loot.TRADE_UP_COST, Content.box(to)["name"], have],
				X0 + 40, y, st.colour("TEXT") if have >= Loot.TRADE_UP_COST else st.colour("TEXT_DIM"))
		list.text("In: %d x %s = %s gold.   Out: %s, give or take %s." % [
				Loot.TRADE_UP_COST, PyFmt.fixed(ev, 1), PyFmt.fixed(Loot.TRADE_UP_COST * ev, 1),
				PyFmt.fixed(stats2[0], 1), PyFmt.fixed(stats2[1], 1)], X0 + 40, y + 20, st.colour("TEXT_DIM"), "small")
	y += 56
	list.text("Rerolling a %s box after opening costs %d gold." % [box["name"], world.reroll_fee(tier)], X0 + 40, y,
			st.colour("TEXT_DIM"), "small")
	list.centred("Enter open   T trade up   Esc back", X0 + WIDTH / 2, 600, st.colour("TEXT_DIM"), "small")
	return list


# --- Shop -------------------------------------------------------------------------------------

static func build_shop(st: HudStyle, world: World, cursor: int, mode: String) -> HudList:
	var list := HudList.new(st)
	var shop := world.shop
	var remote := world.remote_shop and not world.in_safe_room
	MenuKit.frame(list, "SUPPLY DROP" if remote else "SAFE ROOM SHOP", 70, 600)
	var tabs := "BUY   sell" if mode == "buy" else "buy   SELL"
	list.centred("%s   (Tab to switch)     Your gold: %d" % [tabs, world.gold], X0 + WIDTH / 2, 120,
			st.colour("TEXT_DIM"), "small")
	var rows := shop_rows(world, mode)
	var y := 150
	if mode == "buy":
		for col: Array in SHOP_COLS:
			list.text(col[0], X0 + int(col[1]), y, st.colour("TEXT_DIM"), "small")
		y += 20
		for i in rows.size():
			var key: String = rows[i]
			var s: ShopStock = shop.stock[key]
			if i == cursor:
				list.fill(Rect2i(X0 + 10, y - 2, WIDTH - 20, 22), MenuKit.SEL_COLOUR)
			var out := s.on_hand == 0
			var price := world.buy_price(key)
			var it: Dictionary = Items.items()[key]
			var up := price > int(it["value"])
			list.text(it["name"], X0 + 30, y, st.colour("TEXT_DIM") if out else _item_colour(key), "small")
			list.text("%d" % price + ("*" if up else ""), X0 + int(SHOP_COLS[1][1]), y,
					st.colour("ACCENT") if up else st.colour("TEXT"), "small")
			list.text("OUT" if out else str(s.on_hand), X0 + int(SHOP_COLS[2][1]), y,
					st.colour("DANGER") if out else st.colour("TEXT"), "small")
			list.text("%s/floor" % PyFmt.fixed(s.forecast, 1), X0 + int(SHOP_COLS[3][1]), y, st.colour("TEXT"), "small")
			list.text(PyFmt.fixed(shop.reorder_point(key), 1), X0 + int(SHOP_COLS[4][1]), y, st.colour("TEXT"), "small")
			list.text(str(s.on_order) if s.on_order != 0 else "-", X0 + int(SHOP_COLS[5][1]), y, st.colour("TEXT"), "small")
			y += 24
		var cur_key: String = rows[cursor]
		var cs: ShopStock = shop.stock[cur_key]
		var item_name: String = Items.items()[cur_key]["name"]
		var notes: Array = [
			"Other crawlers buy about %s %ss a floor (forecast). Safety stock: %s." % [
					PyFmt.fixed(cs.forecast, 1), item_name, PyFmt.fixed(shop.safety_stock(cur_key), 1)],
			"Stock arrives one floor after it's ordered. When stock falls to the reorder point, "
			+ "the shop orders enough to cover two floors plus safety stock.",
			"* price is up because stock is low. Prices drop when deliveries land."]
		if not cs.history.is_empty():
			var last5: Array = cs.history.slice(maxi(0, cs.history.size() - 5))
			var texts: PackedStringArray = []
			for h in last5:
				texts.append(str(h))
			notes.insert(0, "Demand on recent floors: %s." % ", ".join(texts))
		y += 10
		for note: String in notes:
			for line in MenuKit.wrap(st, note, WIDTH - 60):
				list.text(line, X0 + 30, y, st.colour("TEXT_DIM"), "small")
				y += 17
			y += 4
	else:
		list.text("Item", X0 + 30, y, st.colour("TEXT_DIM"), "small")
		list.text("They pay", X0 + 330, y, st.colour("TEXT_DIM"), "small")
		y += 20
		for i: int in rows:
			var key: String = world.inventory[i]
			if i == cursor:
				list.fill(Rect2i(X0 + 10, y - 2, WIDTH - 20, 22), MenuKit.SEL_COLOUR)
			list.text(Items.items()[key]["name"], X0 + 30, y, _item_colour(key), "small")
			list.text("%d gold" % world.sell_price(key), X0 + 330, y, st.colour("TEXT"), "small")
			y += 22
		if rows.is_empty():
			list.text("Nothing to sell.", X0 + 30, y, st.colour("TEXT_DIM"), "small")
		list.text("The shop pays 40% of an item's value. Junk sells too.", X0 + 30, 600, st.colour("TEXT_DIM"), "small")
	list.centred("Up/Down select   Enter %s   Tab buy/sell   Esc back" % mode, X0 + WIDTH / 2, 650,
			st.colour("TEXT_DIM"), "small")
	return list


# --- Crafting ---------------------------------------------------------------------------------

static func build_craft(st: HudStyle, world: World, cursor: int) -> HudList:
	var list := HudList.new(st)
	MenuKit.frame(list, "CRAFTING BENCH", 140, 440)
	var recipes := Crafting.recipes()
	var y := 200
	for i in recipes.size():
		var rec: Dictionary = recipes[i]
		var ok := Crafting.can_craft(rec, world.inventory)
		if i == cursor:
			list.fill(Rect2i(X0 + 10, y - 2, WIDTH - 20, 44), MenuKit.SEL_COLOUR)
		var out: Dictionary = Items.items()[rec["makes"]]
		list.text("%s  ->  %s" % [rec["name"], out["name"]], X0 + 30, y,
				UiColours.of(out["colour"]) if ok else st.colour("TEXT_DIM"))
		var names: PackedStringArray = []
		for k: String in rec["needs"]:
			names.append(Items.items()[k]["name"])
		list.text("%s   %s" % [" + ".join(names), "ready" if ok else "missing parts"], X0 + 30, y + 20,
				st.colour("GOOD") if ok else st.colour("TEXT_DIM"), "small")
		y += 52
	list.text(recipes[cursor]["desc"], X0 + 30, 430, st.colour("TEXT"), "small")
	list.text("Each craft takes %d minutes of floor time." % Crafting.CRAFT_TURNS, X0 + 30, 455,
			st.colour("TEXT_DIM"), "small")
	list.centred("Up/Down select   Enter craft   Esc back", X0 + WIDTH / 2, 550, st.colour("TEXT_DIM"), "small")
	return list


# --- Class picker -----------------------------------------------------------------------------

## The two-column picker (race and class here, backstory in ScreenModels): names on the left, the
## selected one's details on the right. `detail` is a list of [text, colour, face] ("" = the
## default face); long lines wrap.
static func build_chooser(st: HudStyle, title: String, subtitle: String, names: Array, cursor: int,
		detail: Array, footer: String) -> HudList:
	var list := HudList.new(st)
	var x0 := 140
	var w := 1000
	var y0 := 70
	var h := 600
	MenuKit.shade(list)
	list.fill(Rect2i(x0, y0, w, h), st.colour("PANEL_BG"))
	list.frame(Rect2i(x0, y0, w, h), st.colour("WALL_LIT"), 1)
	list.centred(title, x0 + w / 2, y0 + 28, st.colour("ACCENT"), "big")
	list.centred(subtitle, x0 + w / 2, y0 + 56, st.colour("TEXT_DIM"), "small")
	var y := y0 + 90
	for i in names.size():
		if i == cursor:
			list.fill(Rect2i(x0 + 16, y - 3, 300, 26), MenuKit.SEL_COLOUR)
		list.text(names[i], x0 + 30, y, st.colour("ACCENT") if i == cursor else st.colour("TEXT"))
		y += 30
	list.fill(Rect2i(x0 + 336, y0 + 84, 1, h - 50 - 84 + 1), st.colour("WALL_DIM"))   # a 1 px line, both ends included
	y = y0 + 90
	for d: Array in detail:
		var face: String = d[2] if d[2] != "" else "font"
		var text: String = d[0]
		var lines: PackedStringArray = MenuKit.wrap(st, text, w - 400, face) if text != "" else PackedStringArray([""])
		for line in lines:
			list.text(line, x0 + 360, y, d[1], face)
			y += st.linesize(face) + 2
		y += 6
	list.centred(footer, x0 + w / 2, y0 + h - 28, st.colour("TEXT_DIM"), "small")
	return list


static func build_class_select(st: HudStyle, world: World, step: String, race: String, cursor: int) -> HudList:
	var rows := class_rows(step)
	var key: String = rows[cursor]
	var detail: Array = []
	var title := ""
	var names: Array = []
	if step == "race":
		var spec := Content.race(key)
		detail = [[spec["name"], st.colour("ACCENT"), "big"], [spec["desc"], st.colour("TEXT"), ""]]
		title = "CHOOSE YOUR RACE"
		for k: String in rows:
			names.append(Content.race(k)["name"])
	else:
		var spec := Content.klass(key)
		var sk := Content.skill(spec["skill"])
		var cd := "once per floor" if sk["cooldown"] >= 999 else "every %d turns" % sk["cooldown"]
		detail = [[spec["name"], st.colour("ACCENT"), "big"], [spec["desc"], st.colour("TEXT"), ""],
				["Skill (key 1): %s, %s" % [sk["name"], cd], st.colour("INFO"), ""],
				[sk["desc"], st.colour("TEXT_DIM"), ""]]
		if spec.get("pairs", []).has(world.backstory):
			detail.append(["Pairs well with your backstory: %s." % Content.backstory(world.backstory)["name"],
					st.colour("GOOD"), ""])
		title = "CHOOSE YOUR CLASS"
		for k: String in rows:
			names.append(Content.klass(k)["name"])
	var sub := "The System has decided you're interesting enough for a class."
	if race != "":
		sub += "  Race: %s." % Content.race(race)["name"]
	return build_chooser(st, title, sub, names, cursor, detail, "Up/Down select   Enter choose")


# --- Sponsor offer ----------------------------------------------------------------------------

## The sponsor offer. `rects` (when given) collects the rectangle of every line drawn, so tests
## can check the fit.
static func build_contract(st: HudStyle, world: World, rects: Array = []) -> HudList:
	var list := HudList.new(st)
	var c: Dictionary = Contracts.contracts()[world.pending_offer]
	MenuKit.frame(list, "SPONSOR OFFER", 150, 400)
	var cx := X0 + WIDTH / 2
	var y := 210
	for part in MenuKit.wrap(st, "%s presents: %s" % [c["sponsor"], c["name"]], WIDTH - 60, "font"):
		rects.append(list.centred(part, cx, y, st.colour("ACCENT")))
		y += 22
	y += 8
	for part in MenuKit.wrap(st, c["desc"], WIDTH - 60):
		rects.append(list.centred(part, cx, y, st.colour("TEXT"), "small"))
		y += 18
	y += 14
	rects.append(list.text("This floor only. What it means for you:", X0 + 40, y, st.colour("TEXT_DIM"), "small"))
	y += 22
	for line in Contracts.preview(world, world.pending_offer):
		for part in MenuKit.wrap(st, line, WIDTH - 90):
			rects.append(list.text(part, X0 + 50, y, st.colour("TEXT"), "small"))
			y += 18
		y += 4
	rects.append(list.centred("Y accept   N decline", cx, 520, st.colour("TEXT_DIM")))
	return list


# --- Practice skills and attributes -----------------------------------------------------------

## Practice skills: hidden until first used, then level, progress bar and effect.
static func build_practice(st: HudStyle, world: World) -> HudList:
	var list := HudList.new(st)
	MenuKit.frame(list, "PRACTICE SKILLS", 20, 728)
	var t := world.training
	var y := 66
	var group := ""
	var skills := Practice.skills()
	for key: String in skills:
		var sk: Dictionary = skills[key]
		if sk["group"] != group:
			group = sk["group"]
			list.text(group.to_upper(), X0 + 22, y + 4, st.colour("ACCENT"), "small")
			y += 24
		if not t.used.has(key):
			list.text("???", X0 + 22, y, st.colour("TEXT_DIM"))
			list.text("Not discovered yet", X0 + PRACTICE_TEXT_X, y + 1, st.colour("TEXT_DIM"), "small")
			y += 28
			continue
		var lvl: int = t.levels[key]
		list.text(sk["name"], X0 + 22, y, st.colour("TEXT"))
		list.text(str(lvl), X0 + 174 - st.width("font", str(lvl)), y, st.colour("ACCENT"))
		var bx := X0 + 180
		var bw := 32
		list.frame(Rect2i(bx, y + 4, bw, 8), st.colour("WALL_LIT"), 1)
		var frac := 1.0 if lvl >= Practice.MAX_LEVEL else float(t.xp[key]) / Practice.xp_to_next(lvl)
		if frac != 0.0:
			list.fill(Rect2i(bx + 1, y + 5, int((bw - 2) * frac), 6), st.colour("GOOD"))
		var room := WIDTH - PRACTICE_TEXT_X - 14
		list.text(MenuKit.fit(st, sk["effect"], room), X0 + PRACTICE_TEXT_X, y - 6, st.colour("TEXT"), "small")
		list.text(MenuKit.fit(st, sk["trains"], room), X0 + PRACTICE_TEXT_X, y + 8, st.colour("TEXT_DIM"), "small")
		y += 28
	list.centred("Skills level up by doing the thing. K or Esc to close", X0 + WIDTH / 2, 728,
			st.colour("TEXT_DIM"), "small")
	return list


## The five attributes: score, modifier, where it comes from and what it does.
static func build_attributes(st: HudStyle, world: World, cursor: int) -> HudList:
	var list := HudList.new(st)
	MenuKit.frame(list, "ATTRIBUTES", 90, 560)
	var p := world.player
	var y := 140
	var table := Attributes.table()
	var i := 0
	for key: String in table:
		var a: Dictionary = table[key]
		var score := world.score(key)
		if i == cursor:
			list.fill(Rect2i(X0 + 10, y - 4, WIDTH - 20, 52), MenuKit.SEL_COLOUR)
		list.text(a["name"], X0 + 24, y, st.colour("TEXT"))
		list.text("%d" % score, X0 + 200, y, st.colour("ACCENT"))
		list.text(Attributes.fmt_mod(Attributes.mod(score)), X0 + 240, y, st.colour("INFO"))
		list.text(attr_source(int(p.attrs[key]), score), X0 + ATTR_SOURCE_X, y + 2, st.colour("TEXT_DIM"), "small")
		list.text(a["does"], X0 + 24, y + 22, st.colour("TEXT_DIM"), "small")
		y += 58
		i += 1
	var pts: int = p.stat_points
	if pts != 0:
		list.text("%d point%s to spend" % [pts, "s" if pts != 1 else ""], X0 + 24, y + 4, st.colour("ACCENT"))
	else:
		list.text("No points to spend. You get 2 more each level.", X0 + 24, y + 4, st.colour("TEXT_DIM"))
	y += 34
	for line in ["HP %d   Armour Class %d   To hit %s   Damage %s" % [
				p.max_hp, p.ac, Attributes.fmt_mod(p.attack), p.damage_text()],
			"Proficiency %s (rises every 4 levels)   Bomb save DC %d" % [
				Attributes.fmt_mod(Attributes.proficiency(p.level)), world.save_dc()],
			"Modifier = (score - 10) / 2, rounded down. Every 2 points is +1."]:
		list.text(line, X0 + 24, y, st.colour("TEXT"), "small")
		y += 20
	list.centred("Up/Down select   Enter spend a point   L or Esc close", X0 + WIDTH / 2, 625,
			st.colour("TEXT_DIM"), "small")
	return list

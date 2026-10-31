class_name ScreenModels
extends RefCounted
## The full-screen scenes and the help overlay (crawler/ui/screens.py `draw_title`, `draw_help` and
## crawler/ui/menus.py `draw_identity`, `draw_backstory`, `draw_pet_select`): headless models that
## fill a HudList with pygame's layout and wording. The controls lists are data, so a test can read
## what the help says for each view.

## Help is split by view: movement differs, everything else is shared.
const TOP_CONTROLS := [
	["Arrows / WASD / numpad", "move, bump into monsters to attack"],
	["Numpad 7 9 1 3", "move diagonally"],
]
const FP_CONTROLS := [
	["W / Up", "walk where you look (hold); bumps what's ahead"],
	["S / Down", "walk back (hold)"],
	["A / D", "step left / right (strafe; hold)"],
	["Q / E, Left / Right", "turn: tap 45 degrees, hold to look (free)"],
	["Numpad", "move by the compass, 7 9 1 3 diagonally"],
	["In combat", "W / S / A / D step one tile, Q / E turn 90 degrees"],
	["W in combat", "attacks ahead, else front-left / front-right"],
]
const SHARED_CONTROLS := [
	[". / Space / numpad 5", "wait a turn; in combat, end your turn"],
	["> / Enter", "descend a stairwell"],
	["G", "pick up items on your tile"],
	["I", "inventory: use, equip, drop"],
	["R", "rest to full HP (safe rooms only)"],
	["M", "safe-room menu: boxes, shop, craft, revive, save"],
	["C", "command your pet: follow / attack / stay"],
	["K / L", "practice skills / attributes to spend points on"],
	["1", "use your class skill (from floor 3)"],
	["Tab", "switch view: first-person / map"],
	["?", "toggle this help"],
	["Esc", "close a menu, or quit to title"],
]
## Combat mode, the same in both views.
const COMBAT_CONTROLS := [
	["Combat turn", "one move, one action and one bonus action"],
	["Move / action", "a step / attack, bomb, skill, pick up, descend"],
	["Bonus action", "drink a potion (equip, drop, C and menus are free)"],
	["Leaving reach", "gives it a free swing (not swapping with your pet)"],
]
const VIEW_NAMES := {"fp": "first-person view", "top": "map view"}
const HELP_STEP := 22
const PREMISE := [
	"Earth has been 'repurposed'. You are now a contestant.",
	"Each floor collapses when its timer hits zero. Anyone still on it dies.",
	"Find a stairwell before then. Safe rooms let you rest, at the cost of time.",
	"Billions of viewers are watching. Try to be entertaining.",
]
const NAME_MAX := 16                  ## letters in a hero or pet name


## Help is centred on the map / 3D view, clear of the side panel.
static func help_cx() -> int:
	return HudPlace.MAP_W / 2


## The help list for a view: "fp" (first-person) or "top" (map), as [keys, what] rows.
static func controls(view: String) -> Array:
	var rows: Array = []
	rows.append_array(FP_CONTROLS if view == "fp" else TOP_CONTROLS)
	rows.append_array(SHARED_CONTROLS)
	rows.append_array(COMBAT_CONTROLS)
	return rows


## y of the first help row: the block (title to close line) centred on the map area.
static func help_top(rows: Array) -> int:
	return PyMath.floordiv(HudPlace.MAP_H - rows.size() * HELP_STEP, 2) + 20


## The help text as one string, for tests ("Q / E strafe ...").
static func help_text(view: String) -> String:
	var parts := PackedStringArray()
	for r: Array in controls(view):
		parts.append("%s %s" % [r[0], r[1]])
	return " ".join(parts)


static func build_help(st: HudStyle, view: String) -> HudList:
	var list := HudList.new(st)
	MenuKit.shade(list, 225)
	var cx := help_cx()
	var rows := controls(view)
	var y0 := help_top(rows)
	list.centred("CONTROLS", cx, y0 - 70, st.colour("ACCENT"), "big")
	list.centred("In the %s. Tab switches." % VIEW_NAMES.get(view, "map view"), cx, y0 - 40, st.colour("TEXT_DIM"))
	for i in rows.size():
		var r: Array = rows[i]
		var y := y0 + i * HELP_STEP
		var combat := COMBAT_CONTROLS.has(r) or String(r[0]).ends_with("n combat")
		list.text(r[0], cx - 20 - st.width("font", r[0]), y, st.colour("DANGER") if combat else st.colour("ACCENT"))
		list.text(r[1], cx + 20, y, st.colour("TEXT"))
	list.centred("Press ? to close", cx, y0 + rows.size() * HELP_STEP + 14, st.colour("TEXT_DIM"))
	return list


static func build_title(st: HudStyle, can_load: bool, loading: bool = false) -> HudList:
	var list := HudList.new(st)
	MenuKit.background(list)
	var cx := HudPlace.SCREEN_W / 2
	list.centred("CRAWL LIVE!", cx, 200, st.colour("ACCENT"), "huge")
	list.centred("The galaxy's favourite dungeon survival broadcast", cx, 252, st.colour("TEXT_DIM"))
	for i in PREMISE.size():
		list.centred(PREMISE[i], cx, 330 + i * 26, st.colour("TEXT"))
	list.centred("Press Enter to start", cx, 500, st.colour("GOOD"), "big")
	list.centred("? for controls   Esc to quit", cx, 534, st.colour("TEXT_DIM"))
	if loading:
		list.centred("Loading your saved run...", cx, 562, st.colour("INFO"))
	elif can_load:
		list.centred("L to continue your saved run", cx, 562, st.colour("INFO"))
	if st.icons:                                 # P9: credit the tile artists on the title (assets/CREDITS.md lists every file)
		list.centred("Art: Dungeon Crawl Stone Soup tiles (CC0), github.com/crawl/tiles   C for credits",
				cx, 728, st.colour("TEXT_DIM"), "small")
	return list


## The art credits screen (P9): the tile source and licence and the artists who signed their tiles over to CC0.
## Data from res://assets/credits.json (written by scripts/art_build.py), so an exported build needs no CREDITS.md.
static func build_credits(st: HudStyle) -> HudList:
	var list := HudList.new(st)
	MenuKit.background(list)
	var cx := HudPlace.SCREEN_W / 2
	var data := credits_data()
	list.centred("ART CREDITS", cx, 70, st.colour("ACCENT"), "big")
	var lines: Array = data.get("intro", [])
	for i in lines.size():
		list.centred(lines[i], cx, 112 + i * 20, st.colour("TEXT"), "small")
	var y0 := 112 + lines.size() * 20 + 22
	list.centred("The artists (Dungeon Crawl Stone Soup and RLTiles)", cx, y0, st.colour("ACCENT"))
	var names: Array = data.get("artists", [])
	var cols := 3
	var per := ceili(names.size() / float(cols))
	for i in names.size():
		list.text(names[i], 120 + (i / maxi(per, 1)) * 370, y0 + 28 + (i % maxi(per, 1)) * 19, st.colour("TEXT_DIM"), "small")
	list.centred("Fill-in art drawn for Crawl Live!, also CC0. Every picture's source: assets/CREDITS.md", cx, 708,
			st.colour("TEXT_DIM"), "small")
	list.centred("Esc to close", cx, 736, st.colour("GOOD"), "small")
	return list


static func credits_data() -> Dictionary:
	var path := "res://assets/credits.json"
	if FileAccess.file_exists(path):
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
		if parsed is Dictionary:
			return parsed
	return {"intro": ["Art from Dungeon Crawl Stone Soup (CC0), github.com/crawl/tiles."], "artists": []}


static func build_identity(st: HudStyle, hero_name: String, gender_idx: int) -> HudList:
	var list := HudList.new(st)
	MenuKit.background(list)
	var cx := HudPlace.SCREEN_W / 2
	list.centred("WHO ARE YOU?", cx, 150, st.colour("ACCENT"), "big")
	list.centred("The System needs a name for the death certificate.", cx, 182, st.colour("TEXT_DIM"))
	list.text("Name:", cx - 170, 252, st.colour("TEXT_DIM"))
	list.frame(Rect2i(cx - 110, 242, 300, 36), st.colour("WALL_DIM"), 1)
	var shown := (hero_name if hero_name != "" else "Crawler") + ("_" if hero_name != "" else "")
	list.text(shown, cx - 100, 247, st.colour("TEXT") if hero_name != "" else st.colour("TEXT_DIM"), "big")
	var genders: Dictionary = Content.table("genders")
	var keys := genders.keys()
	var box_w := 200
	var gap := 20
	var left := cx - PyMath.floordiv(keys.size() * box_w + (keys.size() - 1) * gap, 2)
	for i in keys.size():
		var x := left + i * (box_w + gap)
		var sel := i == gender_idx
		list.frame(Rect2i(x, 320, box_w, 56), st.colour("ACCENT") if sel else st.colour("WALL_DIM"), 2 if sel else 1)
		list.centred(genders[keys[i]]["name"], x + box_w / 2, 348, st.colour("ACCENT") if sel else st.colour("TEXT"))
	var addr: String = genders[keys[gender_idx]]["address"]
	list.centred("The System will call you '%s'. Cosmetic only: no stat differences." % addr, cx, 410,
			st.colour("TEXT_DIM"))
	list.centred("Type a name   Left/Right choose   Enter next   Esc back", cx, 520, st.colour("TEXT_DIM"))
	return list


static func build_backstory(st: HudStyle, cursor: int) -> HudList:
	var table: Dictionary = Content.table("backstories")
	var keys := table.keys()
	var b: Dictionary = table[keys[cursor]]
	var detail: Array = [[b["name"], st.colour("ACCENT"), "big"], [b["perk"], st.colour("GOOD"), ""],
			[b["desc"], st.colour("TEXT_DIM"), ""], ["", st.colour("TEXT"), ""],
			["Your life before the dungeon. It nudges your starting stats; your race and class come on floor 3.",
					st.colour("TEXT_DIM"), "small"]]
	var names: Array = []
	for k: String in keys:
		names.append(table[k]["name"])
	var list := HudList.new(st)
	MenuKit.background(list)
	var chooser := MenuModels.build_chooser(st, "CHOOSE YOUR BACKSTORY", "What were you doing when the world ended?",
			names, cursor, detail, "Up/Down select   Enter next   Esc back")
	list.items.append_array(chooser.items)
	return list


static func build_pet_select(st: HudStyle, species_idx: int, pet_name: String) -> HudList:
	var list := HudList.new(st)
	MenuKit.background(list)
	var cx := HudPlace.SCREEN_W / 2
	list.centred("PICK YOUR COMPANION", cx, 140, st.colour("ACCENT"), "big")
	list.centred("Every contestant gets one. It's in the contract.", cx, 172, st.colour("TEXT_DIM"))
	var pets: Dictionary = Content.table("pets")
	var keys := pets.keys()
	var box_w := 260
	var gap := 20
	var left := cx - PyMath.floordiv(keys.size() * box_w + (keys.size() - 1) * gap, 2)
	for i in keys.size():
		var spec: Dictionary = pets[keys[i]]
		var x := left + i * (box_w + gap)
		var sel := i == species_idx
		list.frame(Rect2i(x, 220, box_w, 220), st.colour("ACCENT") if sel else st.colour("WALL_DIM"), 2 if sel else 1)
		var mid := x + box_w / 2
		list.centred(spec["glyph"], mid, 270, UiColours.of(spec["colour"]), "huge")
		list.centred(spec["name"], mid, 325, st.colour("TEXT"), "big")
		var lines := MenuKit.wrap(st, spec["desc"], box_w - 24)
		for j in lines.size():
			list.centred(lines[j], mid, 355 + j * 17, st.colour("TEXT_DIM"), "small")
	var shown := pet_name if pet_name != "" else String(pets[keys[species_idx]]["default_name"])
	list.text("Name:", cx - 160, 480, st.colour("TEXT_DIM"))
	list.text(shown + ("_" if pet_name != "" else ""), cx - 100, 476,
			st.colour("TEXT") if pet_name != "" else st.colour("TEXT_DIM"), "big")
	list.centred("Left/Right choose   type a name   Enter start   Esc back", cx, 550, st.colour("TEXT_DIM"))
	return list

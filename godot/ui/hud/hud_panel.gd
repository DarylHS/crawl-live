class_name HudPanel
extends RefCounted
## The side panel (crawler/ui/hud.py `draw_panel`): title, hero, floor, collapse timer and bar,
## stairs state, HP and XP bars, attributes, armour, to-hit, damage, kills, gold, viewers, class
## skill, sponsor deal, pet, loot boxes, safe room / stairwell hints, the Scout Report and the
## help hint. Same order, spacing and wording as the pygame version; numbers use PyFmt where
## Python uses a format spec. `build` returns the HudList, every string visible to tests.


static func _bar(list: HudList, x: int, y: int, w: int, frac: float, colour: Color, label: String) -> void:
	var st := list.style
	list.fill(Rect2i(x, y, w, 16), st.colour("BAR_BACK"))
	list.fill(Rect2i(x, y, int(w * clampf(frac, 0.0, 1.0)), 16), colour)
	if label != "":
		list.centred(label, x + w / 2, y + 8, st.colour("TEXT"), "small")


## The timer colour for the fraction of the floor's time left: red at 10%, gold at 25%, else blue.
static func timer_colour(st: HudStyle, frac_left: float) -> Color:
	return st.colour("DANGER") if frac_left <= 0.1 else st.colour("ACCENT") if frac_left <= 0.25 else st.colour("INFO")


## The stairs line and its colour name: [text, colour name].
static func stairs_line(world: World) -> Array:
	if world.exit_sealed:
		return ["Exit sealed: beat the Headliner", "DANGER"]
	if world.stairs_locked:
		return ["Stairs unlock in %s" % world.timer_text(world.stairs_wait), "TEXT_DIM"]
	return ["Stairs open (key)" if world.has_key and world.stairs_wait != 0 else "Stairs open", "GOOD"]


static func build(world: World, st: HudStyle) -> HudList:
	var list := HudList.new(st)
	var x0 := HudPlace.MAP_W
	list.fill(Rect2i(x0, 0, HudPlace.PANEL_W, HudPlace.SCREEN_H), st.colour("PANEL_BG"))
	var x := x0 + 16
	var w := HudPlace.PANEL_W - 32
	var p := world.player
	var y := 14
	list.text("CRAWL LIVE!", x, y, st.colour("ACCENT"), "big")
	y += 28
	var who := world.hero_name
	if PyMath.truthy(world.backstory):
		who += ", " + Content.backstory(world.backstory)["name"]
	list.text(who, x, y, st.colour("TEXT_DIM"), "small")
	y += 20
	list.text("Floor %d of %d" % [world.depth, GameConfig.NUM_FLOORS], x, y, st.colour("TEXT"))
	y += 26

	var frac_left := float(world.timer) / float(world.timer_max)
	var tcol := timer_colour(st, frac_left)
	list.text("Floor collapses in", x, y, st.colour("TEXT_DIM"), "small")
	y += 16
	list.text(world.timer_text(), x, y, tcol, "big")
	y += 30
	_bar(list, x, y, w, frac_left, tcol, "")
	y += 20
	var stairs := stairs_line(world)
	list.text(stairs[0], x, y, st.colour(stairs[1]), "small")
	y += 22

	_bar(list, x, y, w, float(p.hp) / float(p.max_hp), st.colour("DANGER"), "HP %d/%d" % [p.hp, p.max_hp])
	y += 22
	_bar(list, x, y, w, float(p.xp) / float(p.xp_to_next()), st.colour("INFO"),
			"Level %d  XP %d/%d" % [p.level, p.xp, p.xp_to_next()])
	y += 30
	var attrs := Attributes.table()
	var col := w / attrs.size()
	var i := 0
	for key: String in attrs:
		var cx := x + i * col + col / 2
		var score := world.score(key)
		list.centred(attrs[key]["short"], cx, y + 6, st.colour("TEXT_DIM"), "small")
		list.centred(str(score), cx, y + 23, st.colour("TEXT"))
		list.centred(Attributes.fmt_mod(Attributes.mod(score)), cx, y + 40, st.colour("INFO"), "small")
		i += 1
	y += 52
	if p.stat_points != 0:
		list.text("L: %d point%s to spend" % [p.stat_points, "s" if p.stat_points != 1 else ""], x, y,
				st.colour("ACCENT"), "small")
		y += 18
	var rows: Array = [["Armour Class", str(p.ac)], ["To hit", Attributes.fmt_mod(p.attack)],
			["Damage", p.damage_text()], ["Kills", str(p.kills)], ["Gold", str(world.gold)],
			["Viewers", PyFmt.thousands(world.viewers)]]
	for row: Array in rows:
		list.text(row[0], x, y, st.colour("TEXT_DIM"))
		list.text(row[1], x + w - st.width("font", row[1]), y, st.colour("TEXT"))
		y += 20

	y += 4
	if PyMath.truthy(world.cls):
		var skill: Dictionary = Content.skill(world.skill)
		var ready := "%d turns" % world.skill_cooldown if world.skill_cooldown != 0 else "ready"
		list.text("%s %s" % [Content.race(world.race)["name"], Content.klass(world.cls)["name"]], x, y,
				st.colour("ACCENT"), "small")
		list.text("1: %s (%s)" % [skill["name"], ready], x, y + 16,
				st.colour("TEXT") if world.skill_cooldown == 0 else st.colour("TEXT_DIM"), "small")
		y += 36
	if PyMath.truthy(world.contract):
		list.text("Deal: %s" % Content.table("contracts")[world.contract]["name"], x, y, st.colour("ACCENT"), "small")
		y += 18
	var pet := world.pet
	if pet != null:
		var status := "DOWN: revive in a safe room" if pet.downed else "HP %d/%d   mode: %s" % [pet.hp, pet.max_hp, pet.mode]
		list.text("%s, L%d %s" % [pet.name, pet.level, Content.pet(pet.species)["name"]], x, y,
				UiColours.of(pet.colour), "small")
		list.text(status, x, y + 16, st.colour("DANGER") if pet.downed else st.colour("TEXT_DIM"), "small")
		y += 36

	if not world.boxes.is_empty():
		var x2 := x
		var tiers: Dictionary = Content.table("loot_boxes")
		for tier: String in tiers:
			var n: int = world.boxes.count(tier)
			if n != 0:
				var r := list.text("%dx%s" % [n, String(tiers[tier]["name"]).left(1)], x2, y,
						UiColours.of(tiers[tier]["colour"]), "small")
				x2 = r.end.x + 8
		y += 18
	y += 6
	if world.in_safe_room:
		list.text("SAFE ROOM", x, y, st.colour("GOOD"), "big")
		y += 26
		list.text("R: rest   M: menu", x, y, st.colour("TEXT_DIM"), "small")
		y += 16
	elif world.on_stairs:
		list.text("STAIRWELL", x, y, st.colour("ACCENT"), "big")
		y += 26
		list.text("> or Enter: descend", x, y, st.colour("TEXT_DIM"), "small")
		y += 16
	if world.scout_turns != 0:
		_scout(list, world, x, y + 14)

	list.text("? for all the controls", x, HudPlace.SCREEN_H - 26, st.colour("TEXT_DIM"), "small")
	return list


static func _scout(list: HudList, world: World, x: int, y: int) -> void:
	var st := list.style
	list.text(HudScout.title(world), x, y, st.colour("INFO"), "small")
	y += 18
	var rows := HudScout.rows(world)
	if rows.is_empty():
		list.text("Nothing in sight.", x, y, st.colour("TEXT_DIM"), "small")
	for row: Dictionary in rows:
		list.text(row["head"], x, y, UiColours.of(row["colour"]), "small")
		for k in 2:
			list.text(row["lines"][k], x, y + 15 + 14 * k, st.colour("TEXT_DIM"), "small")
		y += 48

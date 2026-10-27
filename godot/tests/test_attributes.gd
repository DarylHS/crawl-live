extends TestCase
## Attributes (port of tests/test_attributes.py): the modifier table (S2) and the World tests (S6).


func test_modifier_table() -> void:
	var mods: Array = []
	for s in [8, 9, 10, 11, 12, 14, 18]:
		mods.append(Attributes.mod(s))
	assert_eq(mods, [-1, -1, 0, 0, 1, 2, 4])
	var profs: Array = []
	for lvl in [1, 4, 5, 9, 13]:
		profs.append(Attributes.proficiency(lvl))
	assert_eq(profs, [2, 2, 3, 4, 5])


func test_constants_and_table() -> void:
	assert_eq(Attributes.START_POINTS, 6)
	assert_eq(Attributes.POINTS_PER_LEVEL, 2)
	assert_eq(Attributes.BASE_SCORE, 10)
	assert_eq(Attributes.MAX_SCORE, 30)
	assert_eq(Attributes.keys(), ["str", "dex", "con", "int", "cha"])
	assert_eq(Attributes.fmt_mod(2), "+2")
	assert_eq(Attributes.fmt_mod(0), "+0")
	assert_eq(Attributes.fmt_mod(-1), "-1")


# --- Ported with slice S6 (need World) ----------------------------------------------------------

func test_spending_points_raises_the_score_and_the_sheet() -> void:
	var w := World.new(1)
	var p := w.player
	assert_eq(p.stat_points, Attributes.START_POINTS)
	var hit := p.attack
	var dmg := p.dmg_bonus
	assert_true(w.spend_point("str") and w.spend_point("str"))          # 10 -> 12: +1
	assert_true(p.attack == hit + 1 and p.dmg_bonus == dmg + 1)
	var ac := p.ac
	assert_true(w.spend_point("dex") and w.spend_point("dex"))
	assert_eq(p.ac, ac + 1)
	var hp := p.max_hp
	assert_true(w.spend_point("con") and w.spend_point("con"))
	assert_true(p.max_hp == hp + p.level and p.hp == p.max_hp)          # extra HP arrives healed
	assert_true(p.stat_points == 0 and not w.spend_point("cha"))
	assert_false(w.spend_point("wisdom"))


func test_backstory_race_and_class_nudge_scores() -> void:
	var w := World.new(2, null, {"name": "T", "gender": "female", "backstory": "tradie"})
	assert_eq(w.score("str"), 12)
	w.choose_class("dwarf", "brawler")
	assert_true(w.score("str") == 16 and w.score("con") == 12 and w.score("dex") == 8)
	assert_eq(w.player.dmg_die, 8)                                      # Brawler fists are 1d8


func test_blades_use_the_better_of_str_and_dex() -> void:
	var w := World.new(3)
	for _i in range(4):
		w.spend_point("dex")                                            # DEX 14, STR 10
	w.inventory = ["cleaver"]
	w.equip(0)
	assert_gte(w.player.dmg_bonus, 2 + w.mod("dex"))
	w.inventory.append("pan")
	w.equip(0)                                                          # blunt: back to STR
	assert_eq(w.player.dmg_bonus, w.mod("str") + 2)


func test_heavy_armour_caps_dexterity() -> void:
	var w := World.new(4)
	for _i in range(6):
		w.spend_point("dex")                                            # DEX 16: +3
	w.inventory = ["plate"]
	w.equip(0)
	assert_eq(w.player.ac, 10 + 0 + 4)                                  # plate: no DEX bonus


func test_level_up_points_and_hp() -> void:
	var w := World.new(5)
	var p := w.player
	var hp := p.max_hp
	p.gain_xp(p.xp_to_next())
	w.refresh_stats()
	assert_eq(p.stat_points, Attributes.START_POINTS + 2)
	assert_gt(p.max_hp, hp)


func test_every_attribute_can_be_raised(attr = use_parameters(Attributes.keys())) -> void:
	var w := World.new(6)
	var before := w.score(attr)
	assert_true(w.spend_point(attr))
	assert_eq(w.score(attr), before + 1)


# --- parity with Python -----------------------------------------------------------------------

func test_modifier_and_proficiency_fixtures() -> void:
	if not S2Support.require(self):
		return
	for row in S2Support.rows("attrs"):
		assert_eq(Attributes.mod(row[0]), row[1], "mod(%d)" % row[0])
		assert_eq(Attributes.fmt_mod(Attributes.mod(row[0])), row[2])
	for row in S2Support.rows("proficiency"):
		assert_eq(Attributes.proficiency(row[0]), row[1], "proficiency(%d)" % row[0])
	var c = PyFixtures.decode(S2Support.doc()["tables"]["consts"])
	assert_eq([Attributes.BASE_SCORE, Attributes.START_POINTS, Attributes.POINTS_PER_LEVEL,
		Attributes.MAX_SCORE, Attributes.keys()], c)

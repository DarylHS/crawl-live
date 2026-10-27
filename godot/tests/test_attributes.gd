extends TestCase
## Attributes (port of tests/test_attributes.py, S2 part). The other tests there need World
## (spend_point, score, choose_class, equip, refresh_stats) and are ported with slice S6.


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


func test_world_dependent_tests_are_pending() -> void:
	pending("needs World (slice S6): spending_points, backstory_race_and_class, blades, heavy_armour, "
		+ "level_up_points_and_hp, every_attribute_can_be_raised")


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

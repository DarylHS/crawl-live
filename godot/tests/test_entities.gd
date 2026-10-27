extends TestCase
## Entity, Player, Monster, Pet and the factories (crawler/entities.py). No pytest file covers
## them directly (World tests exercise them), so these pin the behaviour and compare to_dict,
## stat blocks and tables with Python.


func after_each() -> void:
	TestHelpers.restore_patches()


func test_new_player_defaults() -> void:
	var p := Entities.new_player(5, 6)
	assert_eq(p.name, "Crawler")
	assert_eq(p.glyph, "@")
	assert_eq(p.colour, [255, 255, 255])
	assert_eq(p.max_hp, 0)
	assert_eq(p.hp, 0)
	assert_false(p.alive)
	assert_eq(p.attrs, {"str": 10, "dex": 10, "con": 10, "int": 10, "cha": 10})
	assert_eq(p.stat_points, 6)
	assert_eq(p.xp_to_next(), 30)


func test_xp_curve_and_level_ups() -> void:
	var p := Entities.new_player(0, 0)
	assert_eq(p.gain_xp(29), [])
	assert_eq(p.gain_xp(1), [2])
	assert_eq(p.xp, 0)
	assert_eq(p.xp_to_next(), 70)
	assert_eq(p.gain_xp(70 + 110 + 5), [3, 4])
	assert_eq(p.level, 4)
	assert_eq(p.xp, 5)
	assert_eq(p.stat_points, 6 + 6)


func test_pet_level_up_rules() -> void:
	var pet := Entities.new_pet("cat", "", 0, 0)
	assert_eq(pet.name, "Mittens")
	assert_eq(pet.xp_to_next(), 30)
	assert_eq(pet.gain_xp(30), [2])
	assert_eq([pet.max_hp, pet.hp, pet.dmg_bonus, pet.attack, pet.ac], [20, 16 + 4, 2, 5, 13])
	assert_eq(pet.gain_xp(65), [3])
	assert_eq(pet.ac, 14)
	assert_eq(Entities.new_pet("dog", "Rex", 1, 2).name, "Rex")


func test_take_damage_and_heal_clamp() -> void:
	var m := Entities.spawn_monster("gnawer", 1, 2)
	assert_eq(m.take_damage(4), 4)
	assert_eq(m.take_damage(10), 2)
	assert_false(m.alive)
	assert_eq(m.heal(3), 3)
	assert_eq(m.heal(100), 3)
	assert_eq(m.hp, m.max_hp)
	assert_eq(m.damage_text(), "1d4")
	assert_eq(Entities.spawn_monster("vacbot", 0, 0).damage_text(), "1d4+1")


func test_monster_names_take_articles_except_bosses() -> void:
	var m := Entities.spawn_monster("goblin", 0, 0)
	assert_eq([m.the, m.The, m.a], ["the Knockoff Goblin", "The Knockoff Goblin", "a Knockoff Goblin"])
	m.name = "Evil Wizard"
	assert_eq(m.a, "an Evil Wizard")
	m.boss = true
	assert_eq([m.the, m.The, m.a], ["Evil Wizard", "Evil Wizard", "Evil Wizard"])


func test_monster_table_follows_floor_bands_and_data_order() -> void:
	var t := Entities.monster_table(1)
	assert_eq(t[0], ["gnawer", "goblin"])
	assert_eq(t[1], [6, 5])
	assert_eq(Entities.monster_table(5)[0], ["brute", "cultist", "golem", "stalker"])
	assert_eq(Entities.monster_table(0), [[], []])


func test_spawn_monster_copies_row() -> void:
	var m := Entities.spawn_monster("cultist", 7, 8)
	assert_eq([m.x, m.y, m.key, m.xp_value, m.ranged, m.save, m.hp, m.max_hp], [7, 8, "cultist", 16, 5, 3, 16, 16])
	assert_eq([m.dmg_n, m.dmg_die, m.dmg_bonus, m.dr, m.attack, m.ac], [2, 4, 1, 0, 6, 12])
	# Colour is a copy: editing the entity must not edit the content table.
	m.colour[0] = 0
	assert_eq(Content.monster("cultist")["colour"][0], 190)


func test_init_mod_reads_optional_init_key() -> void:
	var goblin := Entities.spawn_monster("goblin", 0, 0)
	assert_eq(Entities.init_mod(goblin), 0)
	TestHelpers.patch_item(Content.monster("goblin"), "init", 50)
	assert_eq(Entities.init_mod(goblin), 50)
	var act := Entities.spawn_monster("gnawer", 0, 0)
	act.base = "goblin"
	assert_eq(Entities.init_mod(act), 50)
	var pet := Entities.new_pet("mouse", "", 0, 0)
	assert_eq(Entities.init_mod(pet), 0)
	TestHelpers.patch_item(Content.pet("mouse"), "init", 4)
	assert_eq(Entities.init_mod(pet), 4)
	var boss := Entities.spawn_monster("goblin", 0, 0)
	boss.tier = "headliner"
	boss.key = "boss_3"
	assert_eq(Entities.init_mod(boss), 0)
	TestHelpers.patch_item(Content.boss(3), "init", 7)
	assert_eq(Entities.init_mod(boss), 7)


func test_to_dict_from_dict_round_trip() -> void:
	var m := Entities.spawn_monster("brute", 1, 2)
	m.alerted = true
	m.tier = "featured"
	var back := Monster.from_dict(m.to_dict())
	assert_eq_deep(back.to_dict(), m.to_dict())
	var p := Entities.new_player(3, 4)
	p.attrs["str"] = 14
	var pb := Player.from_dict(p.to_dict())
	assert_eq_deep(pb.to_dict(), p.to_dict())
	assert_eq(pb.attrs["str"], 14)
	var pet := Entities.new_pet("budgie", "Polly", 0, 0)
	pet.downed = true
	assert_eq_deep(Pet.from_dict(pet.to_dict()).to_dict(), pet.to_dict())
	assert_eq(m.to_dict().keys().slice(0, 3), ["x", "y", "name"])


# --- parity with Python -----------------------------------------------------------------------

func test_hero_matches_python() -> void:
	if not S2Support.require(self):
		return
	assert_eq_deep(World.new(1).player.to_dict(), PyFixtures.decode(S2Support.doc()["tables"]["hero"]))


func test_from_dict_rejects_unknown_keys() -> void:
	var d := Entities.new_player(1, 2).to_dict()
	d["bogus"] = 1
	var p := Player.from_dict(d)
	assert_push_error("unexpected field 'bogus'")
	assert_eq(p.x, 1)


func test_tables_match_python() -> void:
	if not S2Support.require(self):
		return
	for row in S2Support.rows("monster_table"):
		assert_eq(Entities.monster_table(row[0]), row[1], "monster_table(%d)" % row[0])
	for row in S2Support.rows("stat_blocks"):
		var src: Dictionary = Entities.monsters() if Entities.monsters().has(row[0]) else Entities.pets()
		assert_eq(Entities.stat_block(src[row[0]]), row[1], row[0])
	for row in S2Support.rows("spawn"):
		var m := Entities.spawn_monster(row[0][1], 3, 4)
		assert_eq_deep(m.to_dict(), row[1], row[0][1])
		assert_eq(Entities.init_mod(m), row[2])
	for row in S2Support.rows("pets"):
		assert_eq_deep(Entities.new_pet(row[0], "", 3, 4).to_dict(), row[1], row[0])
		assert_eq_deep(Entities.new_pet(row[0], "Rex", 3, 4).to_dict(), row[2], row[0])
		assert_eq(Entities.init_mod(Entities.new_pet(row[0], "", 0, 0)), row[3])
	assert_eq_deep(Entities.new_player(5, 6).to_dict(), PyFixtures.decode(S2Support.doc()["tables"]["player"]))


class_name GameConfig
extends RefCounted
## Global constants from crawler/config.py (port plan 2.1): screen layout, colours and balance numbers.
##
## One static var per constant, initialised from the generated res://data/config.json ("config"
## section) through Content, so the numbers have a single source (scripts/export_content.py reads
## crawler/config.py). They are vars, not consts, so tests can patch them the way pytest's
## monkeypatch.setattr does: TestHelpers.patch_static(GameConfig, "MAP_W", 40). No rule may write
## to them. Colours stay [r, g, b] int Arrays (no Godot Color in the rules); the rules pass them
## through to MessageLog. Python tuples (TIMER_WARNINGS, HEADLINER_DROPS, colours) are Arrays.
##
## Other config sections (ai, bosses, shop, ...) belong to their modules and are read from Content.


## One value of the config section, copied so patching a Dictionary or Array here never edits the
## content cache.
static func _c(name: String) -> Variant:
	var v: Variant = Content.table("config")["config"][name]
	if v is Array:
		return (v as Array).duplicate(true)
	return v


# --- Layout ----------------------------------------------------------------
static var TILE: int = _c("TILE")
static var VIEW_W: int = _c("VIEW_W")  ## map area on screen, in tiles; the map scrolls to follow you
static var VIEW_H: int = _c("VIEW_H")  ## map area on screen, in tiles; the map scrolls to follow you
static var PANEL_W: int = _c("PANEL_W")
static var LOG_H: int = _c("LOG_H")
static var SCREEN_W: int = _c("SCREEN_W")  ## 1280
static var SCREEN_H: int = _c("SCREEN_H")  ## 768
static var FPS: int = _c("FPS")
static var LOG_LINES: int = _c("LOG_LINES")

# --- Dungeon ---------------------------------------------------------------
static var NUM_FLOORS: int = _c("NUM_FLOORS")
static var FOV_RADIUS: int = _c("FOV_RADIUS")
static var MAP_W: int = _c("MAP_W")  ## floor size in tiles (about 3.5x the screen)
static var MAP_H: int = _c("MAP_H")  ## floor size in tiles (about 3.5x the screen)
static var MAX_ROOMS: int = _c("MAX_ROOMS")
static var ROOM_MIN_W: int = _c("ROOM_MIN_W")
static var ROOM_MAX_W: int = _c("ROOM_MAX_W")
static var ROOM_MIN_H: int = _c("ROOM_MIN_H")
static var ROOM_MAX_H: int = _c("ROOM_MAX_H")
static var STAIRS_PER_FLOOR: int = _c("STAIRS_PER_FLOOR")
static var EXTRA_CORRIDORS: int = _c("EXTRA_CORRIDORS")  ## loops so the map isn't a pure chain
static var SAFE_W: int = _c("SAFE_W")  ## the safe room: small, enclosed, one doorway
static var SAFE_H: int = _c("SAFE_H")  ## the safe room: small, enclosed, one doorway

# --- Floor collapse timer (1 turn = 1 in-game minute) ----------------------
static var FLOOR_TURNS_BASE: int = _c("FLOOR_TURNS_BASE")  ## 12 hours on floor 1
static var FLOOR_TURNS_PER_DEPTH: int = _c("FLOOR_TURNS_PER_DEPTH")  ## deeper floors are bigger fights, so a bit more time
static var TIMER_WARNINGS: Array = _c("TIMER_WARNINGS")

# --- Wandering monsters ----------------------------------------------------
static var RESPAWN_START: int = _c("RESPAWN_START")  ## turns between arrivals when a floor opens...
static var RESPAWN_END: int = _c("RESPAWN_END")  ## ...shrinking to this as the timer runs down
static var RESPAWN_CAP: float = _c("RESPAWN_CAP")  ## never more than this times the floor's opening monster count
static var HEADLINER_DROPS: Array = _c("HEADLINER_DROPS")


static func floor_turns(depth: int) -> int:
	return FLOOR_TURNS_BASE + FLOOR_TURNS_PER_DEPTH * (depth - 1)

# --- Player & combat -------------------------------------------------------
static var PLAYER_BASE_HP: int = _c("PLAYER_BASE_HP")  ## plus the CON modifier per level; see World.refresh_stats
static var HP_PER_LEVEL: int = _c("HP_PER_LEVEL")
static var REGEN_INTERVAL: int = _c("REGEN_INTERVAL")  ## turns per 1 HP of natural regeneration
static var REST_MIN_TIMER: int = _c("REST_MIN_TIMER")  ## resting stops when the floor has this many turns left
static var MONSTER_LOSE_TRACK: int = _c("MONSTER_LOSE_TRACK")  ## turns out of sight before a monster gives up
static var MONSTER_WANDER_CHANCE: float = _c("MONSTER_WANDER_CHANCE")
static var RANGED_ATTACK_CHANCE: float = _c("RANGED_ATTACK_CHANCE")  ## chance a ranged monster in range shoots instead of closing in
static var PET_REVIVE_TURNS: int = _c("PET_REVIVE_TURNS")  ## floor time spent reviving a downed pet in a safe room

# --- Items & loot ----------------------------------------------------------
static var INVENTORY_SIZE: int = _c("INVENTORY_SIZE")
static var ITEM_DROP_CHANCE: float = _c("ITEM_DROP_CHANCE")  ## chance a dying monster drops something from its own pockets
static var FLOOR_ITEM_CHANCE: float = _c("FLOOR_ITEM_CHANCE")  ## chance each non-start room holds an item
static var BOMB_RANGE: int = _c("BOMB_RANGE")  ## how far away a bomb can be thrown
static var TOAST_TURNS: int = _c("TOAST_TURNS")  ## how long an achievement toast stays up
static var SASS_LEVEL: int = _c("SASS_LEVEL")  ## 0-10: how often the System picks its spicy lines, and how chatty it is
static var GOLD_PER_XP: float = _c("GOLD_PER_XP")  ## average gold per point of monster XP

# --- Colours ---------------------------------------------------------------
static var BG: Array = _c("BG")
static var PANEL_BG: Array = _c("PANEL_BG")
static var TEXT: Array = _c("TEXT")
static var TEXT_DIM: Array = _c("TEXT_DIM")
static var ACCENT: Array = _c("ACCENT")  ## gold: stairs, headings
static var DANGER: Array = _c("DANGER")
static var WARN: Array = _c("WARN")  ## a step that would provoke an attack of opportunity
static var GOOD: Array = _c("GOOD")
static var INFO: Array = _c("INFO")
static var WALL_LIT: Array = _c("WALL_LIT")
static var WALL_DIM: Array = _c("WALL_DIM")
static var FLOOR_LIT: Array = _c("FLOOR_LIT")
static var FLOOR_DIM: Array = _c("FLOOR_DIM")
static var SAFE_LIT: Array = _c("SAFE_LIT")
static var SAFE_DIM: Array = _c("SAFE_DIM")
static var PLAYER_COLOUR: Array = _c("PLAYER_COLOUR")


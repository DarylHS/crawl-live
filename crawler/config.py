"""Global constants: screen layout, colours and balance numbers.

Balance values live here so tuning never needs a code change elsewhere.
"""

# --- Layout -------------------------------------------------------------
TILE = 16
VIEW_W, VIEW_H = 64, 40            # map area on screen, in tiles; the map scrolls to follow you
PANEL_W = 256
LOG_H = 128
SCREEN_W = VIEW_W * TILE + PANEL_W  # 1280
SCREEN_H = VIEW_H * TILE + LOG_H    # 768
FPS = 30
LOG_LINES = 7

# --- Dungeon ------------------------------------------------------------
NUM_FLOORS = 6
FOV_RADIUS = 8
MAP_W, MAP_H = 120, 76        # floor size in tiles (about 3.5x the screen)
MAX_ROOMS = 44
ROOM_MIN_W, ROOM_MAX_W = 5, 12
ROOM_MIN_H, ROOM_MAX_H = 4, 9
STAIRS_PER_FLOOR = 3
EXTRA_CORRIDORS = 12         # loops so the map isn't a pure chain
SAFE_W, SAFE_H = 7, 5        # the safe room: small, enclosed, one doorway

# --- Floor collapse timer (1 turn = 1 in-game minute) -----------------
FLOOR_TURNS_BASE = 720       # 12 hours on floor 1
FLOOR_TURNS_PER_DEPTH = 60   # deeper floors are bigger fights, so a bit more time
TIMER_WARNINGS = (0.5, 0.25, 0.1)

# --- Wandering monsters -------------------------------------------------
RESPAWN_START = 45           # turns between arrivals when a floor opens...
RESPAWN_END = 15             # ...shrinking to this as the timer runs down
RESPAWN_CAP = 1.25           # never more than this times the floor's opening monster count
HEADLINER_DROPS = ("katana", "sledge", "plate", "elixir", "fireworks")


def floor_turns(depth: int) -> int:
    return FLOOR_TURNS_BASE + FLOOR_TURNS_PER_DEPTH * (depth - 1)


# --- Player & combat ----------------------------------------------------
PLAYER_BASE_HP = 34          # plus the CON modifier per level; see World.refresh_stats
HP_PER_LEVEL = 7
REGEN_INTERVAL = 7           # turns per 1 HP of natural regeneration
REST_MIN_TIMER = 60          # resting stops when the floor has this many turns left
MONSTER_LOSE_TRACK = 10      # turns out of sight before a monster gives up
MONSTER_WANDER_CHANCE = 0.25
RANGED_ATTACK_CHANCE = 0.6   # chance a ranged monster in range shoots instead of closing in
PET_REVIVE_TURNS = 30        # floor time spent reviving a downed pet in a safe room

# --- Items & loot -------------------------------------------------------
INVENTORY_SIZE = 16
ITEM_DROP_CHANCE = 0.25      # chance a dying monster drops something from its own pockets
FLOOR_ITEM_CHANCE = 0.30     # chance each non-start room holds an item
BOMB_RANGE = 6               # how far away a bomb can be thrown
TOAST_TURNS = 8              # how long an achievement toast stays up
SASS_LEVEL = 7                # 0-10: how often the System picks its spicy lines, and how chatty it is
GOLD_PER_XP = 0.5            # average gold per point of monster XP

# --- Colours ------------------------------------------------------------
BG = (12, 11, 16)
PANEL_BG = (22, 20, 30)
TEXT = (225, 222, 235)
TEXT_DIM = (130, 126, 145)
ACCENT = (255, 196, 64)      # gold: stairs, headings
DANGER = (235, 80, 80)
GOOD = (110, 210, 120)
INFO = (110, 170, 240)

WALL_LIT = (88, 80, 110)
WALL_DIM = (40, 37, 52)
FLOOR_LIT = (52, 48, 64)
FLOOR_DIM = (24, 22, 31)
SAFE_LIT = (42, 92, 64)
SAFE_DIM = (20, 42, 30)
PLAYER_COLOUR = (255, 255, 255)

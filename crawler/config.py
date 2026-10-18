"""Global constants: screen layout, colours and balance numbers.

Balance values live here so tuning never needs a code change elsewhere.
"""

# --- Layout -------------------------------------------------------------
TILE = 16
MAP_W, MAP_H = 64, 40
PANEL_W = 256
LOG_H = 128
SCREEN_W = MAP_W * TILE + PANEL_W  # 1280
SCREEN_H = MAP_H * TILE + LOG_H    # 768
FPS = 30
LOG_LINES = 7

# --- Dungeon ------------------------------------------------------------
NUM_FLOORS = 6
FOV_RADIUS = 8
MAX_ROOMS = 14
ROOM_MIN_W, ROOM_MAX_W = 5, 11
ROOM_MIN_H, ROOM_MAX_H = 4, 8
STAIRS_PER_FLOOR = 2
EXTRA_CORRIDORS = 3          # loops so the map isn't a pure chain

# --- Floor collapse timer (1 turn = 1 in-game minute) -----------------
FLOOR_TURNS_BASE = 720       # 12 hours on floor 1
FLOOR_TURNS_PER_DEPTH = 60   # deeper floors are bigger fights, so a bit more time
TIMER_WARNINGS = (0.5, 0.25, 0.1)


def floor_turns(depth: int) -> int:
    return FLOOR_TURNS_BASE + FLOOR_TURNS_PER_DEPTH * (depth - 1)


# --- Player & combat ----------------------------------------------------
PLAYER_START = dict(max_hp=36, power=5, defence=1, accuracy=0, evasion=0)
REGEN_INTERVAL = 7           # turns per 1 HP of natural regeneration
REST_MIN_TIMER = 60          # resting stops when the floor has this many turns left
BASE_HIT = 0.80
HIT_PER_POINT = 0.05
HIT_MIN, HIT_MAX = 0.05, 0.95
CRIT_CHANCE = 0.05
DAMAGE_SPREAD = 2            # base roll is power +/- this
MONSTER_LOSE_TRACK = 10      # turns out of sight before a monster gives up
MONSTER_WANDER_CHANCE = 0.25

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

# Crawl Live! Godot port plan

Status: P0 deliverable (port-architect). Reference: the frozen Python version at commit `db81dce` (Phase 7). Target: Godot 4.7.2 (official build, `/usr/local/bin/godot`), GDScript only.

This is the map for every later brief. Rules-porters translate `crawler/*.py` into `godot/rules/`, godot-dev builds `godot/scenes/` and `godot/ui/`, and the verifier checks each slice with the tests and parity traces described here. Owner decisions recorded in `PHASES.md` are taken as fixed; where this plan touches one, section 9 says so.

Contents

1. Ground rules for the port
2. Module map (Python to GDScript)
3. Python features that need care (with measured Godot 4.7.2 behaviour)
4. JSON content in `godot/data/`
5. RNG parity: `PyRandom` and every call site
6. Parity traces and the comparison script
7. Test framework: GUT (in place) and how tests run
8. Project layout, autoloads, headless runs, telemetry
9. Porting order: P1 and P2 slices
10. Presentation mapping (P4 to P7)
11. Risks, open questions and the parity verdict

Appendix A: measurements behind section 3. Appendix B: per-test-file mapping.

---

## 1. Ground rules for the port

- Faithful first. Same logic, same order of RNG calls, same iteration order, same numbers, same text. Python behaviour that looks wrong is ported as is and reported.
- Rules live in `godot/rules/` as `extends RefCounted` scripts with `class_name`, static typing where practical, and no Node, scene, autoload or `Engine`/`OS` dependency (file IO only in `save_game.gd`, `user_settings.gd`, `telemetry.gd`/`py_csv.gd` and `content.gd`). They run under `godot --headless`.
- All randomness goes through `PyRandom` (`godot/rules/py_random.gd`). Nothing in `rules/` may call `randi()`, `randf()`, `RandomNumberGenerator` or `hash()`, with one exception: `world.gd` picks a seed with `randi() & 0x3FFFFFFF` when none is given, as Python's `random.randrange(1 << 30)` does (it only chooses a seed, so parity is unaffected).
- All Python arithmetic idioms that differ in GDScript go through `PyMath` and all Python string formatting through `PyFmt` (section 3). A porter never writes a bare `/` between two ints, a bare `%` or `//` analogue on ints that may be negative, a bare `round()`, `sort_custom()` where Python used `sorted`/`.sort(key=)`, or `str()` on a float or bool that reaches the player, a log, a CSV or a save.
- Content is read from `godot/data/*.json` through `Content` and `GameConfig`. Never hand-edit data; change `scripts/export_content.py` and regenerate.
- Test seams are allowed when they change no behaviour: an optional `tap` Callable on `EventBus` and `MessageLog` (traces), and mutable `static var` config so tests can do what pytest's `monkeypatch` does. Each seam is listed where it is introduced.
- Australian spelling in player-facing text (it is copied from Python, so this is automatic), original names only.

---

## 2. Module map

Paths are relative to `godot/`. Every rules class is one file with a `class_name`. Names avoid clashes with Godot built-ins (`World3D`, `ConfigFile`, `floor()`).

### 2.1 Rules (`crawler/*.py` to `godot/rules/`)

| Python module | GDScript file(s) | Class(es) and key signatures | Data file(s) | Notes |
|---|---|---|---|---|
| `__init__.py` | none | | | |
| `config.py` | `rules/game_config.gd` | `GameConfig`: `static var MAP_W: int`, ... one `static var` per constant; `static func floor_turns(depth: int) -> int` | `config.json` (`config` section) | `static var`, not `const`, so tests can patch them (monkeypatch analogue). Colours stay `[r, g, b]` int arrays (no Godot `Color` in rules); the rules pass them through to `MessageLog`. |
| `attributes.py` | `rules/attributes.gd` | `Attributes.mod(score: int) -> int` (`PyMath.floordiv(score - 10, 2)`), `proficiency(level) -> int`, `fmt_mod(m) -> String` | `attributes.json` (`ATTRS`), config `attributes` section | `mod(9) == -1`: GDScript `/` would give 0. |
| `character.py` | none (data only) | read via `Content.table("genders")`, `Content.table("backstories")` | `genders.json`, `backstories.json` | Key order matters (bot `pick.choice` over `tuple(BACKSTORIES)`, `list(GENDERS)`). |
| `classes.py` | none (data only) | `Content.table("races")`, `("classes")`, `("skills")` | `races.json`, `classes.json`, `skills.json`; config `classes` (`CHOICE_FLOOR`, `FLAT_BONUSES`) | Key order matters (bot picks). |
| `dice.py` | `rules/dice.gd` | `Dice.d20(rng: PyRandom, advantage := 0) -> Array` (`[kept, rolls]`), `roll(rng, n, sides) -> int`, `fmt(n, sides, bonus := 0) -> String`, `average(n, sides, bonus := 0) -> float`, `dice_distribution(n, sides) -> Dictionary`, `chance_to_hit(attack_bonus, target, crit_range := 1, advantage := 0) -> Array` (`[p_hit, p_crit]`), `needed_roll(a, t) -> int` | none | `lru_cache` becomes a `static var _dist_cache := {}` keyed `Vector2i(n, sides)`. The cached Dictionary is shared, as in Python; callers never mutate it. Insertion order of `dist` must match (float sums iterate it). `sum(hits) / 20` is `float(count) / 20`. |
| `combat.py` | `rules/combat.gd`, `rules/attack_result.gd` | `Combat.attack(attacker, defender, rng, mult: float = 1, sure := false, bonus := 0, crit_bonus := 0, advantage := 0) -> AttackResult`; `hit_chance(a, d, advantage := 0) -> float`; `crit_chance(a, advantage := 0)`; `expected_damage(a, d, mult := 1.0, bonus := 0) -> float`; `saving_throw(rng, bonus, dc) -> Array` (`[saved, face]`). `AttackResult`: `hit, crit, damage, killed, roll, total, target`, `natural() -> String` ("20", "1" or ""), `dice_text() -> String` | none | `round(...)` is `PyMath.round_half_even`; `sum(...)` in `expected_damage` is `PyMath.fsum_py` (Python 3.12+ compensated sum, see 3.3). `natural` returns `None` in Python; use `""` and test truthiness the same way. |
| `dungeon.py` | `rules/dungeon.gd`, `rules/dungeon_floor.gd`, `rules/dungeon_room.gd` | `Dungeon.generate_floor(rng, depth, width := MAP_W, height := MAP_H) -> DungeonFloor`; `Dungeon.compute_fov(floor, ox, oy, radius := FOV_RADIUS) -> Dictionary` (set of `Vector2i`); `DungeonFloor`: `WALL/FLOOR/STAIRS/FURNITURE` consts, `tiles`, `safe`, `explored`, `rooms`, `start_room`, `safe_room`, `stairs: Array[Vector2i]`, `furniture: Dictionary`, `safe_door`, `in_bounds`, `walkable`, `is_safe`, `distance_map(sx, sy, max_dist := -1, avoid_safe := false) -> PackedInt32Array`, `forget_paths()`; `DungeonRoom`: `x, y, w, h`, `centre() -> Vector2i`, `contains`, `intersects(other, pad := 1)`, `tiles() -> Array[Vector2i]` (row-major, y outer) | none | Keep `tiles[y][x]` as `Array` of `PackedByteArray` rows (save format is list of lists). Neighbour cache `_adj_all` / `_adj_no_safe` as `Array` of `PackedInt32Array`. `max_dist=None` becomes `-1`. `sorted(..., key=dist)` and `candidates.sort(key=d)` need the stable sort (ties are common). FOV recursion is identical; visible set is a `Dictionary` used only for membership and to mark `explored`. |
| `entities.py` | `rules/entity.gd`, `rules/player.gd`, `rules/monster.gd`, `rules/pet.gd`, `rules/entities.gd` | `Entity` (fields in dataclass order, `alive` getter, `take_damage`, `heal`, `damage_text`); `Player extends Entity` (`level, xp, kills, attrs, stat_points`, `xp_to_next`, `gain_xp -> Array[int]`); `Monster extends Entity` (`key, xp_value, alerted, unseen_turns, ranged, boss, phase, stunned, save, tier, base`, getters `the`, `The`, `a`); `Pet extends Entity`; `Entities.new_player(x, y)`, `stat_block(d) -> Dictionary`, `monster_table(depth) -> Array` (`[keys, weights]`), `spawn_monster(key, x, y)`, `init_mod(entity)`, `new_pet(species, name, x, y)`; each class has `to_dict()` / `from_dict()` in dataclass field order | `monsters.json`, `pets.json`, `pet_quips.json` | `@dataclass(eq=False)`: identity equality, which GDScript objects already have. `isinstance(entity, Pet)` is `entity is Pet`; `hasattr(e, "alerted")` is `e is Monster`. |
| `encounter.py` | `rules/encounter.gd` | `Encounter`: `order`, `round`, `budget`, `reacted` (Dictionary as set), `has_entity(e)` (Python `__contains__`), `add(e, roll, modifier)`, `can_react`, `react`, `ready`, `remove`, getters `entities`, `monsters`, `turn_over`, `total`, `before`, `after`, `has(part)`, `spend`, `reset_budget` | config `encounter` (`PARTS`, `PART_NAMES`) | `order.sort(key=row[0])` with key `(-(roll+mod), -mod, is_not_player, seq)`: keys are unique, so `sort_custom` with a tuple comparator is safe, but use `PyMath.stable_sort_by` anyway for uniformity. |
| `ai.py` | `rules/ai.gd` | `Ai.cheb(a, b) -> int`, `chase_map(world) -> PackedInt32Array`, `take_monster_turns(world)`, `take_combat_turn(world, m)`, `take_pet_turn(world, combat := false)`; private `_free`, `_step_down`, `_notice`, `_melee`, `_shoot`, `_occupied` | config `ai` | `for m in list(world.monsters)` iterates a copy (`duplicate()`); membership re-checked. `min(xs, key=)` keeps the first minimum: use `PyMath.min_by`. `sorted(targets, key=hp)` needs the stable sort. Chase cache stored on the world as `[floor, x, y, dist]`, compared with `is_same(floor)`. |
| `bosses.py` | `rules/bosses.gd` | `Bosses.spawn_boss(depth, x, y) -> Monster`, `spawn_act(tier, base, x, y) -> Monster`, `acts_per_floor(depth) -> Vector2i`, `boss_depth(m) -> int` | `bosses.json` (keys "1" to "6"), `acts.json` (`ACTS`, `ACT_NAMES`), config `bosses` (`MAP_RADIUS`, `PHASE_TWO`) | `round(m["hp"] * a["hp"])` (2.0, 3.0) through `PyMath.round_half_even`. JSON object keys are strings: `Content.boss(depth)` converts. |
| `items.py` | `rules/items.gd` | `Items.FISTS` (static var Dictionary), `floor_loot_table(depth) -> Array` (`[keys, weights]`), `glyph(key)`, `describe(key) -> String`, `value(key) -> int` | `items.json`, `floor_loot.json`, config `items` (`GLYPHS`, `EQUIP_SLOTS`) | `describe` uses `{:+d}` and `{:.0f}`: `PyFmt`. |
| `loot.py` | `rules/loot.gd` | `Loot.TIERS`, `odds(tier) -> Array` (`[[key, p], ...]`), `roll_box(tier, rng) -> String`, `box_stats(tier) -> Array` (`[ev, sd]`), `next_tier(tier) -> String` ("" for none), `reroll_fee(tier) -> int` | `loot_boxes.json`, config `loot` | `w / total` is float division; `sum` over floats is `PyMath.fsum_py`; `var ** 0.5` is `pow(var, 0.5)` (matches Python, see 3.3). |
| `achievements.py` | `rules/achievements.gd`, `rules/achievement_tracker.gd`, `rules/achievement_rules.gd` | `Achievements.new(world)`, `unlocked: Dictionary`, `tracker`, `_on_event(name, data)`, `_unlock(key, a)`; `AchievementTracker` (counters, `equipped` set); `AchievementRules.test(rule: Dictionary, t: AchievementTracker, d: Dictionary) -> bool` | `achievements.json` (with `rule` objects, section 4.4) | The lambdas become data plus one interpreter; see 4.4. |
| `crafting.py` | `rules/crafting.gd` | `Crafting.can_craft(recipe: Dictionary, inventory: Array) -> bool` | `recipes.json`, config `crafting` (`CRAFT_TURNS`) | `Counter` becomes a count loop. |
| `contracts.py` | `rules/contracts.gd` | `Contracts.effect(world, name, default = 1)`, `preview(world, key) -> PackedStringArray` | `contracts.json`, config `contracts` | `preview` temporarily mutates monsters' `dmg_bonus` and restores it: keep that exactly. Float text through `PyFmt`. |
| `shop.py` | `rules/shop.gd`, `rules/shop_stock.gd` | `Shop.new(rng: PyRandom)`, `stock: Dictionary` (BASE_DEMAND order), `log: Array`, `bought`, `missed`, `safety_stock`, `reorder_point`, `order_up_to`, `price`, `static sell_price`, `buy`, `take_back`, `_poisson(mean)`, `end_of_floor(depth)`, `to_dict`, `load`; `ShopStock`: `on_hand, forecast, on_order, history` | `shop.json` (`BASE_DEMAND`), config `shop` | `end_of_floor` iterates `stock` in insertion order and draws Poisson numbers per item: the order is the RNG order. `math.ceil` is `ceili`; `math.exp`/`math.sqrt` are `exp`/`sqrt` (same libm). `round(x, 3)` is `PyMath.round_n`. |
| `practice.py` | `rules/practice.gd` | `Practice.new(world)`, `levels`, `xp`, `used` (set), `steps`, `level(key)`, `gain(key, amount := 1)`, listeners, `to_dict`, `load`; `static xp_to_next(level) -> int` (`ceili(8 * pow(1.45, level))`) | `practice_skills.json`, config `practice` | Subscribes in a fixed list order; keep it. |
| `funfacts.py` | `rules/fun_facts.gd` | `FunFacts.new(world)`, listeners, `_say(text, once := "", force := false) -> bool` | config `funfacts` | Heavy `{:.0%}`, `{:.2%}`, `{:.0f}` formatting: `PyFmt`. `min(odds, key=p)` first minimum. |
| `showrunner.py` | `rules/showrunner.gd` | `Showrunner.new(world)`, `rng`, `viewers`, `peak`, `history`, `samples`, `_gain`, `_viewers`, `_idle`, `_pet_quip`, `_say(kind, ctx)`, `_box_reaction`, `_announce`; `static box_kind(tier, key) -> String` | `lines.json`, `sponsor_gifts.json`, config `showrunner` (`SPEAK_CHANCE`, `PET_EVENTS`, ...), `JACKPOT_VALUE` | Subscription order is RNG order (see 5.4). `str.format_map(_Safe(ctx))` is `PyFmt.format_map(template, ctx)` (missing keys give "?"). `{self.viewers:,}` is `PyFmt.thousands`. `d["tier"].capitalize()` is `PyFmt.capitalize` (Godot's `capitalize()` differs). |
| `lines.py` | none (data only) | | `lines.json`, config `JACKPOT_VALUE` | 41 events x mild/spicy. Placeholders are plain `{name}` only (checked by the exporter). |
| `report.py` | `rules/run_report.gd` | `RunReport.build(world) -> Dictionary` | none | Plain loop sums (naive, as in Python's explicit `+=`), `sum()` over ints. |
| `save.py` | `rules/save_game.gd` | `SaveGame.VERSION := 7`, `to_dict(w) -> Dictionary`, `from_dict(d) -> World`, `save(w, path)`, `load(path) -> World`, `has_save(path)` | none | Same JSON layout as Python v7 so saves cross-load (with the float caveat in 11). Written with `PyJson.dumps` (Python key order, no sorting) and atomically (`.tmp` then `DirAccess.rename_absolute`). Godot's `JSON.stringify` sorts keys by default and prints 14 significant digits: never use it for saves. |
| `settings.py` | `rules/user_settings.gd` | `UserSettings.VIEWS`, `DEFAULTS`, `load(path) -> Dictionary`, `save(settings, path)`; `path == ""` disables | none | Default path `user://settings.json` (Python: `saves/settings.json`). |
| `telemetry.py` | `rules/telemetry.gd`, `rules/py/py_csv.gd` | `Telemetry.new(world, source := "player", run_id := "", meta := {})`, `tables() -> Dictionary`; `PyCsv.write_tables(tables, out_dir, prefix := "", skip := [])` | config `telemetry` (`SKIP`, `VALUE_KEYS`, `DETAIL_KEYS`) | Column order is Dictionary insertion order: insert keys exactly as Python builds them (8.5). `uuid4().hex[:12]` for player runs becomes 12 hex chars from `Crypto.generate_random_bytes` (not parity-relevant; the bot passes ids). |
| `events.py` | `rules/event_bus.gd` | `EventBus.subscribe(name, fn: Callable)`, `emit(name: String, data := {})`, `var tap: Callable` (trace seam, called first in `emit`) | none | Named subscribers first, in subscription order, then `"*"`; iterate the live array by index (Python iterates the live list). Handlers get `(name, data)`. |
| `world.py` | `rules/world.gd`, `rules/message_log.gd` | `World.new(seed = null, pet = null, hero = null)` (pet `[species, name]`), all public methods with the same names and return values; `MessageLog`: `lines` (max 200), `add(text, colour := TEXT)`, `recent(n)`, `var tap: Callable` | none | About 1,560 lines; split over three briefs (section 9) but one file. Python properties (`viewers`, `active_pet`, `skill`, `in_safe_room`, `on_stairs`, `stairs_wait`, `stairs_locked`, `address`) become GDScript properties with `get:` so call sites read the same. `seed=None` draws `randi() & 0x3FFFFFFF` (not parity-relevant). |

Shared helpers written in P1 slice S1 (not Python modules, but every port depends on them):

| File | Class | Purpose |
|---|---|---|
| `rules/py_random.gd` | `PyRandom` | CPython `random.Random` (section 5). Done in P0 and proven against Python. |
| `rules/py/py_math.gd` | `PyMath` | `floordiv(a, b)`, `mod(a, b)` (Python `%`, sign of divisor), `fmod_py(a: float, b: float)`, `round_half_even(x: float) -> int`, `round_n(x: float, n: int) -> float`, `fsum_py(values: Array) -> float`, `stable_sort_by(arr: Array, key: Callable) -> Array` (returns new array, Python `sorted`), `stable_sort_in_place(arr, key)` (`list.sort(key=)`), `min_by(arr, key)`, `max_by(arr, key, default = null)` (first extreme wins), `compare_tuples(a: Array, b: Array) -> int`, `truthy(v) -> bool` (Python truthiness for `0`, `""`, `[]`, `{}`, `null`). |
| `rules/py/py_fmt.gd` | `PyFmt` | `repr_float(x) -> String`, `str(v) -> String` (bool as `True`/`False`, null as `None`, floats via `repr_float`, ints plain), `fixed(x, n)` (`{:.nf}`), `signed_int(n)` (`{:+d}`), `signed_fixed(x, n)` (`{:+.nf}`), `percent(x, n)` (`{:.n%}`), `signed_percent(x, n)` (`{:+.n%}`), `thousands(n)` (`{:,}`), `zero_pad(n, width)` (`{:02d}`), `capitalize(s)` (Python `str.capitalize`), `format_map(template, ctx: Dictionary) -> String` (plain `{key}` placeholders, missing key gives `?`). |
| `rules/py/py_json.gd` | `PyJson` | `dumps(v) -> String`: Python `json.dumps` style (insertion order, floats via `repr_float`, `true/false/null`, `ensure_ascii` escapes). `loads(text) -> Variant` wraps `JSON.parse_string` and is followed by schema-aware int coercion by the caller (`Content`, `SaveGame`). |
| `rules/py/py_csv.gd` | `PyCsv` | Python `csv.DictWriter` (excel dialect): CRLF line ends, QUOTE_MINIMAL, values via `PyFmt.str`. |
| `rules/content.gd` | `Content` | `static func table(name: String) -> Variant` (loads `res://data/<name>.json` once, coerces ints using `manifest.json`), typed helpers (`monster(key)`, `item(key)`, `boss(depth)`, ...), `static func reload()` for tests. |

### 2.2 Presentation (`crawler/game.py`, `crawler/ui/*` to `godot/scenes/`, `godot/ui/`)

| Python | Godot | Notes |
|---|---|---|
| `game.py` `App` (state machine, key handling, held keys, `update(dt, held)`) | `ui/app_state.gd` (`AppState extends RefCounted`: scene, overlay, cursor, identity/pet/class steps, `handle_action(action: StringName, ch := "")`, `update(dt, held: Dictionary)`), `scenes/main.tscn` + `ui/main.gd` (reads `InputMap` actions, forwards to `AppState`, swaps views and overlays) | Keeping the state machine headless lets `test_render.py`'s logic tests port without a window. |
| `main.py`, `fp_demo.py` | `project.godot` main scene; CLI user args `-- --seed 1234 --view fp` parsed in `ui/main.gd` | |
| `ui/firstperson.py` | `scenes/fp_view.tscn`, `ui/fp/fp_logic.gd` (headless: `step_for_angle`, `angle_gap`, `open_facing`, facing/angle maths, `tap_turn`, `set_combat`, `relative`, `target_ahead`, camera glide `update_camera`, `glide_left`), `ui/fp/fp_camera_rig.gd`, `ui/fp/floor_mesh_builder.gd`, `ui/fp/billboards.gd`, `ui/fp/minimap.gd`, `ui/fp/fp_overlays.gd` | The raycaster itself is replaced by real 3D (section 10). The maths uses `PyMath` too: `round(angle / 45) % 8` has ties at 22.5 degrees and negative angles. |
| `ui/hud.py` | `scenes/hud.tscn`, `ui/hud/side_panel.gd`, `ui/hud/log_view.gd`, `ui/hud/initiative_tracker.gd`, `ui/hud/toasts.gd`, `ui/hud/scout_report.gd`; `scenes/top_view.tscn`, `ui/top/top_view.gd` | |
| `ui/menus.py` | `scenes/menus/{inventory,safe_menu,reveal,craft,class_select,identity,backstory,pet_select,box_info,shop,contract,practice,attributes}.tscn` with matching `ui/menus/*.gd` | Row builders (`inventory_rows`, `menu_options`, `class_rows`, `shop_rows`, `attr_source`) are pure functions: put them in `ui/menus/menu_rows.gd` and test headless. |
| `ui/screens.py` | `scenes/screens/{title,help,death,victory}.tscn`, `ui/screens/controls.gd` (control lists per view) | |
| `ui/report.py` | `scenes/screens/run_report.tscn`, `ui/screens/chart.gd` (custom `_draw`) | `nice_max`, `plural` are pure: test headless. |

### 2.3 Bot, telemetry runner, tests

| Python | Godot | Notes |
|---|---|---|
| `analysis/bot.py` (`step_towards`, `score`, `spend_points`, `manage_items`, `worth_taking`, `can`, `best_of`, `choose`, `flee_goal`, `_choose`, `run_config`, `play`) | `tools/bot_policy.gd` (`BotPolicy` with the same static functions; `play(seed, pet := "", deals := "random", telemetry := false, max_steps := 200000) -> Array` (`[world, tables]`)), `tools/bot.gd` (CLI, `extends SceneTree`) | Bot state Python hangs on the world (`w._bot_route`, `w._bot_fleeing`) goes in a `BotState` object passed alongside. `pick = random.Random(seed * 7919 + 13)`, `coin = random.Random(seed ^ 0xB07)` become `PyRandom`. Multiprocessing becomes process sharding (8.4). |
| `analysis/common.py`, notebooks | stay Python | Notebooks read the same CSVs; content via JSON (4.3). |
| `conftest.py` | `tests/support/` and `scripts/gd_test.sh` environment | |
| `tests/*.py` | `tests/test_*.gd`, `tests/ui/test_*.gd` | Per-file table in Appendix B. |

---

## 3. Python features that need care

### 3.1 Checklist for porters

| Python feature | Where it appears | GDScript rule |
|---|---|---|
| `a / b` (always float) | `loot.odds`, `dice.chance_to_hit`, `shop.price`, `_respawn` (`timer / timer_max`), contracts preview, funfacts, telemetry `hp_frac` | GDScript `int / int` truncates. Write `float(a) / b` for every Python `/`. Verifier greps every `/` in a diff. |
| `a // b` (floor) | `attributes.mod` (negative: `mod(8) == -1`), `depth // 3`, `practice(...) // 2..5`, `max_hp // 4`, `turns // 10`, `amount // 40`, `damage // 2`, `cooldown // 2`, `floor_turns(depth) // 2`, `len(candidates) // 2`, regen interval, `timer_text` | `PyMath.floordiv(a, b)` everywhere, even where values look positive. |
| `a % b` (sign of divisor) | `timer_text`, `self.turn % ...`, `PET_MODES` cycling, `steps % CARDIO_STEPS`, UI angle maths (floats, negatives) | Ints: `PyMath.mod` (= `posmod` for positive divisors). Floats: `fposmod`. GDScript `%` on a negative int gives a negative result. |
| `round(x)` (half to even, returns int) | combat damage `round((roll + bonus) * mult)` (mult 1.5, 2, 3, 1.03...), `round(sum * RESPAWN_CAP)` (10 x 1.25 = 12.5 gives 12), `round(gap)`, prices, potions, bombs, contracts timer, `spawn_act` HP, UI angles | `PyMath.round_half_even(x) -> int`. Godot's `round(2.5)` is 3.0 (measured). |
| `round(x, n)` | `hp_frac` (3), `ev` (2), shop log (3) | `PyMath.round_n(x, n)`: format with `"%.nf"` (matches Python exactly, Appendix A) then parse; parsing short decimals is exact in Godot (measured). |
| `int(x)` (truncate) | viewers, rest `owed` | `int(x)`: same truncation. |
| `math.ceil` returns int | practice curve, shop | `ceili`. |
| `x ** 0.5`, `1.45 ** n` | respawn weights `w / xp ** 0.5`, box SD, practice curve | `pow(x, 0.5)`, not `sqrt`: both Pythons and Godot call glibc `pow`, which differs from `sqrt` for 82 of the first 100,000 integers; `pow` matches Python on all of them (measured). |
| `sum()` of floats | `expected_damage`, `box_stats`, contracts preview (`sum(expected_damage...)`, gold average) | Python 3.12+ `sum()` uses Neumaier compensated summation: it differs from a naive loop in 183 of 750 expected-damage-shaped sums (measured). Use `PyMath.fsum_py`. Explicit `+=` loops in Python (`run_report`, `rest`) stay naive. Sums of ints and bools are ordinary. |
| Float evaluation order | every multi-factor product (`gold = xp * GOLD_PER_XP * uniform * mult * ...`, viewers `_gain`, potion heal) | Keep the same left-to-right order and grouping; never fold constants or reorder factors. |
| `sorted(xs, key=)`, `list.sort(key=)` (stable) | `others = sorted(rooms, key=dist)` (stairwell rooms, ties common), `candidates.sort(key=d)` (safe room, ties common), `sorted(targets, key=hp)` (pounce), `Encounter.add`, `sorted(CONTRACTS)` | Godot's `sort_custom` is documented as unstable. Use `PyMath.stable_sort_by` / `stable_sort_in_place`. `Array.sort()` on plain Strings is fine (code point order matches Python, measured). |
| `min(xs, key=)`, `max(xs, key=)` | targets, spots, bot goals, `max(gaps, key=gaps.get)` | First extreme wins: `PyMath.min_by` / `max_by`. Tuple keys (`(cheb, s)`) via `PyMath.compare_tuples`. |
| Tuples as keys and in sets | `floor_items`, `furniture`, `visible`, `occupied`, `taken` | `Vector2i` keys. Sets become `Dictionary` with `true` values, membership only. |
| `dict` insertion order | content tables, `shop.stock`, `floor_items`, telemetry rows, payloads | Godot `Dictionary` keeps insertion order, including erase then re-insert at the end (measured), and `JSON.parse_string` keeps document key order (measured). |
| `for x in list(...)` while mutating | `take_monster_turns`, `_explode` | Iterate `duplicate()`; recheck membership as Python does. |
| `list.remove(x)`, `index`, `count`, `pop(0)` | inventory, boxes, reasons | `erase` (first occurrence), `find`, `count`, `pop_front`. |
| Python truthiness | `if self.skill_cooldown`, `if reasons`, `if not here`, `trait()` results, `d.get("early", False)`, `contract or "none"` | Be explicit: `!= 0`, `not arr.is_empty()`, `PyMath.truthy(v)` for Variants. `None` vs `""`: keep `null` where Python stores `None` and the value is saved or written to CSV (`cls or "none"`, `death_cause or ""`). |
| `bool` is an `int` | `sum(bools)`, `killed += not m.alive`, `key = (..., entity is not self.player, ...)` | Convert explicitly (`int(b)`). |
| `str(bool)`, `str(None)` | telemetry `pet_down`, `rerolled` (`True`/`False` in CSV), events `detail` (`str(d["boss"])` gives `False` for `pet_kill`) | `PyFmt.str`. Godot's `str(true)` is `true`. |
| f-string specs | `:+d`, `:.0f`, `:.1f`, `:.0%`, `:.2%`, `:+.0f`, `:+.0%`, `:,`, `:02d` (all uses in `crawler/`) | `PyFmt`. Godot's `"%.nf" % x` matches Python's `f"{x:.nf}"` on 20,000 test values including halves, and `"%+.0f" % -0.4` gives `-0` like Python (measured). |
| `str(float)` / `repr` | CSV cells, trace payloads, saves | `PyFmt.repr_float`. Godot `str(0.1 + 0.2)` gives `0.3` (14 digits) and `var_to_str` is not always shortest (measured). See 3.3. |
| `str.capitalize`, `name[0] in "AEIOU"` | showrunner tier, `Monster.a`, class title article | `PyFmt.capitalize` (Godot's turns `opening_act` into `Opening Act`). |
| `str.format_map(_Safe)` | every System line | `PyFmt.format_map`. |
| Dataclasses, `asdict`, `field(default_factory)` | entities, `Room`, `Stock`, `Tracker`, `AttackResult` | Classes with typed vars initialised in `_init`; `to_dict()` in field order (save layout). |
| `@property` | `alive`, `the`, `The`, `a`, world getters, `Encounter.entities/monsters/turn_over` | GDScript properties (`var alive: bool: get: return hp > 0`). |
| `__contains__` | `Encounter` | `has_entity(e)`. |
| `lru_cache` | `dice_distribution` | static Dictionary cache. |
| Lambdas in content | achievement tests, `lambda t, d, depth=_depth:` closure | Rule objects in JSON plus `AchievementRules` (4.4). |
| `**kwargs` events, `emit(name, **data)` | every event | `emit(name, {...})` with keys in Python kwarg order. Payload key `name` is still forbidden. |
| `next(gen)`, `StopIteration` | `_spawn_boss` room lookup, telemetry value/detail, `Encounter.total` | Loops with explicit fallbacks. |
| Exceptions | save version check, mid-combat save, `choice([])` | `push_error` plus a return value (`null` / `false`); the caller checks. Tests assert the return value instead of `pytest.raises`. |
| Integer size | seeds (`seed * 7919 + 13`), MT words, viewers | GDScript `int` is 64-bit signed; all game values fit. Seeds must be in `0 .. 2**62`. MT maths masks to 32 bits after every multiply (products stay below 2**63). |
| `deque(maxlen=200)` | `MessageLog` | Array with `pop_front` past 200. |
| `uuid`, `time`, `multiprocessing` | telemetry ids for player runs, bot timing, Pool | Not rules; see 8.4. |

### 3.2 GDScript gotchas for the same code

- `JSON.parse_string` returns every number as `float` (measured: `{"z": 1}` gives `TYPE_FLOAT`). `Content` and `SaveGame` coerce by schema (4.2).
- `JSON.stringify(data)` sorts keys by default and prints floats with 14 significant digits unless `full_precision` is true (measured). Use `PyJson.dumps`.
- A script run with `godot --headless -s` that fails to parse exits with code 0 (measured). The test wrapper checks a sentinel line too (7.3).
- `class_name` classes resolve only after `godot --headless --path godot --import` has built `.godot/global_script_class_cache.cfg` (measured: without it, `Identifier "Foo" not declared`). CI and every brief run the import step once.
- Runtime errors inside a called function print `SCRIPT ERROR` and return `null` without stopping the caller. Tests must assert on results; the wrapper fails on any `SCRIPT ERROR` in the log.
- `Array.has` / `erase` / `find` compare Objects by reference (what Python's `eq=False` dataclasses do) and `Vector2i` by value.
- Modifying a Dictionary while iterating it is an error in both languages; copy keys first.

#### Back-references to World

`World` creates `Practice`, `Achievements`, `Showrunner` and `FunFacts` in `_init` and keeps them for its whole life (never reassigned; load restores in place). Each holds `_world_ref: WeakRef` with a typed `world` getter and never stores the world strongly in a member, because World -> subsystem -> World would be a reference cycle that leaks both. Subscribe bound methods, not lambdas capturing `self` or the world. Write one ownership test per subsystem (build a stand-in or real world, drop it inside an inner function, assert weakrefs to world and subsystem return null). Anything that keeps only a subsystem without its World gets null from `world`; a subsystem freed while its world lives leaves a dead callable on the event bus (SCRIPT ERROR in `event_bus.gd`).

### 3.3 Float text and parsing (measured on 4.7.2)

| Need | Godot behaviour | Plan |
|---|---|---|
| `f"{x:.nf}"` | `"%.nf" % x` identical to Python for n = 0 to 3 over 20,000 values (halves, negatives, huge, tiny) | Use directly through `PyFmt.fixed`. |
| `repr(x)` (CSV, traces, saves) | `str()` uses 14 digits; `var_to_str` gave 17 digits where 16 suffice in 9 of 20,000 values and uses its own exponent style | `PyFmt.repr_float`: fixed notation for `1e-4 <= abs(x) < 1e16` (Python's rule), exponent form for the rest. GDScript's formatter has no `%e` and `%f` is inexact past about 16 digits for very large or small values, so the digits come from `String.num_scientific`, then the shortest decimal that Clinger's exact check proves round-trips (`M < 2**53`, one multiply or divide by an exact power of ten) wins, and 16-17 digit results in `1e-4 <= abs(x) < 1e16` are redone with `"%.nf"` (exact there, ties to even). Verified identical to CPython on 8,000+ values (game values, edge exponents, random doubles). Outside that range a double may print a different last digit or a longer non-shortest form (e.g. `1e126`); no game value reaches there (all CSV floats are 0.067-42.5), and `parity_diff.py` compares numbers by value anyway. |
| Parsing floats | `JSON.parse_string`, `str_to_var`, `to_float` are exact for decimals with up to 15 significant digits (20,000 of 20,000) but wrong by 1 ulp for 17% of 17-digit reprs | Content floats are all short (exporter asserts at most 15 significant digits). Saves: see risk R5. |
| `x ** 0.5` | glibc `pow`, same as CPython on this machine | `pow(x, 0.5)`. Parity is claimed for Linux x86_64 with glibc; other platforms fall back to statistical parity. |
| `sum()` | n/a | `PyMath.fsum_py` (Neumaier, final `+ c` if `c` is non-zero and finite); validated against CPython 3.13 `sum` on 200,000 random float lists with zero mismatches. |

`PyMath.fsum_py` reference:

```gdscript
static func fsum_py(values: Array) -> float:
	var f := 0.0
	var c := 0.0
	for v in values:
		var x := float(v)
		var t := f + x
		if absf(f) >= absf(x):
			c += (f - t) + x
		else:
			c += (x - t) + f
		f = t
	if c != 0.0 and is_finite(c):
		f += c
	return f
```

The committed reference data was produced by Python 3.12 or later: the bot under the installed Python 3.13.16 reproduces the first rows of every committed `runs/bot_*.csv` byte for byte (seeds 0-2 checked). The port targets Python 3.12+ semantics.

---

## 4. JSON content in `godot/data/`

### 4.1 Generator

`scripts/export_content.py` (Python 3.12+, imports `crawler.*` read-only):

```
python scripts/export_content.py            # writes godot/data/*.json and godot/data/manifest.json
python scripts/export_content.py --check    # exit 1 if regenerating would change any file (CI drift check)
```

- One JSON file per table, `indent=1`, `ensure_ascii=False`, `sort_keys=False` (Python insertion order is the order the rules iterate), UTF-8, trailing newline.
- Tuples become arrays; tuples of named fields become objects (shown below); colours `[r, g, b]`.
- Every float in content must have at most 15 significant digits (asserted).
- `manifest.json`: `{"generator": 1, "python": "3.13.16", "source_commit": "<git rev-parse HEAD>", "files": {"items.json": {"sha256": "...", "sources": ["crawler/items.py"], "float_paths": ["..."]}, ...}}`. `float_paths` lists every leaf that was a Python `float` (JSON pointer style, `/backstories/mixologist/potion_mult`). `Content` converts every other number to `int`.
- Self-checks before writing: achievement rules agree with the Python lambdas (4.4); every line placeholder is a plain identifier and no `{{` appears; every key referenced across tables exists (drops, box tables, recipes, loot, headliner drops).

`Content.table(name)` loads `res://data/<name>.json` once, walks it and coerces numbers using `float_paths`, and caches it in a `static var`. Tests that patch content (`monkeypatch.setitem(MONSTERS["goblin"], "init", 50)`) edit the cached Dictionary and restore it in `after_each`.

### 4.2 Files and schemas

| File | Source | Shape (key order preserved) |
|---|---|---|
| `config.json` | `config.py` plus module constants | `{"config": {...config.py names...}, "ai": {"CHASE_RADIUS": 25, "PET_LEASH": 2, "POUNCE_RANGE": 3, "SQUAWK_RANGE": 3, "MOUSE_FLEE_FRAC": 0.3}, "attributes": {"BASE_SCORE": 10, "START_POINTS": 6, "POINTS_PER_LEVEL": 2, "MAX_SCORE": 30}, "bosses": {"MAP_RADIUS": 22, "PHASE_TWO": {"damage_bonus": 3, "ranged": 5, "adds": ["cultist", "cultist"]}}, "classes": {"CHOICE_FLOOR": 3, "FLAT_BONUSES": ["max_hp", "ac", "hit", "dr"]}, "contracts": {"OFFER_FROM_FLOOR": 2, "OFFER_CHANCE": 0.7}, "crafting": {"CRAFT_TURNS": 10}, "encounter": {"PARTS": [...], "PART_NAMES": {...}}, "funfacts": {"MIN_GAP": 25, "MISS_STREAK": 4, "BOX_DROUGHT": 3}, "items": {"GLYPHS": {...}, "EQUIP_SLOTS": {...}}, "lines": {"JACKPOT_VALUE": 45}, "loot": {"TIERS": [...], "TRADE_UP_COST": 3, "REROLL_FEE_FRAC": 0.3}, "practice": {"MAX_LEVEL": 15, "SMALL_MONSTER_HP": 12, "CARDIO_STEPS": 40}, "shop": {"DEMAND_GROWTH": 0.1, "ALPHA": 0.3, "LEAD_TIME": 1, "SAFETY_Z": 1.0, "SCARCITY_MARKUP": 0.6, "SELL_RATE": 0.4}, "showrunner": {"START_VIEWERS": 50, "MIN_VIEWERS": 20, "SAMPLE_EVERY": 10, "IDLE_TURNS": 10, "DECAY": 0.97, "MULTI_WINDOW": 4, "CLUTCH_FRAC": 0.25, "SPEAK_CHANCE": {...}, "QUIP_CHANCE": 0.6, "FLEE_QUIP_GAP": 8, "PET_EVENTS": {...}}, "telemetry": {"SKIP": ["turn"], "VALUE_KEYS": [...], "DETAIL_KEYS": [...]}, "world": {"PET_MODES": ["follow", "attack", "stay"]}}` |
| `attributes.json` | `ATTRS` | `{"str": {"name": "Strength", "short": "STR", "does": "..."}, ...}` |
| `monsters.json` | `MONSTERS` | `{"gnawer": {"name": "Sewer Gnawer", "glyph": "r", "colour": [170, 140, 110], "hp": 6, "ac": 11, "attack": 3, "dmg": [1, 4, 0], "save": 1, "xp": 3, "floors": [1, 2], "weight": 6, "drops": ["sock", "sock", "tonic"]}, ..., "cultist": {..., "ranged": 5}}` (optional keys such as `ranged`, `init`, `dr` appear only where Python has them; `Content` callers use `.get(key, default)` as Python does) |
| `bosses.json` | `BOSSES` | `{"1": {"name": "The Grease Trap King", "glyph": "K", "colour": [...], "hp": 24, "ac": 11, "attack": 4, "dmg": [1, 6, 0], "save": 2, "xp": 25, "box": "silver"}, ..., "6": {..., "final": true}}` |
| `acts.json` | `ACTS`, `ACT_NAMES` | `{"acts": {"opening": {"title": "Opening Act", "hp": 2.0, "attack": 1, "ac": 1, "dmg": 1, "save": 2, "xp": 3, "gold": 2}, "featured": {...}}, "names": {"gnawer": ["Gnawer Matriarch", "The Rat Queen of Aisle Nine"], ...}}` (`hp` stays float: in `float_paths`) |
| `pets.json` | `PETS` | `{"cat": {"name": "Alley Cat", "glyph": "f", "colour": [...], "hp": 16, "ac": 13, "attack": 4, "dmg": [1, 6, 1], "default_name": "Mittens", "ability": "pounce", "ability_name": "Pounce", "cooldown": 18, "desc": "..."}, "dog": {...}, "budgie": {...}, "mouse": {...}}` (order is `PET_ORDER` for the bot) |
| `pet_quips.json` | `PET_QUIPS` | `{"cat": {"kill": ["Beneath me, frankly.", ...], "ability": [...], "level_up": [...], "downed": [...]}, ..., "mouse": {..., "flee": [...]}}` |
| `items.json` | `ITEMS`, `FISTS` | `{"fists": {"name": "Fists", "style": "unarmed", "dice": [1, 4]}, "items": {"pan": {"name": "Dented Frying Pan", "kind": "weapon", "style": "blunt", "value": 10, "dice": [1, 6], "colour": [...], "desc": "Seen better breakfasts."}, ..., "vest": {"name": "Riot Vest", "kind": "armour", "value": 22, "ac": 2, "max_dex": 2, ...}}}` |
| `floor_loot.json` | `FLOOR_LOOT` | `[{"item": "sock", "weight": 4, "min_floor": 1}, ...]` |
| `loot_boxes.json` | `BOX_TIERS` | `{"bronze": {"name": "Bronze", "colour": [205, 140, 80], "table": [{"item": "sock", "weight": 4}, {"item": "tonic", "weight": 4}, {"item": "popper", "weight": 3}, {"item": "jersey", "weight": 3}]}, ...}` |
| `races.json`, `classes.json`, `skills.json` | `RACES`, `CLASSES`, `SKILLS` | `{"hobgoblin": {"name": "Hobgoblin", "desc": "...", "attrs": {"dex": 2}, "crit_range": 3, "ac": -1}, ...}`; `{"alchemist": {"name": "Alchemist", "desc": "...", "attrs": {"int": 2}, "max_hp": 4, "class_potion_mult": 1.3, "skill": "field_brew", "pairs": ["mixologist", "parent"]}, ...}`; `{"arc_bolt": {"name": "Arc Bolt", "cooldown": 20, "range": 6, "desc": "..."}, ...}` |
| `backstories.json`, `genders.json` | `BACKSTORIES`, `GENDERS` | `{"mixologist": {"name": "Mixologist", "perk": "...", "desc": "...", "attrs": {"cha": 2}, "potion_mult": 1.4}, ...}`; `{"female": {"name": "Woman", "address": "madam"}, ...}` |
| `achievements.json` | `ACHIEVEMENTS` (33, headliners expanded) | 4.4 |
| `lines.json` | `LINES` | `{"floor_start": {"mild": ["Floor {depth} is live. Smile for the cameras, {hero}.", ...], "spicy": [...]}, ...}` (41 events; `spicy` may be missing or empty, as in Python) |
| `practice_skills.json` | `practice.SKILLS` | `{"fisticuffs": {"name": "Fisticuffs", "group": "Fighting", "trains": "...", "effect": "+1 unarmed damage every 2 levels"}, ...}` (20, order is the `K` screen and telemetry row order) |
| `shop.json` | `BASE_DEMAND` | `{"base_demand": {"tonic": 3.0, "brew": 1.5, "elixir": 0.5, "popper": 1.5, "fireworks": 0.7, "jersey": 0.8, "vest": 0.5, "pan": 0.8, "cleaver": 0.4}}` (order is the Poisson draw order) |
| `contracts.json` | `CONTRACTS` | `{"gloop_blitz": {"sponsor": "Gloop Energy", "name": "Gloop Blitz", "desc": "...", "gold_mult": 1.5, "monster_damage": 1, "bonus_box": "silver"}, ..., "hazard_pay": {..., "gold_mult": 2.0, "viewer_mult": 1.5, "monster_hp_mult": 1.25, "monster_damage": 2, "bonus_box": "gold"}}` |
| `recipes.json` | `RECIPES` | `[{"key": "sock_tea", "name": "Sock Tea", "needs": ["sock", "mug"], "makes": "tonic", "desc": "..."}, ...]` |
| `sponsor_gifts.json` | `SPONSOR_GIFTS` | `[{"viewers": 300, "tier": "bronze", "sponsor": "Brightly Snacks"}, ...]` |
| `ui_config.json` (presentation only) | `config.py` layout and colours, `firstperson.DEPTH_TINT`, `TIER_SCALE`, `TIER_OUTLINE`, `hud.TIER_COLOURS`, `FURNITURE_GLYPHS`, `screens` control lists | Read by `ui/` only. |

### 4.3 Reading the JSON from notebooks

The files are plain JSON in Python key order, so notebooks need nothing from Godot:

```python
import json, pandas as pd
monsters = pd.DataFrame.from_dict(json.load(open("godot/data/monsters.json")), orient="index")
boxes = json.load(open("godot/data/loot_boxes.json"))
odds = pd.DataFrame([dict(tier=t, **row) for t, b in boxes.items() for row in b["table"]])
```

`analysis/` is frozen, so no helper is added there now; a `content(name)` helper in `analysis/common.py` is a P3 option for the owner.

### 4.4 Achievements: lambdas to data

Each achievement keeps `name`, `desc`, `tier`, `on` and gains a `rule`. `AchievementRules.test(rule, t, d)` interprets it; `all` combines rules. The exporter holds an explicit `ACHIEVEMENT_RULES` table (lambdas cannot be introspected reliably) and, before writing, evaluates every Python lambda and the rule interpreter (a Python twin) on generated `(tracker, data)` cases around each threshold, failing on any disagreement or on an achievement without a rule.

| Rule kind | Fields | Python it replaces | Used by |
|---|---|---|---|
| `always` | | `lambda t, d: True` | critical_darling, blooper_reel, upcycler |
| `counter_gte` | `counter`, `n` | `t.<counter> >= n` | first_blood, pest_control (kills), pet_project (pet_kills), cursed_dice (nat1s), bare_knuckle_tv (unarmed_kills), cartographer (maps), pack_rat (pickups), dumpster_diver (junk_sold) |
| `field_gte` | `field`, `n` | `d[field] >= n` | deep_diver (depth 3), demolition (kills 2), pyrotechnician (kills 3), best_friends (level 3), jack_of_all_trades (many_at_3 8), nap_champion (turns 180) |
| `field_eq` | `field`, `value` | `d[field] == value` | opening_night, upstaged (tier), one_hp_wonder (hp 1), headliner_1..6 (depth) |
| `field_true` | `field` | `d.get(field, False)` | locksmith (early) |
| `field_lte_floordiv` | `field`, `of`, `div` | `d[field] <= d[of] // div` | close_call (player_hp, player_max_hp, 4) |
| `field_lt_frac` | `field`, `of`, `frac` | `d[field] < frac * d[of]` | cutting_it_fine (timer_left, timer_max, 0.1) |
| `world_gte` | `stat` (`viewers`, `inventory_len`), `n` or `n_config` | `t.world.viewers >= 1000`, `len(t.world.inventory) >= C.INVENTORY_SIZE` | crowd_pleaser, hoarder (`n_config: "INVENTORY_SIZE"`, read at test time so patching works) |
| `equipped_all` | `slots` | `{"weapon", "armour"} <= t.equipped` | dressed_to_kill |
| `all` | `rules` | `and` | underfoot (`field_eq skill "stomping"`, `field_gte level 3`) |

Example:

```json
"close_call": {"name": "Close Call", "desc": "Landed a kill on 25% HP or less.", "tier": "silver", "on": "kill",
  "rule": {"kind": "field_lte_floordiv", "field": "player_hp", "of": "player_max_hp", "div": 4}},
"headliner_3": {"name": "Show Stopper: Foreman Gristle", "desc": "Took down floor 3's Headliner, Foreman Gristle.",
  "tier": "gold", "on": "boss_kill", "rule": {"kind": "field_eq", "field": "depth", "value": 3}}
```

The tracker's counter updates per event (`kill` increments `kills` and maybe `unarmed_kills`, etc.) stay in `achievements.gd` code, as in Python.

---

## 5. RNG parity

### 5.1 Streams

| Stream | Construction (Python) | GDScript | Used for |
|---|---|---|---|
| main | `random.Random(seed)` (`World.rng`) | `PyRandom.new(seed)` | floor generation, monster and item placement, Acts, respawns, all attack and save rolls, initiative, monster wander and ranged choice |
| loot | `random.Random(seed ^ 0x100F)` (`World.loot_rng`) | `PyRandom.new(seed ^ 0x100F)` | box rolls, kill gold (`uniform`), drops, headliner drops, Featured Act hauls, Field Brew, Tinkering spare |
| shop | `random.Random(seed ^ 0x5A0F)` (`Shop.rng`) | same | Poisson demand in `end_of_floor` |
| deal | `random.Random(seed ^ 0xC0DE)` (`World.deal_rng`) | same | contract offer and choice |
| show | `random.Random(world.seed ^ 0x5EED)` (`Showrunner.rng`) | same | line choice, spice, chattiness, pet quips |
| bot pick | `random.Random(seed * 7919 + 13)` (`bot.run_config`) | same | race, class, backstory, gender for a bot seed |
| bot coin | `random.Random(seed ^ 0xB07)` (`bot.play`) | same | accept or decline each offer |
| unseeded | `random.randrange(1 << 30)` when `World(seed=None)` | `randi() & 0x3FFFFFFF` | the seed itself; not part of parity |

Construction order inside `World.__init__` (matters for nothing random, but the trace harness labels streams by it): main, loot, shop, deal, show.

### 5.2 Every call site

| File:line (Python) | Call | Stream | Method semantics needed |
|---|---|---|---|
| `dice.py:14,16` | `rng.randint(1, 20)` (once, or twice with advantage) | main | `randint` = `randrange(a, b+1)` = `a + _randbelow(width)` |
| `dice.py:21` | `rng.randint(1, sides)` n times | main | same |
| `combat.py:64,71,78` | via `d20`, `roll` | main | |
| `dungeon.py:124` | `rng.random() < 0.5` (corridor corner) | main | `random()` = `(a >> 5) * 67108864.0 + (b >> 6)` then `* 2**-53` |
| `dungeon.py:135-137` | `randint` x4 (room size, position) | main | |
| `dungeon.py:165` | `rng.sample(floor.rooms, 2)` | main | `sample`, set branch (n of about 44 > setsize 21) |
| `dungeon.py:177-178` | `randint` x2 per stairwell | main | |
| `dungeon.py:192` | `randint` x2 per safe-room candidate (up to 600) | main | |
| `dungeon.py:199` | `rng.shuffle(sides)` (4 items) | main | `shuffle`: `for i in reversed(range(1, n)): j = _randbelow(i + 1)` |
| `world.py:337` | `randint(0, min(2, 1 + depth // 3))` per room | main | |
| `world.py:339` | `rng.sample(spots, min(count, len(spots)))` | main | both branches: pool branch when the room has 21 or fewer free tiles, set branch otherwise; `k = 0` draws nothing |
| `world.py:340, 389, 407` | `rng.choices(keys, weights)[0]` | main | `choices` with int weights (respawn: float weights `w / xp ** 0.5`): `cum = accumulate(weights)`, `total = cum[-1] + 0.0`, `bisect_right(cum, random() * total, 0, n - 1)` |
| `world.py:347` | `rng.random() >= chance` per room | main | |
| `world.py:350-351` | `rng.choice(spots)`, `rng.choices(keys, weights)` | main | `choice` = `seq[_randbelow(len(seq))]` |
| `world.py:377` | `rng.choice(spots)` (`_free_spot`) | main | |
| `world.py:382` | `rng.shuffle(rooms)` (Act rooms) | main | |
| `world.py:404` | `rng.choice(rooms)` up to 10 tries (respawn) | main | |
| `world.py:700, 745, 803, 1090, 1218, 1225` | `attack(..., self.rng, ...)` | main | via dice |
| `world.py:983` | `roll(self.rng, *item["dice"])` (bombs) | main | |
| `world.py:992` | `saving_throw(self.rng, ...)` per monster in blast | main | |
| `world.py:1347` | `d20(self.rng)` (initiative) | main | |
| `ai.py:92` | `world.rng.random() < RANGED_ATTACK_CHANCE` | main | short-circuit: only drawn when the earlier conditions hold |
| `ai.py:132-133` | `rng.random() < MONSTER_WANDER_CHANCE`, `rng.choice(NEIGHBOURS_8)` | main | |
| `world.py:614` | `loot_rng.random() < 0.04 * tinkering` | loot | drawn even at level 0 (left operand evaluated first) |
| `world.py:829` | `loot_rng.choices(("tonic", "brew", "elixir"), (6, 3, 1))[0]` | loot | |
| `world.py:1036` (`loot.py:32`) | `roll_box`: `rng.choices(keys, weights)[0]` | loot | |
| `world.py:1148` | `loot_rng.uniform(0.6, 1.4)` | loot | `uniform` = `a + (b - a) * random()` |
| `world.py:1176` | `loot_rng.choice(C.HEADLINER_DROPS)` | loot | |
| `world.py:1179-1180` | `loot_rng.random() < ITEM_DROP_CHANCE`, then `choice(drops)` | loot | |
| `world.py:1209` | `loot_rng.choices(keys, weights)[0]` x2 | loot | |
| `shop.py:91` | `self.rng.random()` in Knuth Poisson loop | shop | |
| `world.py:278-279` | `deal_rng.random() < OFFER_CHANCE`, `deal_rng.choice(sorted(CONTRACTS))` | deal | only from floor 2 (`depth >= OFFER_FROM_FLOOR` is checked first) |
| `showrunner.py:125, 128` | `rng.random() >= QUIP_CHANCE`, `rng.choice(lines)` | show | |
| `showrunner.py:134, 138` | `rng.random()` (spice), `rng.choice(pool)` | show | |
| `showrunner.py:159` | `rng.random() >= SPEAK_CHANCE * chattiness` | show | |
| `bot.py:234-237` | `pick.choice(RACES)`, `choice(CLASSES)`, `choice(STORIES)`, `choice(list(GENDERS))` | bot pick | |
| `bot.py:252`, play loop | `coin.random() < 0.5` per offer | bot coin | |
| `save.py:20-26` | `getstate()` / `setstate()` on main, loot, deal, shop, show | all | state is `(3, (624 words + index), None)`; the save stores `[list_of_625_ints, null]` |

Short-circuit evaluation decides whether a draw happens in several places (`ai.py:92`, `world.py:347`, `world.py:614`, `world.py:278`). GDScript `and` / `or` also short-circuit, so keep each condition in the same position.

### 5.3 `PyRandom` required API (`godot/rules/py_random.gd`)

Implemented in P0 with this surface; names in brackets are what the code uses.

```gdscript
class_name PyRandom
extends RefCounted

var words_used: int = 0          # 32-bit outputs drawn so far (trace counter)

func _init(seed_value: int = 0) -> void      # = seed_int(seed_value)
func seed_int(n: int) -> void                # CPython random_seed: abs(n) split into 32-bit words, little end first;
                                             # n == 0 gives key [0]; then init_by_array(key) (init_genrand(19650218) first)
func genrand_uint32() -> int                 # MT19937 with tempering; increments words_used
func random() -> float                       # (a >> 5) * 67108864.0 + (b >> 6), times 1.0 / 9007199254740992.0
func getrandbits(k: int) -> int              # k <= 32: genrand_uint32() >> (32 - k); 32 < k <= 62: words little end first,
                                             # the top word shifted right by (32 * words - k); k == 0 returns 0 with no draw
func randbelow(n: int) -> int                # _randbelow_with_getrandbits: k = bit_length(n); r = getrandbits(k); while r >= n: redraw
func randrange(start: int, stop = null, step: int = 1) -> int
func randint(a: int, b: int) -> int
func choice(seq: Array) -> Variant           # seq[randbelow(seq.size())]; push_error and null on empty
func choices(population: Array, weights = null, k: int = 1, cum_weights = null) -> Array
                                             # no weights: population[floor(random() * n)]; weights: int accumulate stays int,
                                             # float accumulate is left-to-right float addition; total = float(cum[-1]);
                                             # bisect_right(cum, random() * total, 0, n - 1)
func shuffle(x: Array) -> void
func sample(population: Array, k: int) -> Array   # setsize = 21, plus 4 ** ceil(log(k * 3) / log(4)) when k > 5;
                                                  # pool branch if n <= setsize else set branch (redraw on repeats)
func uniform(a: float, b: float) -> float
func get_state() -> Array                    # [624 words..., index] (625 ints), the save format's first element
func set_state(state: Array) -> void
func state_digest() -> String                # sha256 hex of "index,w0,...,w623" (HashingContext), for traces
static func bit_length(n: int) -> int
```

`randbelow(1)` still draws (CPython redraws `getrandbits(1)` until it gets 0); nothing in the game calls `randint(a, a)`, but keep the semantics. Every method needs exact semantics except `getrandbits` above 63 bits (use `getrandbits_words`) and `choices(cum_weights=...)`, which nothing uses. `tools/check_py_random.gd` with `scripts/py_random_reference.py` is the P0 proof; the same check also runs as `tests/test_py_random.gd` (116 parametrised seeds).

### 5.4 Iteration order that affects rules or RNG consumption

| Place | What is iterated | Effect | Exact match? |
|---|---|---|---|
| `entities.monster_table` | `MONSTERS` dict order | maps `choices` index to a monster | Yes: JSON key order |
| `items.floor_loot_table` | `FLOOR_LOOT` list | maps `choices` index | Yes: array |
| `loot.roll_box` | box table list | maps index | Yes |
| `shop.end_of_floor` | `self.stock` (from `BASE_DEMAND` order) | Poisson draw order | Yes: JSON key order |
| `world.new_floor` | `sorted(CONTRACTS)` | `deal_rng.choice` index | Yes: string sort by code point |
| `achievements._on_event` | `ACHIEVEMENTS` dict order | unlock order, so box, toast, message and event order (and `show` draws per `achievement` event) | Yes |
| `Achievements.__init__` | a `set` of event names (`{a["on"] for a in ...}`), Python string hashing, random per process | only which event lists get the `_on_event` subscriber, and each event gets exactly one, appended during the same constructor call | Order-insensitive: no effect on rules. GDScript iterates a de-duplicated Array in first-seen order. |
| `EventBus` subscriber lists | subscription order: `Practice` (World `__init__`), `Achievements`, `Showrunner` (LINES order for `_announce`, then `_box_reaction`, `_viewers`, `_idle`, `_pet_quip`), `FunFacts`, then later `Telemetry` | which handler runs first, so `show` draw order and message order | Yes, if constructors subscribe in the same order. Nested emits are depth first in both. |
| `Showrunner.__init__` | `LINES` keys | subscription per event | Yes |
| `Practice.__init__` | fixed tuple of listeners | per event order | Yes |
| `bot.spend_points` | `targets` dict (with key collision when the fight and class attributes coincide) | `max(gaps, key=gaps.get)` tie order | Yes: Godot Dictionary keeps the first insertion position on overwrite |
| `bot._choose` | `w.floor_items` dict (`loot = [xy for xy in w.floor_items ...]`), then `min(..., key=cheb)` | first minimum wins | Yes: insertion order, erase and re-insert go to the end in both |
| `world.update_fov`, `_respawn`, `ai` | `self.visible` (a `set` of int tuples) | only membership and marking `explored` | Order-insensitive |
| `ai._occupied`, `taken`, `Encounter.reacted`, `World._acted`, `FunFacts.said`, `Practice.used`, `Tracker.equipped`, `sample`'s `selected` | sets | membership, subset, or sorted before saving | Order-insensitive |
| `dice.dice_distribution` | dict built in a fixed loop | float summation order in `expected_damage` | Yes (same insertion order) |
| `telemetry` row dicts | insertion order | CSV column order | Yes |

Result: no set or dict iteration feeds the rules in an order that GDScript cannot reproduce. Python's per-process string hash randomisation touches only the `Achievements.__init__` set, which is order-insensitive. Int and tuple sets (deterministic in Python but dependent on table size and history) are only used for membership. So no "sort in both versions" fix is needed; if a future change iterates a set, the owner should decide to sort at that point in both versions (Python is frozen, so that is an owner call).

---

## 6. Parity traces

### 6.1 What both versions emit

JSON Lines, UTF-8, one object per line. Both sides write the same records in the same order; `scripts/parity_diff.py` parses both and compares values (so cosmetic number formatting cannot cause a false failure).

**Normative spec.** The docstrings at the top of `scripts/py_trace.py` (records, digests, floor sections, CLI) and `scripts/trace_policies.py` (actions and policy decision orders) are the normative definition of the trace; where this section and those docstrings differ, the docstrings win. Differences from the first draft of this table: the header gains a trailing `"mode"` (`"run"`, `"floors"` or `"floors_world"`); `act` gains a trailing `"pr"` (words used by the policy's own stream after the action); the `floor` record in floor-only mode carries extra fields (`words`, `tiles`, `safe` as row strings, `rooms`, `start`, `safe_room`, `safe_door`, `stairs`, `furniture`; with `--spawns` also `player`, `timer` `[timer, timer_max]`, `monsters` and `items`); the floor fingerprint has eight `#`-separated sections (pure `generate_floor` mode uses the first six); the state digest hashes `"index,w0,...,w623"`.

| Record | When | Fields |
|---|---|---|
| `header` | first line | `{"k": "header", "impl": "python" or "godot", "trace_version": 1, "seed": 5, "policy": "hunter", "steps": 3000, "pet": null, "hero": null, "content_sha": "<sha256 of manifest.json>"}` |
| `ev` | every `EventBus.emit`, before dispatch (pre-order: an outer event precedes the events its handlers emit) | `{"k": "ev", "i": 1234, "t": turn, "d": depth, "e": "kill", "p": {payload}, "r": [main, loot, shop, deal, show]}` where `r` holds `words_used` per stream at that moment. Payload is the event data as emitted (ints, floats, strings, bools, null). |
| `turn` | on each `turn` event (inside `_tick_clock`, after the counter moves) | `{"k": "turn", "t": turn, "pos": [x, y], "hp": hp, "max_hp": m, "timer": timer, "state": "playing", "gold": g, "viewers": v, "combat": round or null, "pet": [x, y, hp, downed] or null, "mon": "<sha256/16 of monster list>", "inv": ["tonic", ...]}` |
| `floor` | on `floor_start` | `{"k": "floor", "depth": d, "fp": "<sha256/16 of tiles, safe, rooms, stairs, furniture, safe_door, floor_items, monsters>", "rs": ["<state_digest/16 per stream>"]}` |
| `act` | each policy action, after it returns | `{"k": "act", "n": 17, "a": "move", "arg": [1, 0], "ok": true}` |
| `msg` | each `MessageLog.add` | `{"k": "msg", "text": "You hit the Knockoff Goblin for 6. (d20 14+4=18 vs AC 11)", "c": [225, 222, 235]}` |
| `end` | last line | `{"k": "end", "state": "dead", "turn": 953, "depth": 2, "cause": "Killed by a Sewer Gnawer on floor 2", "rs": [...]}` |

Canonical monster string, hashed with SHA-256 and cut to 16 hex characters: for each monster in list order, `key:x:y:hp:max_hp:alerted:unseen_turns:stunned:phase:dmg_bonus`, joined with `|`, booleans as `1`/`0`. Floor fingerprint: tiles row by row as digits, then `safe` and the other parts in the order listed, each section separated by `#`.

### 6.2 Producing it without changing rules

Python, `scripts/py_trace.py` (imports `crawler` read-only; nothing in `crawler/` changes):

- `CountingRandom(random.Random)` overrides both `random()` (counts 2) and `getrandbits(k)` (counts `ceil(k / 32)`, 0 for `k == 0`). Overriding `getrandbits` keeps CPython's `_randbelow_with_getrandbits` (the subclass hook picks it when `getrandbits` is defined), so draws are unchanged. The harness sets `random.Random = CountingRandom` before constructing the World, and records instances in creation order (main, loot, shop, deal, show; then bot pick and coin).
- `TracingEventBus(EventBus)` and `TracingMessageLog(MessageLog)` record and then call the parent; the harness assigns them to `crawler.world.EventBus` and `crawler.world.MessageLog` before `World(...)`, so the floor 1 events and messages emitted inside the constructor are captured.
- A `turn` snapshot is written from the `ev` hook when the event name is `turn`; `floor` from `floor_start`.
- Policies (6.4) drive the World and write `act` records.
- The bot-pick stream (`run_config`, 4 draws from `random.Random(seed * 7919 + 13)`) is created outside the patch and is not counted or traced. The policy stream (`seed ^ 0x7ACE`, or `seed ^ 0xB07` for the bot coin) is a `CountingRandom` reported as `pr` in `act` records. `py_trace.py` asserts that exactly five streams were created by `World(...)`.
- Default output path without `--out`: `./trace_<seed>.jsonl`; `--seeds A-B --out-dir D` writes `<policy>_<seed>.jsonl` (`floors_<seed>.jsonl` for floor-only).

**Notes for `godot/tools/trace.gd`**

- (a) The world must be reachable from the tap before floor 1's `floor_start` fires (the `floor`, `turn` and `ev` records read world state): assign `events.tap` / pass the world before `new_floor(1)`. `t` and `d` are 0 in `ev` records emitted before the first `new_floor`.
- (b) Floats are written with round-trip precision (`PyFmt.repr_float`, never `JSON.stringify` defaults). Every numeric field that goes into a hash input (monster string, floor sections, state digest) is formatted as a decimal int (beware `round()` returning a float, which would print `14.0`). Colours are ints 0-255. Bools stay bools.
- (c) `spend_points`, `manage_items` and the remote `shop_buy` after a Supply Drop call the World directly and produce no `act` records, so `trace_policies.gd` must do exactly the same.

Godot, `tools/trace.gd` (`extends SceneTree`): sets `world.events.tap` and `world.messages.tap` before the first floor is built (`World.new(seed, pet, hero, tap_events, tap_messages)` takes two optional Callables for this; no rule reads them), reads `words_used` and `state_digest()` from the five streams, and runs the same policies from `tools/trace_policies.gd`.

```
python scripts/py_trace.py --seed 5 --policy hunter --steps 3000 --out /tmp/py.jsonl [--pet cat] [--no-msg]
godot --headless --path godot -s res://tools/trace.gd -- --seed 5 --policy hunter --steps 3000 --out /tmp/gd.jsonl
python scripts/parity_diff.py /tmp/py.jsonl /tmp/gd.jsonl [--scope core|full] [--context 12]
```

### 6.3 `scripts/parity_diff.py`

- Streams both files record by record. Compares `k`, then every field; numbers compare by value (`float(a) == float(b)`, ints exactly), strings exactly.
- On the first difference prints: the record index, the turn and depth, the last `--context` records from both sides (side by side), the field path that differs, and the RNG counter delta at that point (if `r` differs first, the cause is an extra or missing draw just before it, which narrows it to one call site in 5.2). Exit code 1.
- `--scope core` (P1): ignores `msg` records, the `i` counter of `ev` records, the `show` counter (index 4 of `r`, `rs` and a floor record's `words`), `viewers` in `turn`, events from systems still stubbed in P1 (`achievement`, `box_gained`, `viewers_gained`, `sponsor_gift`, `fun_fact`), `practice_level` events for `showmanship` (Python trains it from `viewers_gained`, which the stand-in never emits) and the `many_at_3` field of other `practice_level` payloads. `--scope full` (P2 onward) compares everything. The header's `impl` is never compared.
- A missing or malformed file (bad JSON line) is reported as a failure for that pair (`file X line N malformed`), exit 1, no traceback. On a divergence that is not in `r`, the last `ev` RNG counters of both sides are printed as well. `--dirs DIR_A DIR_B [--seeds lo-hi]` compares same-named files and carries on past a bad pair.
- The CSV compare mode (`--csv DIR_A DIR_B`: telemetry tables cell by cell, floats by value, byte differences reported separately) is implemented (slice T4): bytes first, then cells; see the T4 notes in B.2.
- Exit 0 prints `PARITY OK: <n> records, <turns> turns`.

### 6.4 Seeds and scripted sequences

Policies live in both `scripts/trace_policies.py` and `godot/tools/trace_policies.gd`, written line for line alike, and use their own stream: `random.Random(seed ^ 0x7ACE)` for `walk` and `hunter`, `random.Random(seed ^ 0xB07)` (the bot's coin) for `bot`; the trace counts it as `pr`. The docstring of `scripts/trace_policies.py` is normative. If a policy's main action returns False, the policy then performs `wait` (a second `act` record with the same `n`), as `bot.play` does.

| Policy | What it does | Purpose |
|---|---|---|
| `walk` | each step picks one of 9 actions (8 moves, wait) with `randrange(9)` | dungeon, FOV, wandering, monsters noticing you, combat starting by monster, opportunity attacks |
| `hunter` | first rule that yields an action: (1) hp*100 < max_hp*45 and not in a safe room: `use` the first inventory index holding tonic, brew or elixir; (2) attack an adjacent monster (first in list order); (3) `pickup` when standing on floor items with fewer than 16 carried; (4) step towards the nearest visible monster (first minimum by Chebyshev distance; bosses only when the exit is sealed); (5) step towards the nearest unexplored room centre; (6) `descend` on open stairs; (7) step towards the nearest stairs; (8) wait. A step is one downhill move on `floor.distance_map` (NEIGHBOURS_8 order, strictly smaller distance); no step means the rule is skipped | combat mode, kills, gold and drops (loot stream), floors 1-2, stairs timing. Note: it usually dies on floor 1; use `bot` for deep floors |
| `bot` | `analysis/bot.py` `choose`, `spend_points`, `manage_items` inside `bot.play`'s loop (class pick when pending, coin flip `coin.random() < 0.5` per offer; pet, hero, race and class from `run_config(seed)`, whose 4 draws on the uncounted `seed * 7919 + 13` stream are not traced). Godot mirror: `BotPolicy` (P2) | everything |

| Phase | Check | Seeds | Pass condition |
|---|---|---|---|
| P0 | `PyRandom` vs CPython | the 116 seeds in `py_random_reference.py` | identical outputs |
| P1 | `Dungeon.generate_floor` x6 from one `PyRandom(seed)` | 0-199 | identical floor fingerprints and `words_used` |
| P1 | `World.new(seed)` initial floor (monsters, items, boss, Acts) | 0-499 | identical `floor` record |
| P1 | `walk`, 500 actions, no pet, no hero | 0-49 | `--scope core` OK |
| P1 | `hunter`, 3,000 actions, no pet | 0-49 | `--scope core` OK |
| P2 | `hunter` with each pet (`seed % 4`) and a hero | 50-99 | `--scope full` OK |
| P2 | `bot` full runs with telemetry | 0-99 | `--scope full` OK, and CSV tables identical |
| P2 | save at the first safe-room visit of bot seed 7 in Python, load in Godot, continue | 7, 11, 23 | traces identical after load (R5 is resolved: floats in a Python save load exactly in the game's ranges, see B.2 T5) |
| P3 | Godot bot 2,000 runs | 0-1999 | `runs/bot_{runs,floors,boxes,shop,practice}.csv` identical to the committed files; if not, statistical parity (win rate and floor-of-death distribution within 95% intervals) and a report on the first diverging seed |

Fixture tests (part of the normal test run, generated by `scripts/make_fixtures.py` into `godot/tests/fixtures/*.json`): dice and attack sequences, `chance_to_hit` and `expected_damage` tables, floors for seeds 0-9, box rolls, `repr_float` and `fixed` cases for every float the game writes, `fsum_py` cases.

---

## 7. Test framework

### 7.1 GUT vs GdUnit4

| Criterion | GUT 9.x (Godot 4 line) | GdUnit4 (v5/v6 line for Godot 4.x) |
|---|---|---|
| Headless CI | `godot --headless -s addons/gut/gut_cmdln.gd -gdir=res://tests -ginclude_subdirs -gexit` works headless | CLI tool refuses headless mode by default (input simulation needs a display); needs `--ignoreHeadlessMode`; wrapper scripts (`runtest.sh`) expect `GODOT_BIN` |
| Exit codes | `-gexit` exits 0 when all pass, 1 on any failure | non-zero on failure (100 for failures; other codes for warnings), documented in its CLI |
| Parametrised tests | `func test_x(p = use_parameters([[1, 2], [3, 4]]))`, `ParameterFactory.named_parameters`: close to `pytest.mark.parametrize` | `func test_x(a: int, b: int, test_parameters := [[1, 2], [3, 4]])`: typed and neat |
| Assertions | `assert_eq`, `assert_ne`, `assert_true`, `assert_almost_eq`, `assert_has`, `assert_gt` ...: one call per pytest `assert`, so translation is mechanical | fluent `assert_int(x).is_equal(5)`, `assert_array(...)`: richer, more rewriting per assert |
| Layout | any `test_*.gd` extending `GutTest` under the configured dirs; `.gutconfig.json` | suites extending `GdUnitTestSuite`, test dirs configured; HTML and JUnit reports in `reports/` |
| Doubles, spies, input | `double()`, `stub()`, `spy`, `watch_signals`, `InputSender` | mocks and spies, `scene_runner` with input and frame stepping (strong for UI tests) |
| Reports | JUnit XML (`-gjunit_xml_file`) | HTML and JUnit XML |
| Weight and coupling | pure GDScript, small, tolerant across Godot minors | larger, releases track Godot minor versions closely, editor plugin |
| Fit for this project | rules tests are plain RefCounted logic ported from pytest; headless is the main mode | best for P4-P7 scene tests; heavier for the bulk of rules tests |

Recommendation: **GUT 9.x**, pinned to the release that lists Godot 4.7 support, vendored under `godot/addons/gut/` once GitHub or the Asset Library is reachable. Reasons: about 85% of the tests are headless rules tests whose pytest asserts map one to one onto GUT's assert functions; `use_parameters` mirrors `parametrize`; the CLI runs headless without flags and returns a plain 0/1; it is pure GDScript and small. GUT's doubles and `InputSender` are enough for the UI tests because the state machine is headless (`AppState`) and scene tests only need instantiation, a few frames and screenshots. If the owner later wants GdUnit4's scene runner for P8 juice tests, both can coexist in one project (separate dirs).

### 7.2 GUT in this project (in place since P1)

GUT 9.7.1 is vendored in `godot/addons/gut/` (MIT, from the v9.7.1 tag). The P0 stopgap runner was retired.

```
godot/.gutconfig.json     # dirs, prefix test_, should_exit; add res://tests/ui/ when UI tests arrive
godot/tests/
  support/test_case.gd    # class_name TestCase extends GutTest: type-strict assert_eq/assert_ne/assert_eq_deep
  support/helpers.gd      # class_name TestHelpers: world factories, tmp dirs, patching
  fixtures/               # generated by scripts/make_fixtures.py
  test_*.gd               # one per pytest file (Appendix B), each `extends TestCase`
```

- Every test file `extends TestCase`, not `GutTest` directly. GUT's own `assert_eq` treats `1 == 1.0` as equal and its deep compare ignores dictionary key order; `TestCase` makes both fail.
- Parametrised tests: `func test_x(p = use_parameters([...]))`, as in GUT.
- GUT fails a test on any unexpected `push_error`. A test that expects one says so with `assert_push_error("text")`.
- `TestHelpers.restore_patches()` is called from each file's own `after_each()`.
- Keep `include_subdirs` off: `support/test_case.gd` matches the `test_` prefix.

`scripts/gd_test.sh [--file=<substring>] [--test=<substring>] [other GUT flags]` imports the project, regenerates the Python references, runs `addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json`, and passes only if Godot exits 0, GUT prints `All tests passed!`, and no `SCRIPT ERROR`, `Parse Error`, `Failed to load script` or `Failed to compile` line appears.

---

## 8. Project layout, autoloads, headless runs, telemetry

### 8.1 Layout

```
godot/
  project.godot            # main scene res://scenes/main.tscn; input map (10.5); autoload Game (presentation only)
  rules/                   # headless rules, class_name per file, no Nodes
    py_random.gd
    py/ py_math.gd py_fmt.gd py_json.gd py_csv.gd
    content.gd game_config.gd event_bus.gd message_log.gd
    dice.gd attributes.gd combat.gd attack_result.gd
    dungeon.gd dungeon_floor.gd dungeon_room.gd
    entity.gd player.gd monster.gd pet.gd entities.gd
    encounter.gd ai.gd bosses.gd items.gd loot.gd crafting.gd contracts.gd
    shop.gd shop_stock.gd practice.gd achievements.gd achievement_tracker.gd achievement_rules.gd
    showrunner.gd fun_facts.gd run_report.gd
    world.gd save_game.gd user_settings.gd telemetry.gd
  data/                    # generated JSON + manifest.json (never hand-edited)
  scenes/                  # .tscn: main, fp_view, top_view, hud, menus/, screens/
  ui/                      # presentation scripts: app_state.gd, main.gd, fp/, top/, hud/, menus/, screens/, theme/crawl_theme.tres
  tests/                   # 7.2
  tools/                   # SceneTree CLIs: bot.gd, bot_policy.gd, trace.gd, trace_policies.gd, check_py_random.gd, screenshots.gd
  assets/                  # P9 (art bible layout), CREDITS.md
scripts/                   # repo root: export_content.py, make_fixtures.py, py_trace.py, trace_policies.py, parity_diff.py,
                           # gd_test.sh, gd_bot.py, py_random_reference.py, setup_godot.sh
```

### 8.2 Autoloads

Rules never use autoloads. Presentation has one: `Game` (`ui/game.gd`, a Node): holds the current `World`, `UserSettings`, the `Telemetry` for player runs and paths (`user://saves/slot1.json`, `user://settings.json`, runs dir); switches top-level scenes. Audio (`Sfx`) may be added in P8. Tests of rules never load `Game`.

### 8.3 Headless tests

```
scripts/gd_test.sh                       # all
scripts/gd_test.sh --file=test_dungeon   # one file
```

### 8.4 Headless bot

```
godot --headless --path godot -s res://tools/bot.gd -- --runs 100 --start 0 --runs-dir /abs/path/runs_gd --deals random [--pet cat] [--no-events] [--summary-only] [--summary-out FILE]
python scripts/gd_bot.py --runs 2000 --workers 4 --no-events --out runs_gd     # shards seeds over worker processes, merges shard CSVs in seed order
```

`tools/bot.gd` mirrors `analysis/bot.py main()`: deletes old `bot_*.csv` when `--start 0`, writes with prefix `bot_`, prints the same summary lines (formatted with `PyFmt`). Process sharding replaces `multiprocessing.Pool` (Godot threads would also work since rules share only read-only statics, but processes keep each run isolated and the merge order trivial). `--runs-dir` (default `user://runs`, owner decision 5; `gd_bot.py` calls it `--out`, default `runs_gd`) takes an absolute path or one relative to the shell's directory.

### 8.5 Telemetry CSV writer

`Telemetry` builds rows as Dictionaries with keys inserted in exactly this order (the committed headers):

| Table | Columns |
|---|---|
| runs | run_id, source, seed, pet, race, backstory, gender, cls, outcome, depth, turns, kills, level, gold, viewers, peak_viewers, boxes, achievements, practice_levels, death_cause, then `meta` keys (bot: deals) |
| floors | run_id, source, depth, turn, hp, max_hp, hp_frac, level, str, dex, con, int, cha, attack, ac, dmg_avg, potions, bombs, gold, boxes, cls, race, backstory, pet, pet_level, pet_down, timer_max, viewers, contract, damage_taken, gold_earned, kills_here, viewers_gained, result, died_here |
| boxes | run_id, source, tier, item, value, ev, rerolled, turn, reason |
| shop | run_id, source, depth, item, demand, sales, lost, delivered, on_hand, forecast_before, forecast, reorder_point, ordered |
| practice | run_id, source, skill, level, used |
| events | run_id, turn, floor, event, value, detail |

`PyCsv.write_tables(tables, out_dir, prefix, skip)`: appends to `<out_dir>/<prefix><name>.csv`, writes the header when the file is new or empty, skips empty tables, header from the first row's keys. Cells: `null` gives empty, `bool` gives `True`/`False`, int plain, float `PyFmt.repr_float`, strings as is; a cell is quoted (with `"` doubled) when it contains `,`, `"`, `\r` or `\n`; every line ends `\r\n` (the committed files use CRLF). Event `value` is the first `VALUE_KEYS` entry that is an int or float but not a bool, else empty; `detail` is `PyFmt.str` of the first `DETAIL_KEYS` entry that is neither null nor `""` (so a `pet_kill` row's detail is `False`, as in Python).

---

## 9. Porting order

Owner's grouping in `PHASES.md`: P1 rules core, P2 rules systems. One deviation proposed (flagged in section 11, Q1): `world.py` and `ai.py` are each ported whole in P1, including the pet, class-skill, box, shop and contract methods that live in them, because splitting one file across parallel briefs causes merge conflicts. Those features are still verified in P2 (their traces need the P2 systems). P2 then ports the separate listener systems, which touch disjoint files and can run in parallel.

P1 systems not yet ported are minimal stand-ins in `rules/` with the final class names and constructor signatures: `Achievements` (subscribes, does nothing), `Showrunner` (`viewers = 50`, `peak`, `history`, `samples`, owns its `PyRandom` but never draws), `FunFacts` (no-op). None of them touch the main, loot, shop or deal streams in Python, so P1 core traces stay comparable.

### 9.1 Slices

Each slice is one rules-porter brief (about 300-600 Python lines plus tests).

| Slice | Content | Depends on | Tests ported | Parity evidence |
|---|---|---|---|---|
| P0 (done) | `py_random.gd`, `export_content.py` and `godot/data/`, `support/` test base (GUT since P1), bare `project.godot` loading data headless | | `test_py_random`, `test_content` | 116 RNG seeds |
| S1 Foundations | `py_math`, `py_fmt`, `py_json`, `game_config`, `event_bus`, `message_log` (`content` was delivered in P0) | P0 | `test_py_math`, `test_py_fmt` (fixtures from Python) | fixtures |
| S2 Dice and combat | `dice`, `attributes`, `entity`, `player`, `monster`, `pet`, `entities`, `attack_result`, `combat` | S1 | `test_combat`, `test_attributes::test_modifier_table` | dice and attack fixtures per seed |
| S3 Dungeon | `dungeon`, `dungeon_floor`, `dungeon_room` (generation, safe room, distance maps, FOV) | S1 | `test_dungeon` | floors seeds 0-199 |
| S4 Small rules modules | `encounter`, `bosses`, `items`, `loot`, `crafting`, `contracts` (effect and preview), `shop`, `shop_stock`, P1 stand-ins | S2 | `test_loot` (data and odds parts), shop policy tests from `test_phase4` | box roll and Poisson fixtures |
| S5 Practice | `practice` | S1 (S2 for types) | `test_practice::test_xp_curve...` | |
| S6 World A | `world.gd` lines 1-460 of `world.py`: init, traits, `refresh_stats`, attributes, prices, floors and spawns, queries, timer | S2, S3, S4, S5 | `test_attributes` (rest), `test_floors` (spawn parts) | World init fingerprint seeds 0-499 |
| S7 World B and AI | `world.py` 1084-1557 (attacks, kills, drops, Acts, combat mode, opportunity attacks, turn flow) and `ai.gd` whole | S6 | `test_world`, `test_encounter` (non-save parts) | `walk` seeds 0-49 |
| S8 World C | `world.py` 468-1080 (move, wait, descend, rest, safe-room activities, craft, shop trades, pet methods, class and skills, items, bombs, boxes) | S7 | `test_items`, `test_floors`, `test_phase3` (non-save), `test_phase4` (world parts), `test_achievement_loot` (world parts) | `hunter` seeds 0-49 core |
| S9 Trace tooling (parallel from S1) | `scripts/py_trace.py`, `trace_policies.py`, `parity_diff.py`, `make_fixtures.py`, `godot/tools/trace.gd`, `trace_policies.gd` | S1 for the Godot half | self-test: a Python trace diffed against itself and against a deliberately perturbed copy | |
| T1 Achievements | `achievements`, `achievement_tracker`, `achievement_rules` | S8 | `test_showrunner` (achievement tests), `test_achievement_loot` | |
| T2 Showrunner | `showrunner` (lines, viewers, sponsor gifts, pet quips) | S8 | `test_showrunner` | `show` stream counters |
| T3 Fun facts and report | `fun_facts`, `run_report` | S8 | `test_phase4` (fun facts, report) | |
| T4 Telemetry | `telemetry`, `py_csv` | S8 | `test_telemetry` (writer parts) | CSV fixtures |
| T5 Save and settings | `save_game`, `user_settings` | T1, T2, T3 | save tests in `test_phase3`, `test_phase4`, `test_practice`, `test_encounter`; `test_settings` | Python save loaded in Godot |
| T6 Bot | `tools/bot_policy.gd`, `tools/bot.gd`, `scripts/gd_bot.py` | T1-T4 | `test_telemetry` (bot parts), `test_encounter::test_bot_*` | `bot` seeds 0-99 full, CSVs |

Parallelism:

```
P0 ─ S1 ─┬─ S2 ─┬─ S4 ─┐
         │      └──────┼─ S6 ─ S7 ─ S8 ─┬─ T1 ─┐
         ├─ S3 ────────┤                ├─ T2 ─┼─ T5 ─┐
         ├─ S5 ────────┘                ├─ T3 ─┘      ├─ T6 (P2 sign-off) ─ P3
         └─ S9 (tooling, any time after S1)  └─ T4 ──────┘
```

- In parallel: S2, S3, S5 and S9 after S1; S4 after S2 alongside S3; T1, T2, T3 and T4 after S8.
- Sequential: S6, S7, S8 (one file); T5 after the systems whose state it saves; T6 last.
- P4 (presentation) can start on fixtures and a fake world once S8 lands; it does not need P2 or P3.

---

## 10. Presentation mapping (P4 to P7)

### 10.1 First-person 3D (P4)

- Recommendation: **generated meshes, not GridMap.** `FloorMeshBuilder.build(floor: DungeonFloor, depth: int) -> Node3D` uses `SurfaceTool` to emit only visible wall faces (a wall side next to a walkable tile), floor and ceiling quads, one surface per material: wall (2-3 variants chosen by a tile hash), safe wall, floor, safe floor, ceiling, stairs open, stairs locked. Reasons: per-floor tint and the "safe rooms and stairs never tinted" rule are just materials; variants by tile hash and the explored state need no MeshLibrary juggling; a 120 x 76 floor builds in milliseconds; and it is testable headless (count faces, check materials). GridMap would need a MeshLibrary item per variant and per tint (GridMap has no material override) and draws hidden cube faces, for no gain on a static grid.
- Look: render at 320 x 200 in a `SubViewport` shown through a `TextureRect` with nearest filtering (hard pixels, as now); textures 64 x 64, `TEXTURE_FILTER_NEAREST`, no mipmaps (art bible section 3). `Camera3D` with a 70 degree horizontal FOV (`PLANE = 0.70`, `keep_aspect = KEEP_WIDTH`); walls 0.875 tiles high with the eye at 0.4375 (half the wall). Why (lead decision in P4, replacing the earlier 1.0 / 0.5): Python's raycaster draws a wall `200 / d` pixels tall while its horizontal half-width is 0.7, so its pixels are not square; with Godot's square pixels a 1.0-tile wall came out `228 / d` (about 14% taller), and 0.875 = 2 x 0.7 x 200 / 320 gives exactly `200 / d`. Billboard sizes scale with the wall height too. `WorldEnvironment` depth fog ending at `LIGHT = FOV_RADIUS + 0.5` tiles, plus an `OmniLight3D` torch on the camera with the same range (steady in P4; flicker waits for P8 so screenshots stay repeatable); tint per floor from `ui_config.json` `DEPTH_TINT`.
- Billboards (P5): `Sprite3D`, `billboard = BILLBOARD_FIXED_Y`, `alpha_cut = ALPHA_CUT_DISCARD` (binary alpha), `texture_filter = NEAREST`, `pixel_size` so a 32 px sprite is `scale` tiles tall (monsters 0.62-0.71 by HP, Acts 0.85 / 0.95, Headliners 1.0, pets 0.5, furniture 0.75, items 0.32), feet on the floor; tier outline by a small shader or a second slightly larger sprite.
- Camera behaviour: `FpCameraRig` (Node3D) runs `fp_logic.gd` maths in `_process(delta)` with `delta` capped at `MAX_DT` 0.05: free look (hold Q/E after `HOLD_DELAY` 0.2 s at `TURN_RATE` 180 degrees a second; a tap turns to the next 45 degree line), glide at `WALK_SPEED` 4 tiles a second and `TURN_SPEED` 2 pi radians a second, snap when the gap exceeds 2.5 tiles or on `dt >= 1`, held walking issues the next step when the glide has under `NEXT_STEP` 0.15 tiles left and at least `STEP_GAP` 0.2 s have passed, and stops after a blocked step or an attack until the key is released.
- Grid-locked combat: `sync_combat()` each frame: when `world.combat != null`, `set_combat(true)` rounds the angle to the nearest 90 degrees (the camera glides there), W/S/A/D act on key press only (`_unhandled_input`), Q/E turn 90 degrees; held walk keys present at the start of the fight are marked stopped. Free look resumes when `combat` becomes null.

### 10.2 Top-down (P5)

`TileMapLayer` for terrain and furniture (a TileSet built from the 16 px glyph look first, the 32 px DCSS tiles in P9 per art bible question 1), a second `TileMapLayer` or a shader with an `ImageTexture` of explored and visible flags for fog (darken remembered tiles in code, no "dim" art). Entities as `Sprite2D` or glyph `Label` nodes; boss tier boxes and the orange provoke brackets drawn in `_draw`. `Camera2D` follows the player with the same clamping as `Renderer._camera`.

**P9 as built.** `TopView` has two zooms over the same 1024 x 640 map area: `"tiles"` (32 px art tiles, a 32 x 20 tile window, the real game's default) and `"glyphs"` (the 16 px overview, 64 x 40 tiles, pixel-identical to pygame; a bare `AppState` and every pairing tool start there). The art TileSet is built per floor (`TopView.build_art_tile_set(depth)`): lit and dim columns share one picture, and the floor's `DEPTH_TINT` and the fog ratio (0.46) are the tiles' `modulate`, so nothing is baked into the art; safe floors and safe-room edges are never tinted; the edge of a safe room (every wall next to a safe floor) uses the pale `tile:safe_wall`; one wall block in three uses the second brick picture by the same hash as the first-person mesh. `TopMarks` draws stairs (`tile:stairs_open|locked`, padlock on the locked one), furniture, items, creatures, your pet and you (`SpriteArt.player(race)`, white outline) as 32 px pictures, with the tier boxes (2 px, 3 px for a Headliner), provoke brackets (3 px by 10) and health bars (4 px) scaled up. The Z key (`zoom_map`, `AppState.toggle_zoom`) switches in the map view; it is not saved. `Hud.actor_rects` follows the zoom.

### 10.3 HUD, menus, Theme (P6, P7)

- `hud.tscn` (CanvasLayer): map area (the 3D `SubViewportContainer` or the top view), side panel (VBox: HP bar, attributes, AC, to-hit, damage dice, gold, viewers, timer, stairs countdown, pet, scout report), log (`RichTextLabel`, wrapping, coloured lines from `MessageLog`), initiative tracker (`PanelContainer`, `TRACKER_W` 270, `TRACKER_ROWS` 8, Move / Action / Bonus pips), toasts and the two-round combat banner (`COMBAT_TOAST_TURNS`), first-person warnings (orange label naming the keys that provoke, chevrons).
- Tracker placement: top-left of the map area unless it would cover the player or a monster; actor rectangles come from `Camera3D.unproject_position` (3D) or tile rects (top-down); otherwise it moves to the bottom of the map area, as `Renderer.draw_tracker(avoid=)` does.
- Menus are Control scenes over a dimmed view with HUD bits hidden (Phase 7 rule), driven by `AppState` (scene, overlay, cursor). One `Theme` resource `ui/theme/crawl_theme.tres` with the `config.py` colours (`BG`, `PANEL_BG`, `TEXT`, `TEXT_DIM`, `ACCENT`, `DANGER`, `WARN`, `GOOD`, `INFO`) and one monospace font (open question Q6).
- Run report charts: `chart.gd` with `_draw` (bars, lines, axes, `nice_max`).

### 10.4 Settings file

`UserSettings` at `user://settings.json`, same JSON (`{"view": "fp"}`), same fallback rules; Tab toggles and saves; tests pass `""` to disable.

### 10.5 Input map (`project.godot`)

| Action | Keys |
|---|---|
| `move_n/s/e/w`, `move_ne/nw/se/sw` | arrows, W A S D (map view), numpad 8 2 6 4, 9 7 3 1 |
| `walk_forward`, `walk_back`, `strafe_left`, `strafe_right` | W / Up, S / Down, A, D (first-person) |
| `turn_left`, `turn_right` | Q / Left, E / Right (first-person) |
| `wait` | `.`, Space, numpad 5 |
| `descend` / `confirm` | `>` (Shift+Period), Enter, numpad Enter |
| `pickup` G, `inventory` I, `rest` R, `safe_menu` M, `pet_command` C, `practice` K, `attributes` L, `skill_1` 1, `help` `?`, `toggle_view` Tab, `back` Esc, `accept_deal` Y, `decline_deal` N, `unequip` U, `drop` D, `reroll` R | as in README |

The same physical key maps to different actions by view and scene (W walks in first-person, moves north on the map, moves the cursor in menus; R rests in play, rerolls on the reveal screen, opens the report on the end screen; L opens attributes in play, loads on the title). `ui/main.gd` resolves this the way `App.handle_key` does: it passes the action and the current context to `AppState`, never letting two contexts handle one press.

F2 = `cycle_render_scale` (P5), F3 = `cycle_effects` and F4 = `cycle_volume` (P8): any screen, saved in the settings file.

Z = `zoom_map` (P9): in the map view, 32 px tiles (32 x 20 window) <-> the 16 px glyph overview; F5 = `cycle_art_set` (P9 dev key, any screen): the next art set (default, every folder under `assets/sets/`, placeholder), flashing "Art set: NAME". Neither is saved: `UserSettings` is rules code and stays untouched. `--art-set NAME` / `CRAWL_ART_SET=NAME` pick a set at start and `--glyphs` starts with no art at all (placeholder pictures, the 16 px map).

### 10.6 Effects and sound (P8)

Effects are decoration driven by what the rules already announce, never by new rules. `FxDirector` (a Node made by `GameView`) subscribes to the `World`'s `EventBus` events, `FxPlan` (a pure table) says which effects each event fires, `FxState` holds their timing, and the views only read it:

| Event | Effects |
|---|---|
| `player_attack` | weapon swing (`ViewModel`), "miss" number and sound on a miss |
| `player_hit` | white flash on the monster, `-N` number, hit sparks, hit sound; crit: gold `CRIT -N!`, more sparks, screen shake, crit sound |
| `nat20` | "NATURAL 20" text |
| `damage_taken` | `-N` number low on screen, hurt sound; shake when it is a quarter of your HP |
| `kill`, `boss_kill` | dust burst, kill sound; bosses add shake and a fanfare |
| `boss_phase` | the biggest shake, "PHASE TWO", a roar |
| `bomb` | fire and smoke burst, an orange flash of light (OmniLight3D tween), shake, boom |
| `box_opened` | the reveal animation (`FxReveal`, `RevealCanvas`: rattle, lid flies off, sparkles) and its two sounds |
| `step`, `descend`, `achievement`, `item_use`, `item_pickup`, `level_up`, `combat_start`, `player_death`, `pet_hit` | sounds, a heal number and motes, a pet hit flash |

Also always on (no event): a torch flicker on the camera light (dips only, so walls are never brighter than their texture), wall torches with embers (`WallTorches`, a hash of the tile and depth chooses the sites, never the game's RNG), a walking bob, monsters and the pet sliding between tiles (`FxState.track_actor`, 0.14 s), and the weapon view model (`ViewModel` + `WeaponArt`, picture keyed `wpn:<item>` then `wpn:<style>` in `SpriteArt.weapon_view`).

- **Setting.** `settings.json` gains `effects` ("on", "reduced", "off"; F3), `volume` (percent; F4 walks 100, 70, 40, 10, muted) and `muted`. Python ignores the keys (`tests/test_settings.py`). "Reduced" has no shake and no camera bob, half flashes, a third of the particles, a gentler flicker; "off" has no effects at all (the red hurt flash included), sound stays on its own switch. `FxSettings.profile` is the one place that says what each mode means.
- **Skipping.** `FxDirector.on_key()` runs before every key is handled (`Main`): it finishes the shake, flashes, slides, swing, particle bursts and delayed sounds, and the box animation (`Hud.on_key`). Floating numbers keep drifting. Nothing waits for an effect and nothing queues up (each kind is capped).
- **Targets.** Events carry the monster key, not its tile, so `FxTargets` picks the nearest monster of that key from the World's list at the moment of the event (the previous frame's snapshot for the dead). A rules change adding `x`, `y` to `player_hit`, `kill` and `bomb` would make this exact; not needed so far.
- **Sound.** `SfxSynth` makes 19 short sounds from sine, square, saw, triangle and noise voices (deterministic, no RNG); `SfxPlayer` plays them through a pool of 8 `AudioStreamPlayer`s, and a `res://assets/sfx/<name>.wav` or `.ogg` replaces any of them. `godot/tools/export_sfx.gd` writes them as WAV files.
- **Proof.** `CRAWL_FX=1` makes `tools/trace_run.gd` and `tools/chaos.gd` attach a headless director to every World; `scripts/fx_parity.sh` compares those traces with Python's.
- **Tools.** `tools/fx_shots.gd` (frame sequences and contact sheets under Xvfb, plus a frame rate test) and `scripts/fx_gif.py`. The pygame pairing tools (`screenshots.gd`, `menu_sweep.gd`) call `GameView.set_plain(true)`, which turns effects off and hides the view model, since pygame has neither.

---

## 11. Risks, open questions and parity verdict

### 11.1 Verdict

**Seed-for-seed parity looks achievable** for the rules, the bot and the telemetry CSVs on Linux x86_64. Evidence: every RNG call site is a CPython method with a known algorithm (5.2); no set or dict iteration order that GDScript cannot reproduce feeds the rules (5.4); every Python numeric and text idiom that differs has a measured, tested replacement (3.3); and the installed Python 3.13 reproduces the committed `runs/bot_*.csv` byte for byte, so those files are a ready 2,000-run acceptance test. Statistical parity (bot win rate and floor-of-death distribution within confidence intervals over 2,000 runs) stays as the fallback for: other platforms whose libm differs (`pow`, `exp`, `log`), cross-implementation save loads (R5), and any divergence found late that the owner chooses not to chase.

### 11.2 Risks

| # | Risk | Likelihood / impact | Mitigation |
|---|---|---|---|
| R1 | Silent numeric mismatches: `int / int`, `//` and `%` on negatives, `round` half-even, Python 3.12 `sum`, `**0.5` vs `sqrt`, float factor order | High / breaks traces | `PyMath` only; verifier greps diffs for bare `/`, `%`, `round(`, `sqrt(`, `sort_custom(`; fixture tests; traces localise the first bad draw. |
| R2 | Unstable `sort_custom` where Python's sort is stable (stairwell rooms, safe-room candidates, pounce targets) | High / different floors | `PyMath.stable_sort_by`; floor fingerprints for 200 seeds catch it in S3. |
| R3 | Event subscriber order and nested emit order differ | Medium / `show` draws and messages diverge | Construct and subscribe in Python order; traces record pre-order emits with stream counters. |
| R4 | Text formatting: `repr`, `{:,}`, `{:.0%}`, `capitalize`, `str(bool)` | Medium / CSV and message diffs | `PyFmt`, fixtures from Python for every format the game uses; `parity_diff` compares numbers by value. |
| R5 | Float parsing in Godot is not correctly rounded for 16-17 digit decimals (17% off by 1 ulp in tests) | Low / Python saves loaded in Godot can differ in `streak_chance` and shop `forecast` by 1 ulp, which can flip a reorder comparison | Content floats are short (asserted). Godot-written saves add an `exact` map of IEEE hex for those fields (Python ignores unknown keys). Cross-loads from Python are best effort; owner decides if exact cross-load matters (Q4). **Resolved in T5** for the game's float ranges: `PyJsonLoad` reads repr floats exactly (and subnormals correctly), so no `exact` map is needed; only values outside `1e-4 <= abs(x) < 1e16` depend on `PyFmt.repr_float` for the exactness search (see B.2). |
| R6 | Headless pitfalls: `-s` parse errors exit 0; runtime errors return `null` and continue; `class_name` needs `--import` | High / false passes | `gd_test.sh` sentinel and `SCRIPT ERROR` grep; risky (assert-less) tests fail; import step in every run. |
| R7 | GDScript speed for 2,000 bot runs (Python: about 31 minutes on 4 cores) | Medium / slow P3 | Typed GDScript, `PackedInt32Array` distance maps and adjacency, process sharding; profile in T6 before the 2,000-run job. |
| R8 | GUT and GdUnit4 not installable now | Certain / short term | Stopgap runner with GUT-compatible API (7.2); one-line migration. |
| R9 | `world.py` is large and highly coupled; three sequential briefs on one file | Medium / schedule | Slices S6-S8 by line range with tests per slice; S9 tooling ready before S7 so traces guide S7 and S8. |
| R10 | JSON numbers come back as floats in Godot | High / int division and comparisons go wrong | `manifest.json` `float_paths`; `Content` coerces every other number to int; `test_content` checks types for every table. |
| R11 | Content drift between Python and JSON | Low (Python frozen) | `export_content.py --check` in CI; `content_sha` in trace headers. |
| R12 | Test seams (EventBus/MessageLog `tap`, `static var` config, patchable content) leak into behaviour | Low | Seams are read by no rule; the verifier checks each. |
| R13 | Platform libm: Windows, macOS and web exports may compute `pow`/`exp`/`log` differently | Medium for exports / small gameplay effect | Parity claimed and tested on Linux x86_64 only; other platforms checked statistically in P10. |

### 11.2a Open follow-ups

- **PyFmt.repr_float last digit (found by the T5 verifier, not fixed in T5):** a few doubles print one digit off Python's repr, for example `4232.246599528969` prints as `...9695`, and values below `1e-4` can differ. No game value or save depends on it today (saves are byte-identical on 100+ seeds), but `PyJsonLoad`'s exactness search and `PyJson.dumps` both use it, so a later PyFmt slice should fix it and extend `tests/test_py_fmt.gd`.

### 11.3 Owner decisions (answered after P0)

The owner accepted every recommendation:

| # | Question | Decision |
|---|---|---|
| 1 | P1/P2 grouping | Port `world.py` and `ai.py` whole in P1; verify pet, class-skill, box, shop and contract features in P2. |
| 2 | Test framework | GUT 9.7.1 vendored in `godot/addons/gut/` (MIT). `tests/support/test_case.gd` (`TestCase extends GutTest`) keeps type-strict `assert_eq`, `assert_ne` and `assert_eq_deep`. `scripts/gd_test.sh` keeps its safeguards. The stopgap runner is gone. |
| 3 | P3 bar | Byte-identical `runs/bot_*.csv` for seeds 0-1999; statistical parity only as a fallback. |
| 4 | Saves | A Python save that "loads and plays" is enough; no exact decimal parser. |
| 5 | Data location | `user://` by default, with `--runs-dir` and `--save-dir` options. |
| 6 | Font | DejaVu Sans Mono (recheck the licence at the source when it is bundled). |
| 7 | Test seams | `tap` Callables on `EventBus` and `MessageLog`, and `static var` config, approved. |
| 8 | Sorting | No sorting changes. |

---

## Appendix A: measurements on Godot 4.7.2 (this environment)

Probes were run headless with throwaway projects under the session scratchpad; results:

| Probe | Result |
|---|---|
| `round(2.5)`, `round(-2.5)` | 3.0, -3.0 (half away from zero; Python gives 2, -2) |
| `-7 / 2`, `-7 % 2`, `posmod(-7, 2)` | -3, -1, 1 (Python: -4, 1) |
| `str(0.1 + 0.2)`, `var_to_str(0.1 + 0.2)` | `0.3`, `0.30000000000000004` |
| `"%.nf" % x` vs Python `f"{x:.nf}"`, n = 0-3, 20,000 values | identical |
| `var_to_str(x)` vs Python `repr(x)`, 20,000 values | 9 differ (17 vs 16 digits) and exponent styles differ |
| Parsing Python `repr` strings (`JSON.parse_string`, `str_to_var`, `to_float`) | 3,344 of 20,015 off by 1 ulp (long digit strings); 0 of 20,022 wrong for decimals up to 15 significant digits |
| `pow(x, 0.5)` vs `sqrt(x)`, x = 1-99,999 | differ for 82 values in Godot and in Python alike; Godot `pow` equals Python `x ** 0.5` |
| Python 3.13 `sum()` vs naive loop on expected-damage-shaped sums | 183 of 750 differ; Neumaier model matches CPython on 200,000 random lists |
| Dictionary order after `erase` and re-insert; `JSON.parse_string` key order | insertion order kept; re-insert goes to the end; document order kept |
| `JSON.parse_string('{"z": 1}')` type of 1 | float |
| `JSON.stringify({"b": 1, "a": 2})` | `{"a":2,"b":1}` (sorted by default) |
| `"%+.0f" % -0.4` | `-0` (as Python) |
| `"opening_act".capitalize()` | `Opening Act` (Python: `Opening_act`) |
| `Array.sort()` on `["b", "a", "B", "_", "aa"]` | `["B", "_", "a", "aa", "b"]` (as Python) |
| `-s` script with a parse error | exits 0 |
| `class_name` without `--import` | not resolved; after `godot --headless --path . --import` it works |
| `quit(3)` from a `-s` script | process exit code 3 |
| Python 3.13.16 bot seeds 0-2 vs committed `runs/bot_*.csv` | byte-identical prefixes for runs, floors, boxes, shop and practice |

## Appendix B: test files

| pytest file | Godot test file | Slice | Notes |
|---|---|---|---|
| `test_combat.py` | `tests/test_combat.gd` | S2 | `pytest.approx` becomes `assert_almost_eq`; simulated damage uses `PyRandom` with the same seed. |
| `test_attributes.py` | `tests/test_attributes.gd` | S2, S6 | `parametrize("attr", list(ATTRS))` becomes `use_parameters(Content.table("attributes").keys())`. |
| `test_dungeon.py` | `tests/test_dungeon.gd` | S3 | `SEEDS` parametrised; FOV helpers on a hand-built floor. |
| `test_loot.py` | `tests/test_loot.gd` | S4, S8 | |
| `test_practice.py` | `tests/test_practice.gd` | S5, S6, S8, T4, T5 | The test that wraps `world.attack` to see `bonus` instead checks the damage outcome with a seeded roll, or uses a counting `PyRandom`; no seam in `World`. |
| `test_world.py` | `tests/test_world.gd` | S6 (World-specific checks and ownership), S7, S8 | `test_random_play_smoke` seeds 0-11 with a `PyRandom` driver. |
| `test_encounter.py` | `tests/test_encounter.gd` | S4, S7, S8, T5, T6 | `monkeypatch.setattr(C, ...)` becomes `TestHelpers.patch_static(GameConfig, ...)`; `setitem(MONSTERS["goblin"], "init", 50)` becomes `patch_item(Content.monster("goblin"), "init", 50)`; `SPEAK_CHANCE` patch likewise on the config table. |
| `test_floors.py` | `tests/test_floors.gd` | S6, S7, S8 | |
| `test_items.py` | `tests/test_items.gd` | S4, S6, S8 | pytest fixture `w` becomes `before_each`. |
| `test_phase3.py` | `tests/test_phase3.gd` | S4, S6, S8, T5 | |
| `test_phase4.py` | `tests/test_phase4.gd` | S4, S6, S7, S8, T3, T5 | |
| `test_achievement_loot.py` | `tests/test_achievement_loot.gd` | S8, T1 | |
| `test_showrunner.py` | `tests/test_showrunner.gd` (achievement tests: `tests/test_achievements.gd`) | T1, T2 | `test_every_event_has_mild_and_spicy_lines_that_format` checks `PyFmt.format_map` over `lines.json`. |
| `test_telemetry.py` | `tests/test_telemetry.gd` | T4, T6 | `test_bot_is_deterministic` uses `BotPolicy.play`. |
| `test_settings.py` | `tests/test_settings.gd` | T5 | |
| `test_firstperson.py` | `tests/ui/test_fp_logic.gd` (angle, steps, `target_ahead`, `open_facing`, glide) and `tests/ui/test_fp_scene.gd` (scene builds for every floor, every creature has a sprite) | P4, P5 | Minimap pixel tests become checks on the minimap image data. |
| `test_render.py` | `tests/ui/test_app_state.gd` (key handling, Tab, menus, held keys, combat lock, provoke flags; headless) and `tests/ui/test_scenes.gd` (every scene instantiates and draws a frame); `tools/screenshots.gd` under `xvfb-run` for the screenshot sweep | P4-P7 | `CRAWL_SCREENSHOTS` becomes `-- --screenshots=<dir>`. |
| (new) | `tests/test_py_random.gd`, `test_py_math.gd`, `test_py_fmt.gd`, `test_content.gd`, `test_parity_fixtures.gd`, `test_s2_parity.gd`, `test_s4_parity.gd`, `test_s6_parity.gd` | P0, S1, S2, S4, S6 | S4: scripts/make_fixtures_s4.py, seeds 0-199, 18,567 steps; S6: World floor traces, seeds 0-49 |

### B.1 Deferred tests (ported when their slice lands)

Every pytest test not yet ported is named here, with the slice that must port it. Remove a line when it is ported.

| Slice | pytest test | Why deferred |
|---|---|---|
| (none) | | Every pytest test is ported or covered. P7 ported the last three (`test_new_runs_and_floors_face_the_most_open_way` load part, `test_menus_in_first_person_leave_you_where_you_were`, `test_screenshot_sweep_of_every_screen_in_both_views`) and the menu and screen tests of `test_render.py` into `tests/ui/test_app_state.gd` and `tests/ui/test_menus.gd`. Nothing is deferred to P8-P10 (juice, art and sign-off add features, not ports). |

### B.2 Notes carried forward to later slices

- **P9 (art; built, awaiting sign-off) notes for P10:** art is data. `scripts/art_build.py` (shared helpers in `scripts/art_pipeline.py`) turns the CC0 `crawl/tiles` export plus fill-in art drawn in code into `godot/assets/` (sprites, 64 px textures, 32 px tiles, loot boxes, `manifest.json`, generated `CREDITS.md`); `SpriteArt` answers every key from the manifests (`ui/art/sprite_art.gd`: `mon:` `boss:` `pet:` `item:` `furn:` `fx:` `player:<race>` `box:` `box_big:` `tex:<depth>:<slot>` `tile:<depth>:<slot>`, `wpn:` and `fx:torch_*` as before) and falls back to the code-drawn placeholders for any key a set lacks. Art sets: `res://assets/sets/<name>/manifest.json` (written by `scripts/artgen.py import`) answers first and the default set fills the gaps; the set called `placeholder` skips every manifest. Switch with F5, `--art-set`, or `CRAWL_ART_SET`; `SpriteArt.generation` increases on every change and the views (`FpView`, `Billboards`, `ViewModel`, `WallTorches`, `FpMaterials`, `TopView`, `TopMarks`, `HudCanvas`) rebuild their pictures when it does. Keys: Z zooms the map (10.2, 10.5). Menu pictures (`HudStyle.icons`, off unless `Hud.icons_auto`, which only Main sets): inventory rows and the reveal show the item's picture, the safe-room box rows a loot box icon, the title the art credit; with icons off every model is pygame's layout exactly. Items are billboarded at 0.4 of a wall with real art (0.32 for the placeholder shapes). Acts have no sprite of their own: `SpriteArt.creature` lays `fx:badge_opening` / `fx:sash_featured` over the base monster's body (clipped to its pixels). The weapon view models stay procedural (`WeaponArt`; DCSS has no first-person art). Tests: `tests/ui/test_art.gd`, `test_top_view_tiles.gd`, `tests/test_artgen.py`, and the sprite, texture and tint tests in `test_sprites.gd` / `test_fp_scene.gd` now run against the real art and the placeholders. Tools: `godot/tools/art_shots.gd` (every shot of this phase, plus `--only perf`). Frame rate under Xvfb llvmpipe at 1280 x 768 with real art: first-person 33 FPS (36 with placeholders), map 48 (tiles) / 48 (glyphs); six floors of textures load in 9 ms (93 ms procedural).
- **P8 (juice; done) notes for P9 and P10:** files in `ui/fx/` (`FxSettings`, `FxPlan`, `FxState`, `FxTargets`, `FxDirector`, `FxParticles`, `WallTorches`, `ViewModel`, `ViewModelPose`, `FxCanvas`, `FxReveal`, `RevealCanvas`, `SfxSynth`, `SfxMixer`, `SfxPlayer`) and `ui/art/weapon_art.gd`; design in 10.6. Tests: `tests/ui/test_fx_plan.gd`, `test_fx_state.gd`, `test_fx_sound.gd`, `test_fx_scene.gd`. P9: register `wpn:<item>`, `wpn:<style>` and `fx:torch_0/1` art in `SpriteArt`, and drop recorded sounds in `assets/sfx/`. The pygame pairing tools use `GameView.set_plain(true)` so their shots stay comparable. `GameView.fx_director` exists on every GameView (tests included), so tests that count events or timing see the director's reads, never changes. Frame rate under Xvfb software GL at 1280 x 768 (llvmpipe): about 36 FPS with effects off, 34 to 35 on, so effects cost 1 to 3 FPS here.

- **P7 (menus and screens; done) notes for P8 to P10:**
  - Files: `ui/app/app_state.gd` (`AppState`, headless: `scene` title / identity / backstory / pet_select / game, `overlay` "" or inventory / safe / reveal / box / shop / craft / class / contract / report / skills / attributes, `cursor`, `show_help`, creation fields, `view`, settings, save and load, run logging; `handle_key(InputEventKey)` is the one input path, `update(dt, held)` the per frame one, `press(action)` the old action entry point); `ui/menus/` (`MenuKit` frame, wrap, fit; `MenuModels` inventory, safe room, box odds and reveal, shop, craft, class picker, sponsor offer, practice, attributes; `ScreenModels` title, help, identity, backstory, pet pick; `ReportModel` the three charts), all filling a `HudList` in 1280 x 768 pixels at pygame's coordinates; `scenes/hud.tscn` gained the `Menu`, `TrackerOver` and `Help` canvases (the Hud reads the GameView's `app`); `ui/main.gd` (`Main`) only forwards keys and held actions. `GameView` now owns an `AppState` (`game_view.app`) and delegates `view`, `settings`, `blocked`, `press`, `toggle_view`, run logging to it; `FpView.controller` and `TopView.controller` are the app's `fp` and `top`.
  - InputMap (`tools/input_map.gd`, 40 actions): `confirm`, `back`, `erase`, `menu_up/down/left/right`, `pickup`, `inventory`, `rest`, `safe_menu`, `pet_command`, `practice`, `attributes`, `skill_1`, `help` (F1; the "?" character works too), `accept_deal`, `decline_deal`, `unequip`, `drop`, `reroll`, `trade_up`. The same key has several actions (R rest and reroll, L attributes and load, D drop and strafe) and AppState tests the ones its state allows, as `App.handle_key` did. Text entry (names) takes only characters that are letters, digits, space, hyphen or apostrophe, up to 16.
  - Behaviour as Python: Tab is swallowed by an open menu (the shop uses it for buy / sell) and ignored on the end screens; Enter / numpad Enter restart from the end screens (">" does not), R opens the report, Esc goes to the title; menus in first person never move or turn you; the class picker and the sponsor offer open from `pending_choice` / `pending_offer` after any key; Esc in play goes to the title without saving.
  - Differences: L on the title shows "Loading your saved run..." for one frame and loads on the next `update` (the parse takes about 0.1 s); `--save-dir DIR` puts the save and settings in DIR, `--runs-dir DIR` the run logs, `--quick` skips the title and creation, `--seed N` seeds the first run and `--pet` preselects the companion (`godot --path godot -- --quick --seed 1 --pet dog` is the old P4-P6 start). A failed save keeps the menu open with a message (Python raises). `HudStyle.linesize(face)` is pygame's line step (18, 16, 26, 66; `line_height` is one more for small and big), used for wrapped paragraphs. Bold centred titles can sit 1 px right of pygame's (text width rounding).
  - Tests: `tests/ui/test_app_state.gd`, `tests/ui/test_menus.gd`, `tests/ui/test_main.gd`. `tools/menu_sweep.gd` (`MenuSweep`) replays every screen of the pygame sweep (77 names, both views) through the real GameView, Hud and AppState: the headless test builds each, `tools/screenshots.gd` saves them as `<name>_top.png` / `<name>_fp.png` (`--menus-only` for just these). `scripts/fp_compare_shots.py OUT/godot --menus OUT/pygame_raw ...` pairs them with pygame's own PNGs (`CRAWL_SCREENSHOTS=OUT/pygame_raw pytest tests/test_render.py`). Menu and screen pixels equal pygame's apart from the 1 px title shift and the log lines behind a menu; the first-person differences are the P4 ones. `tools/e2e_run.gd` is the scripted real-key run from the title to victory and back.
- **P6 (HUD and combat UI; done) notes for P7 to P9:**
  - Scene `scenes/hud.tscn` (`Hud`, `ui/hud/hud.gd`) sits over the GameView in `main.tscn`: seven full-window `HudCanvas` nodes (Panel, Log, Chevrons, Ahead, Tracker, Toasts, End). Everything shown is decided in headless RefCounted models (`HudPanel`, `HudLog`, `HudTracker`, `HudToasts`, `HudFp`, `HudScout`, `HudEnd`, `HudPlace`) that fill a `HudList` (text, fills, frames, polygons in 1280 x 768 pixels, laid out the way pygame does); `HudCanvas` only paints it. `HudStyle` reads fonts, sizes and colours from `ui/theme/crawl_theme.tres`, which `tools/make_theme.gd` generates from `ui_config.json` (DejaVu Sans Mono bundled in `assets/fonts/` with its licence). P7: set `Hud.covered` while a menu or help is open (hides tracker, toasts, chevrons, label and the minimap) and `Hud.tracker_over_menu` for the inventory; use the theme for menus. `HudEnd` draws the death and victory overlays with Python's wording; P7 owns the keys it names (R, Esc).
  - Tracker and toast placement follow `Renderer.draw_tracker` / `toast_layout`: in the map view they avoid your tile, your pet and monsters in sight; in first-person the tracker avoids the sprites of monsters and the pet projected with `Camera3D.unproject_position` (`FpView.actor_rects`), which Python skipped (its `_avoid` is empty there), and the toasts stay at the top as in Python.
  - P7 must restore the `box.right < menus.X0` check of `test_combat_tracker_and_screens_in_both_views` (the inventory over the tracker) once the menus exist; P6 only checks the tracker stays up with `Hud.covered` and `tracker_over_menu`. P9: the Headliner placeholder face differs from pygame's.
  - Text is drawn character by character at the face's whole-pixel advance (8, 9, 13, 34 px for the 13, 15, 22, 56 px faces), as pygame rounds it; the first-person labels use the 18 px bold face `fp_big`. The Hud rebuilds its lists every frame and `HudCanvas.show_list` skips the redraw when the items are equal (about 2-3 ms); `test_the_hud_never_shows_stale_lists` compares every canvas with a fresh build after a run of actions.
  - Tests: `tests/ui/test_hud.gd` (the five P6 rows of B.1 plus `test_boxes_over_the_map_never_hide_you_in_a_top_left_corner`, `test_long_boss_names_fit_the_tracker_cleanly`, and the models). Shots: `godot/tools/screenshots.gd` writes `hud_<name>_fp|top.png`, replayed by `scripts/fp_compare_shots.py` (kinds `hud_fp`, `hud_top`).
- **P5 (entities, minimap, top-down; done) notes for P6 to P9:**
  - Files: `scenes/game_view.tscn` + `ui/game_view.gd` (`GameView`: owns `FpView` and `TopView`, shows one; `press(action)`, `toggle_view`, `set_view`, `cycle_render_scale`, `set_render_scale`, `start(world)`, `blocked`, `settings_path` and `runs_dir` ("" turns each off), run logging to `user://runs/player_*.csv`); `scenes/top_view.tscn` + `ui/top/top_view.gd` (`TileMapLayer` terrain from a generated TileSet, `camera(world)` = `Renderer._camera`), `ui/top/top_marks.gd` (glyphs, boss boxes, provoke brackets, health bars in `_draw`), `ui/top/top_controller.gd` (map input, headless); `ui/fp/billboards.gd` + `billboard.gdshader` / `billboard_bar.gdshader` (replace `fp_markers.gd`), `ui/fp/minimap_image.gd` (pixels, headless) + `ui/fp/minimap.gd` (node and "Facing X"); `ui/art/sprite_art.gd` (`SpriteArt`, the asset-key lookup) + `ui/art/pixel_canvas.gd`; `ui/ui_colours.gd`, `ui/ui_fonts.gd` (SystemFont monospace until P7's Theme).
  - **Keys added to the InputMap** (`tools/input_map.gd`): Tab = `toggle_view`, F2 = `cycle_render_scale`. Both are handled by `GameView`, and ignored while `blocked` (P7 menus must set it, as `FpController.blocked`) and, for Tab, after death or victory. Keys still free: F1, F3-F12 (P7 help is `?`).
  - Sprite lookup keys (art bible section 6): `mon:<key>`, `mon:opening_<base>` / `mon:featured_<base>` (fall back to the base), `boss:boss_N`, `pet:<species>`, `item:<key>`, `furn:<kind>`, `fx:stairs_open`, `fx:stairs_locked`. P9: `SpriteArt.register(key, image)` or `res://assets/manifest.json` (`{"mon:goblin": {"file": "sprites/monsters/goblin.png"}}`, path relative to `res://assets/`). Creatures get the vertical shade and the one pixel outline in code (`SpriteArt.finish_creature`), items, furniture and stairs are used as given. Item shadows are a code-drawn ellipse behind the item. Item art scale stays 0.32 until the real art lands (art bible: about 0.4 then).
  - Sprites are shaded by `billboard.gdshader` (fog only, Python's `max(0.12, (1 - d / 8.5) ^ 1.3)` with `d` the depth straight ahead, `fog_disabled` so the scene fog does not double up). It converts to linear only when `OUTPUT_IS_SRGB` is false (Forward+ measured by the verifier: sprites match, but the walls come out about 13% brighter than pygame). **The project now defaults to the Compatibility renderer** (`rendering/renderer/rendering_method` and `.mobile` = `gl_compatibility`): everything was tuned and measured there, the retro look gains nothing from Forward+, and it is safer on older laptops. Health bars use `billboard_bar.gdshader` (no depth test: a tall Act's bar sits above the ceiling line, as in pygame). A bar follows Python's exact rule (`FpLogic.sprite_column_clear`, a port of the per-column DDA `_cast`): it is hidden when the ray through the sprite's centre column hits a wall before the sprite's depth, or the sprite has no columns on the 320 pixel screen. A monster whose tile is in `world.visible` can still fail this (about 3.6% of cases, e.g. seed 1, player (21, 5), looking 135 degrees, goblin at (23, 7)), so tile visibility alone is not enough. Keys used in the map view run `GameView._after_top_action` (the first-person `after_action`, so a new floor is faced from the arrival tile, and run logging) through `TopView.acted`.
  - Item sprites are new procedural shapes by kind (weapons diagonal, armour a torso, potions bottles, bombs round with a fuse, junk greyish), not pygame's font glyphs, following the art bible's shape language; the top-down view still draws the glyphs.
  - Sprites closer than 0.2 tiles in front of the eye are skipped (Python's `tz > 0.2`), so a monster on your own tile or behind you is not drawn.
  - **Render scale** (owner addition): `UserSettings.RENDER_SCALES` retro / sharp / full, default retro, in the same `settings.json` as the view (`{"view": "fp", "render_scale": "retro"}`; the Python version ignores the extra key, and `UserSettings.DEFAULTS` gained it, the only change under `godot/rules/`). `FpView.set_render_scale` resizes the `SubViewport` (320 x 200, 640 x 400, or the size of the `FpView` control); camera, FOV (`KEEP_WIDTH`) and aspect never change, sprites and bars are in world units, and the minimap, label and hurt flash are drawn at full resolution on top. Retro keeps nearest filtering, the other two are filtered linearly. "Full" assumes the 1.6 aspect of the 1024 x 640 map area; another aspect changes only the vertical framing.
  - Top-down is the pygame view as it is (16 px glyph grid, no 32 px tiles until P9 per the owner's art bible decisions). Terrain tiles are written only when they change; the glyph layer redraws every frame the view is active.
  - Not done in P5 (still P6): chevrons for monsters beside or behind you, the "ahead" label, the initiative tracker and toasts over either view. The top view's `set_active` / `FpView.set_active` do what Python's `toggle_view` does (fresh camera, no stale flash).
- **P4 (first-person 3D) notes for P5 to P7:**
  - Files: `scenes/fp_view.tscn` + `ui/fp/fp_view.gd` (`FpView`: `start(world)`, `refresh(dt)`, `capture()`, `input_enabled`, `hud`), `ui/fp/fp_logic.gd` (`FpLogic`, headless camera maths), `ui/fp/fp_controller.gd` (`FpController`, headless: the first-person part of `App.handle_key` / `App.update` / `sync_combat`, driven by action names; `blocked` is the overlay/help flag P7's `AppState` should set), `ui/fp/floor_mesh_builder.gd`, `ui/fp/fp_materials.gd`, `ui/fp/fp_textures.gd` (placeholder 64 px textures), `ui/fp/fp_camera_rig.gd`, `ui/fp/fp_markers.gd` (PLACEHOLDER sprites: P5 replaces it with `billboards.gd`; keep the `sync(world)` call site in `FpView.refresh`). `ui/main.gd` has a placeholder status panel and log (P6 replaces them).
  - The mesh is filled with packed arrays rather than `SurfaceTool` (same mesh, faster); about 40-65 ms per 120 x 76 floor in GDScript, once per floor.
  - Not done in P4 (still to port from `firstperson.py` / `game.py`): minimap, compass label, chevrons and the "ahead" / provoke label (P5/P6); class picker and contract offer on `pending_choice` / `pending_offer`, Tab, run logging (P5/P7); the play keys R rest, G pickup, C command pet, 1 class skill, Esc, and I / M / K / L menus (P7: add their InputMap actions and route them in `AppState`). The rules do not block on `pending_choice`, so P4 play simply carries on without a class.
  - `FpController.press()` ignores `blocked` (only held keys honour it): P7 must route presses to the menu instead of the controller while an overlay or help is open, as `App.handle_key` does.
  - After death or victory, P4's `FpView` starts a new run on any `descend` key, including `>`; P7's end screens should restart on Return / numpad Enter only, as Python does.
  - Lighting (verifier fix): ambient 0.6 plus a torch of 0.4 with `omni_attenuation = 0`, so nothing near the eye is brighter than the texture (Python only darkens); depth fog does the falloff. The stairs grate has no emission (pygame's dark brown and gold). Measured mean brightness against pygame on the shot set: 0.96x to 1.15x, the wall at 0.5 tiles 1.00x.
  - InputMap actions are written by `tools/input_map.gd` (re-run it after editing its table). `tools/screenshots.gd` writes `shots.json`; `scripts/fp_compare_shots.py` replays it in pygame for side by side images.

- **S6 (done):** `S2Support.hero()` and `S4Support.FakeWorld` are gone (tests use `World.new(1).player` and a real `World`). `Entities.new_pet` takes a String name (`None` -> `""`); `World.new` maps a `null` pet name to `""`.
- **T5 (Save and settings, done) notes for T6 and P5/P7:**
  - `rules/save_game.gd` (`SaveGame`: `VERSION`, `DEFAULT_DIR := "user://saves"`, `slot_path(dir := DEFAULT_DIR)`, `to_dict`, `from_dict`, `dumps`, `save(world, path := "") -> bool`, `load(path := "") -> World` (null on failure), `from_text`, `has_save`) and `rules/user_settings.gd` (`UserSettings`: `DEFAULT_PATH := "user://settings.json"`, `settings_path(dir)`, `VIEWS`, `DEFAULTS`, `load(path)`, `save(settings, path) -> bool`; path `""` disables). The `--save-dir DIR` option of P7 passes `SaveGame.slot_path(DIR)` and `UserSettings.settings_path(DIR)`. Failures are `push_error` plus `false`/`null` (mid-combat save, wrong version, missing key, unreadable or corrupt file).
  - The schema coercion the earlier notes asked for is not needed: `rules/py/py_json_load.gd` (`PyJsonLoad.parse(text)`) is a small JSON reader that keeps `1` an int and `1.0` a float, so `Entity.from_dict`, `Practice.load`, `Shop.load` and the rest receive Python's types and `ShopStock.from_dict` coercion is only a safety net. `String.to_float` is out by up to 3 ulp even at `0.009999999999999995`, so the reader scales the digits by an exact power of ten and, off Clinger's exact fast path, searches the neighbouring doubles for the one whose `PyFmt.repr_float` equals the text. Result: floats in a Python-written save load exactly for the game's ranges (risk R5 and decision #4's 1-ulp allowance are not needed; the `exact` hex map was never added; text outside `1e-4 <= abs(x) < 1e16` relies on `repr_float`, see the PyFmt follow-up below). The reader also rejects the number forms Python rejects (`01`, `1.`, `1e`, `1e+`) and scales without passing through an infinite power of ten (subnormals are right). `PyJsonLoad.parse` takes about 103 ms on a 245 KB save, so P7 should load off the main thread or show a loading state, and Godot writes with `PyJson.dumps`, so its saves are byte-identical to Python's (measured, see below).
  - Python's v7 save does not keep `Tracker.unarmed_kills`, `pet_kills`, `maps`, `junk_sold` and `nat1s`. A loaded run counts them from zero, so about 40% of chaos runs that are saved and loaded unlock some achievement later than the run that did not save (Python and Godot alike; ported as is, not a bug of the port). The parity harness drops those five counters on the continued original (`drop_unsaved`) so that `direct` and `loaded` compare strictly.
  - Parity tooling: `scripts/save_trace.py` / `godot/tools/save_trace.gd` (+ `tools/save_trace_run.gd`, the chaos player without tracing) play a seed to a save point, save, reload, continue `--steps` steps both ways and write `direct_`, `loaded_` (and with `--load-dir`, `xload_`: the other language's save) traces and `save_<seed>.json`; `scripts/save_diff.py` requires byte-identical saves and identical traces. `gd_test.sh`: seeds 0-7, 150 steps (`SAVE_TRACES`, `tests/test_save_game.gd`); `parity_all.sh`: seeds 0-99, 300 steps. About one run in six dies or stays in a fight before a save point (no save is written for it, on both sides).
- **S4 seams and judgement calls (for S6 and later):**
  - `Contracts.effect` / `preview` take a duck-typed `world` (`Variant`): `contract` (String, "" or null for none), `floor_stats`, `monsters`, `player`, `timer`, and `timer_text(turns := null)`. S6 passes the real `World`.
  - `Shop.buy` returns `""` for Python's `None`; `Loot.next_tier` returns `""`. Only `ShopStock.from_dict` coerces (`int`/`float`); `Shop.load` stores `log`, `bought` and `missed` raw, so T5 must coerce them (and the stock dictionaries) by schema before calling it.
  - `Encounter.total/before/after` for an entity that is not in the fight push_error and return 0 / [] (Python raises `StopIteration`).
  - `FunFacts` was a P1 stand-in; T3 replaced it whole (as T1 did `Achievements` and T2 `Showrunner`, see below). They already follow the section 3 "Back-references to World" rule (`_world_ref: WeakRef`, `world` getter, `_init(world_value: Object)`) and each has an ownership test in `tests/test_s4_standins.gd`; the replacements and World (S6) must keep both.
  - `Bosses.acts_per_floor` returns a `Vector2i` (x opening, y featured); `Bosses.MAP_RADIUS` / `PHASE_TWO` are patchable static vars.
  - `Contracts.preview` with no monsters (Python: ZeroDivisionError) push_errors and returns the lines so far.
- **S7 (World B and AI, done) notes for S8 and later:**
  - `ai.gd` is whole. `world.gd` has all of `world.py` 1084-1557 under the "S7" marker. Pulled forward from the S8 range so the `walk` trace can run (S8 must not port them again; they sit under "Pulled forward from S8 by S7"): `move_player` (pet swap, bump attack, provoke checks), `wait`, and the pet methods `Ai` calls: `pet_attack`, `pet_pounce`, `pet_lick`, `pet_squawk`, `pet_dirty_trick`, `pet_flees`, `monster_attack_pet`. Still S8: `descend`, `rest`, `_spend_turns`, safe-room activities, `craft`, shop trades, `command_pet`, `revive_pet`, `use_skill`, `pickup`, `drop`, `unequip`, `use_item`, bombs, boxes (`open_box`, `reroll`, `trade_up`) and `_take_reason`/`_reveal`.
  - `World._chase_cache` (`[floor, x, y, dist]`) is Python's `world._chase_cache`; `Ai.chase_map` reads and writes it. `Ai` takes a typed `World` (the cyclic `Ai`/`World` references compile fine in 4.7).
  - Event payload keys follow Python's kwarg order; the `walk` trace compares them by value anyway. `_player_attack`, `monster_attack` and `opportunity_attacks` return bool as Python's do.
  - Trace tooling: `tools/trace.gd` run mode (`--policy walk|hunter`, `--steps`, `--pet`, `--hero`, `--no-msg`, `--seed(s)`, `--out`/`--out-dir`), `tools/trace_run.gd` (`TraceRun.run_trace`, shared with `tests/test_s7_parity.gd`) and `tools/trace_policies.gd`. `walk` is proven (seeds 0-49, no pet and each of the four pets with heroes, core scope identical). `HunterPolicy` is written line for line from `trace_policies.py` but unrun: `TracePolicies.perform` calls `World.descend`, `pickup`, `use_item(index)`, `use_skill`, `rest`, `revive_pet` by name and push_errors until S8 adds them, so S8 can run `--policy hunter` with no tooling change. `bot` needs the T6 `BotPolicy`.
  - Core scope also drops `practice_level` events for `showmanship` and ignores `many_at_3`: the stand-in Showrunner never emits `viewers_gained`, so Python trains Showmanship (which only affects viewer gains) and the counts differ. T2 restores full parity. (Done: T2 and T1 landed; walk and hunter compare at full scope.)
  - The `full` scope of the `walk` traces differs from Python only where the P1 stand-ins stay silent: the `msg` records for System and Showrunner lines, and the `achievement`, `box_gained`, `viewers_gained`, `sponsor_gift`, `fun_fact` events with the `show` stream draws and `viewers` that follow from them. T1 to T3 should switch `tests/test_s7_parity.gd` to full scope (drop `_core`). (Done: T1 to T2 switched the walk and hunter checks to full scope; only FunFacts is still muted on the Python side.)
- **T2 (Showrunner, done) notes for T1, T3 to T6:**
  - `rules/showrunner.gd` is the whole of `crawler/showrunner.py`. Constants are `static var`s read from config.json (`SPEAK_CHANCE` is the config table itself, so `TestHelpers.patch_item(Showrunner.SPEAK_CHANCE, ...)` patches it); `Showrunner.sponsor_gifts()` reads `sponsor_gifts.json`; `_say(kind, ctx := {})` takes a Dictionary. The save fields T5 needs are plain vars with Python's names: `viewers`, `peak`, `history`, `samples`, `_kill_turns`, `_last_fun`, `_gift_idx`, `_last_flee_quip` (the `[turn, viewers]` pairs are Arrays; coerce JSON floats to int on load).
  - World init already emits `floor_start`, so the show stream has drawn by the time `World.new` returns (tests replay it with `genrand_uint32` times `words_used`).
  - Muting for parity while a subsystem is still a stand-in: `chaos_trace.py`, `chaos.gd` and `chaos_diff.py` take `--mute showrunner,funfacts` (default both; `all`, `none`; names validated by `scripts/mute.py`; Achievements cannot be muted; `--mute-standins` / `--no-mute-standins` are aliases). `py_trace.py` takes `--mute funfacts` (it silences the real Python `FunFacts._say`; the Godot stand-in is silent already). `scripts/gd_test.sh` and `scripts/parity_all.sh` pass `--mute funfacts` to both and compare every trace set in full scope. T3 deletes its entry from those `--mute` lists (gd_test.sh, parity_all.sh, `tests/test_chaos_parity.gd` `MUTE`) when they land. `chaos.gd` mutes the showrunner by unsubscribing it (Python's muted showrunner has no other observable effect on the compared state).
  - Against unmuted Python (real Achievements and FunFacts), `walk` and `hunter` seeds 0-11 are identical at core scope and differ at full scope only where Achievements and FunFacts are silent in Godot: the first "Achievement unlocked" or FUN FACT message and what follows from it (boxes, viewers, show stream).
- **T4 (Telemetry, done) notes for T6 and later:**
  - `rules/telemetry.gd` (`Telemetry.new(world, source := "player", run_id := "", meta := {})`, `tables()`) and `rules/py/py_csv.gd` (`PyCsv.write_tables(tables, out_dir, prefix := "", skip := [])`, plus `encode_row/encode_rows/parse/read_dicts`). The writer takes any directory (absolute or `user://`), so `--runs-dir` is the caller's business (T6 bot, the game's `Game` autoload). `run_id` is a Variant (Python tests pass an int); a falsy one draws 12 hex characters from `Crypto`.
  - The Telemetry reaches the World through a `WeakRef` and subscribes bound methods (`"*"` then `floor_start`, as Python). The caller owns the Telemetry, as in Python: drop it before the world and nothing leaks; drop it while the world lives and the bus holds a dead callable. Ownership test: `tests/test_telemetry.gd`.
  - Rows depend on the real `Achievements` (T1, merged; it can never be muted): `runs.achievements` (`len(unlocked)`) and the achievement boxes in `boxes` are nonzero and compared byte for byte, as are the viewers they bring. FunFacts only writes messages, so the CSVs do not depend on it; the Python side still runs `--mute funfacts` until T3. The Showrunner is real, so `viewers`, `peak_viewers` and `viewers_gained` are compared.
  - Byte-compare: `chaos_trace.py` / `chaos.gd` take `--telemetry-dir DIR`. They attach a Telemetry at creation, then after the trace file is closed run `finale()` (by `(seed // 4) % 4`: leave unfinished, kill, collapse, win by walking down the stairs with the exit forced open), emit nine odd events straight on the bus (quotes, commas, CR and LF, unicode, `1e-05`, `1e+16`, `0.30000000000000004`, `True` as a value, `None` and empty details, the skipped `turn`) and write `DIR/seed_<n>/chaos_<table>.csv`. The `.jsonl` traces are unchanged, so CHAOS_TRACES still holds. `scripts/parity_diff.py --csv DIR_A DIR_B [--cells-only] [--max-diffs N]` compares them (bytes first, then cells, floats by value; byte-only differences are reported as BYTES DIFFER and fail unless `--cells-only`). Quick check: `test_telemetry.gd` (seeds 0-15 through `gd_test.sh`); large set: `parity_all.sh` (seeds 0-215, 2500 steps).
  - Formatting traps checked (all identical to Python): CRLF line ends, `""` for a lone empty field (never reached, tables have many columns), quoting of `\r` and `\n` as well as `,` and `"`, `repr` of floats (`1e-05`, `1e+16`, `3.0`, `0.30000000000000004`), `True`/`False` for booleans and for `str(d[k])` of a `False` payload, `None` as an empty cell, a restval of `""` for a missing key, and unicode written as UTF-8 without a BOM.
- **T6 notes (bot and CSV output; from the T4 verifier):**
  - The committed `runs/bot_*.csv` were made with `--no-events`: there is no `bot_events.csv`.
  - `runs.achievements` is nonzero in the committed files, so the bot needs the real T1 (merged).
  - Float columns stay floats even when integral (`hp_frac`, `dmg_avg`, `ev`, `forecast_before`, `forecast`, `reorder_point`: `1.0`, not `1`); `pet_down` and `rerolled` are bools (`True`/`False`); every other numeric column is an int.
  - `bot_boxes.csv` gets its header from the first run that has box rows (empty tables are skipped), so `gd_bot.py` shard merging must keep exactly one header per file and cope with shards whose first runs have empty tables.
  - Old `bot_*.csv` are deleted only when `--start 0`; otherwise runs append.
  - `bot.gd` and the Game autoload must hold the `Telemetry` for the whole run: the event bus calls it through a bound callable and does not keep it alive.
  - `PyCsv.encode_rows` builds its text with `out +=`: fine per run, quadratic if one call wrote a huge table.
- **S6 (World A) notes for S7 and S8:**
  - `world.gd` has marked "S7" and "S8" append sections at the end. Already in the file, do not port again: `add_box`, `choose_class`, `equip` (S8 methods the S6 tests need) and `_end_combat` (S7; `new_floor` calls it). `_respawn` (S6 range) is there too but its caller `_tick_clock` is S7.
  - Python's `World.trait` is `World.get_trait` (`trait` is a reserved word in GDScript 4.7). `World.CHOICE_FLOOR` and `World.PET_MODES` are static vars read from config.
  - `race`, `cls`, `gender`, `backstory`, `contract`, `pending_offer`, `death_cause`, `last_reason`, `last_reveal` are Variants holding `null` as in Python. `World.new(seed, pet, hero, tap_events, tap_messages, tracer)`: `pet` is `[species, name]`, `hero` a Dictionary; `tracer` (optional object with `attach_world(world)`) is how `trace.gd` reaches the world before floor 1's `floor_start`.
  - The `--floor-only --spawns` trace compares at `--scope core` until T2 (the `show` stream draws in Python, never in the stand-in Showrunner). `parity_diff.py` core scope now also drops index 4 of a floor record's `words`. T2 should switch the check to full scope (`tests/test_s6_parity.gd` drops the show stream explicitly). (Done in T2.)
  - `test_cardio_trains_by_walking_and_extends_the_next_timer` emits "step" events instead of walking with `move_player` (S8 to switch it; done in S8).
- **S8 (World C, done) notes for T1 to T6:**
  - `world.gd` now covers all of `world.py` 1-1557. `_spend_turns` returns `false` when it refuses in a fight and `true` otherwise (Python: `False` / `None`; no caller reads it, one test asserts the refusal). `use_skill`, `use_item`, `pickup`, `drop`, `unequip`, `_explode`, `_reveal`, `trade_up` and the rest follow Python statement for statement; `Contracts.effect(self, "rest_mult")` is the only contracts read in the new range.
  - `hunter` is proven against Python at `--scope core`: seeds 0-49, 3,000 steps, with no pet and with each pet plus heroes (see the S8 report); `tests/test_s8_parity.gd` runs seeds 0-9 and five pet/hero combinations through `gd_test.sh` (`HUNTER_TRACES`, `HUNTER_COMBOS`). Hunter rarely goes past floor 3, so rest, craft, class skills, bombs, boxes and shop trades are covered by the unit tests, not by a trace; the `bot` trace (T6) will exercise them. No stand-in effect beyond the documented core-scope ones showed up in the hunter traces.
  - New helpers in `tests/support/helpers.gd`: `clear_world`, `free_tiles_near`, `play` (the Python `_clear`, `_free_tiles_near`, `_play`).
  - The stomping test replays the roll on a copy of the main stream (`get_state`/`set_state`) instead of wrapping `attack`; it swings until the replayed roll hits so the bonus is visible.
- **T1 (Achievements, done) notes for T3 to T6:**
  - `achievements.gd`, `achievement_tracker.gd` and `achievement_rules.gd` are whole. The tracker holds the world through a WeakRef too (Python's holds it strongly; World -> Achievements -> Tracker -> World would leak). Subscription order: distinct `on` events in table order, then `unequip` (Python iterates a set, whose order varies per process; each event still gets exactly one handler, after Practice's and before the Showrunner's). `AchievementRules.test` reads `INVENTORY_SIZE` through the `GameConfig` class object at test time.
  - `tests/test_achievements.gd` holds the achievement tests of `test_showrunner.py` plus rule, flow, subscription and ownership checks. No T1 rows remain in B.1.
  - Python traces and chaos runs now mute only `funfacts` (`--mute funfacts` in `gd_test.sh`, `parity_all.sh`, `test_chaos_parity.gd`); walk and hunter compare at full scope. T3 removes the last name.
- **T3 (Fun facts and report, done) notes for T4 to T6:**
  - `rules/fun_facts.gd` is the whole of `crawler/funfacts.py` (no RNG draws; `once` is `""` for Python `None`; constants are `static var`s from config.json). `rules/run_report.gd` has `RunReport.build(world)` (Python's `run_report`; pairs and samples are two-element Arrays) plus the pure helpers of `crawler/ui/report.py` the screen needs: `nice_max`, `plural`, `summary_line`, `box_caption`, `contract_lines`, `notes_line`. P7 only draws them.
  - Nothing is muted any more: `gd_test.sh`, `parity_all.sh`, `test_chaos_parity.gd` and the S6 to S8 parity tests pass no `--mute`, and `scripts/parity_all.sh` is identical at full scope with every system real. `--mute` stays as a debugging option on `py_trace.py` (funfacts only), `chaos_trace.py`, `chaos.gd` and `chaos_diff.py`, now defaulting to none (`scripts/mute.py` `DEFAULT = ""`); `chaos.gd` mutes FunFacts by unsubscribing it, as for the Showrunner.
- **T6 (Bot, done) notes for P3 and later:**
  - `tools/bot_policy.gd` (`BotPolicy`: `run_config`, `choose(w, state)`, `spend_points`, `manage_items`, `play`), `tools/bot.gd`, `scripts/gd_bot.py`, `scripts/bot_csv_check.py` (byte compare of a directory with the committed `runs/bot_*.csv` rows of a seed range) and the `bot` trace policy (`TracePolicies.BotTracePolicy`, `TracePolicies.default_setup`; `trace.gd` takes the pet and hero from `run_config` unless `--pet` / `--hero` override, as `py_trace.py`). Python's `w._bot_route` and `w._bot_fleeing` are a `BotPolicy.BotState` passed to `choose`; a move is a `Vector2i`.
  - `bot.gd` writes each run's tables as soon as it ends (`--no-events` skips `bot_events.csv`; the committed files have none) and `--summary-out` writes one JSON summary per run for `gd_bot.py`, which cuts the seeds into chunks of `--chunk` (default 10), runs one Godot process per chunk on a thread pool, and merges shards in seed order with one header per file. `scripts/parity_all.sh` runs the bot traces (0-49) and the CSV set (0-99) and `tests/test_t6_parity.gd` a small set of both.
  - Speed (T6 profile, measured; no optimisation done): one process plays about 10 runs a minute and 4 workers about 17 on this 4-core machine. `DungeonFloor.distance_map` is about 55% of bot time (the bot's route maps 23%, the pet's radius-40 maps 17%, the chase map 14%), FOV 10-12%. A safe option for later is a per-floor `distance_map` memo keyed `(start, max_dist, avoid_safe)` and cleared in `DungeonFloor.forget_paths()` (saves about 11-15%); bigger wins need native code. P3 should run on an idle machine with 4 workers (estimate 55-70 minutes for 2,000 runs; this slice's own measurement under load suggests up to about 2 hours).

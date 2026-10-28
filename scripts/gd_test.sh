#!/usr/bin/env bash
# Run every Godot headless test (port plan 8.3):
#   scripts/gd_test.sh                       # all
#   scripts/gd_test.sh --file=test_content   # files whose name contains this
#   scripts/gd_test.sh --test=reference_seed # tests whose name contains this
#   (any other argument goes straight to GUT, e.g. -glog=2)
#
# 1. imports the project (class_name needs .godot/global_script_class_cache.cfg; a headless
#    parse error can still exit 0, so step 4 also greps the log),
# 2. builds the Python references and fixtures (not committed: the RNG one is 12.7 MB) in a cache
#    directory under ${TMPDIR:-/tmp}, keyed by a hash of crawler/, scripts/ and godot/data/ (*.py, *.json),
#    so an unchanged checkout reuses them; GD_TEST_NO_CACHE=1 rebuilds into a throw-away directory:
#      py_random, content, dice/combat (S2), practice and S4 fixtures (S4: 50 seeds),
#      dungeon (S3): FOV/distance fixtures (DUNGEON_FIXTURES) and floor-only traces, seeds 0-19 (FLOOR_TRACES),
#      world (S6): floor-only traces with spawns, seeds 0-19 (SPAWN_TRACES, SPAWN_COMBOS),
#      world (S7): `walk` run traces, seeds 0-9 (WALK_TRACES) and pet/hero combos (WALK_COMBOS),
#      world (S8): `hunter` run traces, 3000 steps, seeds 0-4 (HUNTER_TRACES) and pet/hero combos (HUNTER_COMBOS),
#      world (S8): chaos traces, seeds 0-9, 600 steps (CHAOS_TRACES; scripts/chaos_trace.py),
#      telemetry (T4): chaos CSV files, seeds 0-15 (CHAOS_CSV; chaos_trace.py --telemetry-dir),
#      bot (T6): `bot` run traces, 3000 steps, seeds 0-3 (BOT_TRACES); the bot CSVs are compared with the committed runs/,
#      saves (T5): Python saves and continuations, seeds 0-7, 150 steps (SAVE_TRACES; scripts/save_trace.py),
# 3. runs GUT (addons/gut, settings in godot/.gutconfig.json),
# 4. passes only if the exit status is 0, GUT reports 'All tests passed!' and no SCRIPT ERROR /
#    parse error / failed-to-load line appears.
# The full acceptance sets (more seeds) are in scripts/parity_all.sh.
# Environment: GODOT (binary, default godot), GD_TEST_LOG (default /tmp/gd_test_<hash of checkout path>.log,
# so parallel worktrees never share a log), GD_TEST_NO_CACHE.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
TMP="${TMPDIR:-/tmp}"
LOG="${GD_TEST_LOG:-$TMP/gd_test_$(echo "$ROOT" | md5sum | cut -c1-8).log}"

"$GODOT" --headless --path "$ROOT/godot" --import >/dev/null 2>&1

KEY="$(cd "$ROOT" && find crawler analysis scripts godot/data -type f \( -name '*.py' -o -name '*.json' -o -name '*.sh' \) | LC_ALL=C sort | xargs md5sum | md5sum | cut -c1-16)"
if [ "${GD_TEST_NO_CACHE:-}" = "1" ]; then
	REFDIR="$(mktemp -d)"
	trap 'rm -rf "$REFDIR"' EXIT
else
	REFDIR="$TMP/crawl_gd_refs_$KEY"
fi

build_refs() {
	local R="$1"
	python3 "$ROOT/scripts/py_random_reference.py" "$R/py_random_ref.json" || { echo "FAIL: py_random_reference.py"; return 1; }
	python3 "$ROOT/scripts/content_reference.py" "$R/content_ref.json" || { echo "FAIL: content_reference.py"; return 1; }
	python3 "$ROOT/scripts/make_fixtures.py" "$R/fixtures.json" || { echo "FAIL: make_fixtures.py"; return 1; }
	python3 "$ROOT/scripts/make_fixtures_s2.py" "$R/fixtures_s2.json" || { echo "FAIL: make_fixtures_s2.py"; return 1; }
	python3 "$ROOT/scripts/practice_reference.py" "$R/practice_ref.json" || { echo "FAIL: practice_reference.py"; return 1; }
	python3 "$ROOT/scripts/make_fixtures_s4.py" "$R/fixtures_s4.json" 50 || { echo "FAIL: make_fixtures_s4.py"; return 1; }
	python3 "$ROOT/scripts/make_dungeon_fixtures.py" "$R/dungeon_fixtures.json" || { echo "FAIL: make_dungeon_fixtures.py"; return 1; }
	python3 "$ROOT/scripts/py_trace.py" --seeds 0-19 --floor-only --floors 6 --out-dir "$R/floor_traces" >/dev/null || { echo "FAIL: py_trace.py --floor-only"; return 1; }
	python3 "$ROOT/scripts/py_trace.py" --seeds 0-19 --floor-only --spawns --floors 6 --out-dir "$R/spawn_traces" >/dev/null || { echo "FAIL: py_trace.py --floor-only --spawns"; return 1; }
	# pet and hero combos (SPAWN_COMBOS): <name>.jsonl, mirrored in tests/test_s6_parity.gd
	mkdir -p "$R/spawn_combos"
	while read -r name seed pet hero; do
		python3 "$ROOT/scripts/py_trace.py" --seed "$seed" --floor-only --spawns --floors 4 --pet "$pet" --hero "$hero" --out "$R/spawn_combos/$name.jsonl" >/dev/null || { echo "FAIL: py_trace.py combo $name"; return 1; }
	done <<'COMBOS'
cat_tradie_3 3 cat female:tradie
dog_rideshare_8 8 dog male:rideshare
budgie_none_12 12 budgie :
mouse_mixologist_21 21 mouse female:mixologist
none_parent_5 5 none male:parent
COMBOS
	python3 "$ROOT/scripts/py_trace.py" --seeds 0-9 --policy walk --steps 500 --out-dir "$R/walk_traces" >/dev/null || { echo "FAIL: py_trace.py --policy walk"; return 1; }
	# pet and hero combos (WALK_COMBOS): <name>.jsonl, mirrored in tests/test_s7_parity.gd
	mkdir -p "$R/walk_combos"
	while read -r name seed pet hero; do
		python3 "$ROOT/scripts/py_trace.py" --seed "$seed" --policy walk --steps 500 --pet "$pet" --hero "$hero" --out "$R/walk_combos/$name.jsonl" >/dev/null || { echo "FAIL: py_trace.py walk combo $name"; return 1; }
	done <<'COMBOS'
cat_tradie_3 3 cat female:tradie
cat_none_30 30 cat :
dog_rideshare_8 8 dog male:rideshare
dog_veteran_41 41 dog female:veteran
budgie_dog_walker_12 12 budgie male:dog_walker
budgie_none_27 27 budgie :
mouse_comedian_21 21 mouse female:comedian
mouse_parent_36 36 mouse male:parent
COMBOS
	python3 "$ROOT/scripts/py_trace.py" --seeds 0-4 --policy hunter --steps 3000 --out-dir "$R/hunter_traces" >/dev/null || { echo "FAIL: py_trace.py --policy hunter"; return 1; }
	# pet and hero combos (HUNTER_COMBOS): <name>.jsonl, mirrored in tests/test_s8_parity.gd
	mkdir -p "$R/hunter_combos"
	while read -r name seed pet hero; do
		python3 "$ROOT/scripts/py_trace.py" --seed "$seed" --policy hunter --steps 3000 --pet "$pet" --hero "$hero" --out "$R/hunter_combos/$name.jsonl" >/dev/null || { echo "FAIL: py_trace.py hunter combo $name"; return 1; }
	done <<'COMBOS'
cat_tradie_3 3 cat female:tradie
dog_rideshare_8 8 dog male:rideshare
budgie_dog_walker_12 12 budgie male:dog_walker
mouse_comedian_21 21 mouse female:comedian
cat_none_30 30 cat :
COMBOS
	python3 "$ROOT/scripts/py_trace.py" --seeds 0-3 --policy bot --steps 3000 --out-dir "$R/bot_traces" >/dev/null || { echo "FAIL: py_trace.py --policy bot"; return 1; }
	python3 "$ROOT/scripts/chaos_trace.py" --seeds 0-9 --steps 600 --out-dir "$R/chaos_traces" || { echo "FAIL: chaos_trace.py"; return 1; }
	#   telemetry (T4): CSV files of chaos seeds 0-15 (every outcome), compared byte for byte (CHAOS_CSV)
	python3 "$ROOT/scripts/chaos_trace.py" --seeds 0-15 --steps 200 --out-dir "$R/chaos_csv_traces" --telemetry-dir "$R/chaos_csv" || { echo "FAIL: chaos_trace.py --telemetry-dir"; return 1; }
	#   saves (T5): Python saves, and the traces of continuing with and without saving, seeds 0-7 (SAVE_TRACES; test_save_game)
	python3 "$ROOT/scripts/save_trace.py" --seeds 0-7 --steps 150 --out-dir "$R/save_traces" || { echo "FAIL: save_trace.py"; return 1; }
}

if [ ! -f "$REFDIR/.complete" ]; then
	BUILD="$REFDIR.partial.$$"
	rm -rf "$BUILD"; mkdir -p "$BUILD"
	build_refs "$BUILD" || { rm -rf "$BUILD"; exit 1; }
	touch "$BUILD/.complete"
	if [ "${GD_TEST_NO_CACHE:-}" = "1" ]; then
		cp -a "$BUILD"/. "$REFDIR"/ && rm -rf "$BUILD"
	else
		rm -rf "$REFDIR"; mv "$BUILD" "$REFDIR"
	fi
fi
export PY_RANDOM_REF="$REFDIR/py_random_ref.json" CONTENT_REF="$REFDIR/content_ref.json" FIXTURES="$REFDIR/fixtures.json" FIXTURES_S2="$REFDIR/fixtures_s2.json" PRACTICE_REF="$REFDIR/practice_ref.json" FIXTURES_S4="$REFDIR/fixtures_s4.json" DUNGEON_FIXTURES="$REFDIR/dungeon_fixtures.json" FLOOR_TRACES="$REFDIR/floor_traces" SPAWN_TRACES="$REFDIR/spawn_traces" SPAWN_COMBOS="$REFDIR/spawn_combos" WALK_TRACES="$REFDIR/walk_traces" WALK_COMBOS="$REFDIR/walk_combos" HUNTER_TRACES="$REFDIR/hunter_traces" HUNTER_COMBOS="$REFDIR/hunter_combos" CHAOS_TRACES="$REFDIR/chaos_traces" CHAOS_CSV="$REFDIR/chaos_csv" SAVE_TRACES="$REFDIR/save_traces" BOT_TRACES="$REFDIR/bot_traces" CRAWL_ROOT="$ROOT"

ARGS=()
for a in "$@"; do
	case "$a" in
		--file=*) ARGS+=("-gselect=${a#--file=}") ;;
		--test=*) ARGS+=("-gunit_test_name=${a#--test=}") ;;
		*) ARGS+=("$a") ;;
	esac
done
"$GODOT" --headless --path "$ROOT/godot" -s res://addons/gut/gut_cmdln.gd -gconfig=res://.gutconfig.json "${ARGS[@]}" 2>&1 | tee "$LOG"
status=${PIPESTATUS[0]}

fail=0
[ "$status" -eq 0 ] || { echo "gd_test: godot exited with $status"; fail=1; }
grep -q 'All tests passed!' "$LOG" || { echo "gd_test: GUT did not report 'All tests passed!'"; fail=1; }
if grep -Eq 'SCRIPT ERROR|Parse Error|Failed to load script|Failed to compile' "$LOG"; then
	echo "gd_test: script or parse errors in the log:"
	grep -En 'SCRIPT ERROR|Parse Error|Failed to load script|Failed to compile' "$LOG" | head -20
	fail=1
fi
[ "$fail" -eq 0 ] && echo "gd_test: OK" || echo "gd_test: FAILED"
exit "$fail"

#!/usr/bin/env bash
# Run every Godot headless test (port plan 8.3):
#   scripts/gd_test.sh                       # all
#   scripts/gd_test.sh --file=test_content   # files whose name contains this
#   scripts/gd_test.sh --test=reference_seed # tests whose name contains this
#   (any other argument goes straight to GUT, e.g. -glog=2)
#
# 1. imports the project (class_name needs .godot/global_script_class_cache.cfg; a headless
#    parse error can still exit 0, so step 4 also greps the log),
# 2. regenerates the Python references and fixtures (make_fixtures.py) into a temp dir (not committed: the RNG one is 12.7 MB),
# 2b. dungeon (S3): FOV/distance fixtures (DUNGEON_FIXTURES) and Python floor-only traces for seeds 0-49 (FLOOR_TRACES),
# 2c. world (S6): Python World floor-only traces for seeds 0-49 (SPAWN_TRACES),
# 2d. world (S7): Python `walk` run traces for seeds 0-9 (WALK_TRACES) and pet/hero combos (WALK_COMBOS),
# 3. runs GUT (addons/gut, settings in godot/.gutconfig.json),
# 4. passes only if the exit status is 0, GUT reports 'All tests passed!' and no SCRIPT ERROR /
#    parse error / failed-to-load line appears.
# Environment: GODOT (binary, default godot), GD_TEST_LOG (default /tmp/gd_test_<hash of checkout path>.log,
# so parallel worktrees never share a log).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
LOG="${GD_TEST_LOG:-${TMPDIR:-/tmp}/gd_test_$(echo "$ROOT" | md5sum | cut -c1-8).log}"
REFDIR="$(mktemp -d)"
trap 'rm -rf "$REFDIR"' EXIT

"$GODOT" --headless --path "$ROOT/godot" --import >/dev/null 2>&1

python3 "$ROOT/scripts/py_random_reference.py" "$REFDIR/py_random_ref.json" || { echo "FAIL: py_random_reference.py"; exit 1; }
python3 "$ROOT/scripts/content_reference.py" "$REFDIR/content_ref.json" || { echo "FAIL: content_reference.py"; exit 1; }
python3 "$ROOT/scripts/make_fixtures.py" "$REFDIR/fixtures.json" || { echo "FAIL: make_fixtures.py"; exit 1; }
python3 "$ROOT/scripts/make_fixtures_s2.py" "$REFDIR/fixtures_s2.json" || { echo "FAIL: make_fixtures_s2.py"; exit 1; }
python3 "$ROOT/scripts/practice_reference.py" "$REFDIR/practice_ref.json" || { echo "FAIL: practice_reference.py"; exit 1; }
python3 "$ROOT/scripts/make_fixtures_s4.py" "$REFDIR/fixtures_s4.json" || { echo "FAIL: make_fixtures_s4.py"; exit 1; }
export PY_RANDOM_REF="$REFDIR/py_random_ref.json" CONTENT_REF="$REFDIR/content_ref.json" FIXTURES="$REFDIR/fixtures.json" FIXTURES_S2="$REFDIR/fixtures_s2.json" PRACTICE_REF="$REFDIR/practice_ref.json" FIXTURES_S4="$REFDIR/fixtures_s4.json" DUNGEON_FIXTURES="$REFDIR/dungeon_fixtures.json" FLOOR_TRACES="$REFDIR/floor_traces" SPAWN_TRACES="$REFDIR/spawn_traces" SPAWN_COMBOS="$REFDIR/spawn_combos" WALK_TRACES="$REFDIR/walk_traces" WALK_COMBOS="$REFDIR/walk_combos"
python3 "$ROOT/scripts/make_dungeon_fixtures.py" "$REFDIR/dungeon_fixtures.json" || { echo "FAIL: make_dungeon_fixtures.py"; exit 1; }
python3 "$ROOT/scripts/py_trace.py" --seeds 0-49 --floor-only --floors 6 --out-dir "$REFDIR/floor_traces" >/dev/null || { echo "FAIL: py_trace.py --floor-only"; exit 1; }

python3 "$ROOT/scripts/py_trace.py" --seeds 0-49 --floor-only --spawns --floors 6 --out-dir "$REFDIR/spawn_traces" >/dev/null || { echo "FAIL: py_trace.py --floor-only --spawns"; exit 1; }
# pet and hero combos (SPAWN_COMBOS): <name>.jsonl, mirrored in tests/test_s6_parity.gd
mkdir -p "$REFDIR/spawn_combos"
while read -r name seed pet hero; do
	python3 "$ROOT/scripts/py_trace.py" --seed "$seed" --floor-only --spawns --floors 4 --pet "$pet" --hero "$hero" --out "$REFDIR/spawn_combos/$name.jsonl" >/dev/null || { echo "FAIL: py_trace.py combo $name"; exit 1; }
done <<'COMBOS'
cat_tradie_3 3 cat female:tradie
dog_rideshare_8 8 dog male:rideshare
budgie_none_12 12 budgie :
mouse_mixologist_21 21 mouse female:mixologist
none_parent_5 5 none male:parent
COMBOS

python3 "$ROOT/scripts/py_trace.py" --seeds 0-9 --policy walk --steps 500 --out-dir "$REFDIR/walk_traces" >/dev/null || { echo "FAIL: py_trace.py --policy walk"; exit 1; }
# pet and hero combos (WALK_COMBOS): <name>.jsonl, mirrored in tests/test_s7_parity.gd
mkdir -p "$REFDIR/walk_combos"
while read -r name seed pet hero; do
	python3 "$ROOT/scripts/py_trace.py" --seed "$seed" --policy walk --steps 500 --pet "$pet" --hero "$hero" --out "$REFDIR/walk_combos/$name.jsonl" >/dev/null || { echo "FAIL: py_trace.py walk combo $name"; exit 1; }
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

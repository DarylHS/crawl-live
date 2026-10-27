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
# 3. runs GUT (addons/gut, settings in godot/.gutconfig.json),
# 4. passes only if the exit status is 0, GUT reports 'All tests passed!' and no SCRIPT ERROR /
#    parse error / failed-to-load line appears.
# Environment: GODOT (binary, default godot), GD_TEST_LOG (default /tmp/gd_test.log).
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
LOG="${GD_TEST_LOG:-/tmp/gd_test.log}"
REFDIR="$(mktemp -d)"
trap 'rm -rf "$REFDIR"' EXIT

"$GODOT" --headless --path "$ROOT/godot" --import >/dev/null 2>&1

python3 "$ROOT/scripts/py_random_reference.py" "$REFDIR/py_random_ref.json" || { echo "FAIL: py_random_reference.py"; exit 1; }
python3 "$ROOT/scripts/content_reference.py" "$REFDIR/content_ref.json" || { echo "FAIL: content_reference.py"; exit 1; }
python3 "$ROOT/scripts/make_fixtures.py" "$REFDIR/fixtures.json" || { echo "FAIL: make_fixtures.py"; exit 1; }
export PY_RANDOM_REF="$REFDIR/py_random_ref.json" CONTENT_REF="$REFDIR/content_ref.json" FIXTURES="$REFDIR/fixtures.json"

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

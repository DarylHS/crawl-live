#!/usr/bin/env bash
# The full P1 acceptance parity run: Python (scripts/py_trace.py, chaos_trace.py, make_fixtures_s4.py) against
# Godot (godot/tools/trace.gd, chaos.gd, the S4 GUT test), far more seeds than the quick suite in gd_test.sh.
#
#   scripts/parity_all.sh            # everything; exit 0 only when every set is identical
#   PARITY_JOBS=8 scripts/parity_all.sh   # parallel jobs (default: nproc)
#   PARITY_KEEP=1 scripts/parity_all.sh   # keep the work directory (traces) for inspection
#
# Sets (all at --scope full, nothing muted on either side):
#   floors   floor-only traces, seeds 0-199, 6 floors                  (full scope)
#   spawns   World floors with spawns, seeds 0-499, 1 floor            (full)
#   walk     walk policy, seeds 0-49, 500 steps                        (full)
#   hunter   hunter policy, seeds 0-49, 3000 steps, with no pet and with 8 pet/hero combinations (full)
#   s4       S4 fixtures (loot, shop, items, bosses), seeds 0-199, via the GUT test test_s4_parity
#   chaos    chaos harness, seeds 0-215, 2500 steps (scripts/chaos_diff.py)
#   csv      telemetry CSV files of the same chaos runs (T4: chaos_trace.py / chaos.gd --telemetry-dir, compared
#            byte for byte with parity_diff.py --csv; every outcome, boxes, shop, practice, events)
# The bot policy needs the T6 BotPolicy and is not included. Every system is real on both sides and
# compared in full; --mute (scripts/mute.py) stays a debugging option and nothing here uses it.
set -u
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
GODOT="${GODOT:-godot}"
N="${PARITY_JOBS:-$(nproc)}"
WORK="$(mktemp -d "${TMPDIR:-/tmp}/parity_all.XXXXXX")"
[ "${PARITY_KEEP:-}" = "1" ] && echo "work directory: $WORK" || trap 'rm -rf "$WORK"' EXIT
START=$(date +%s)
cd "$ROOT" || exit 1

"$GODOT" --headless --path "$ROOT/godot" --import >/dev/null 2>&1

PY="python3 $ROOT/scripts/py_trace.py"
GD="$GODOT --headless --path $ROOT/godot -s res://tools/trace.gd --"
JOBS="$WORK/jobs.txt"
: > "$JOBS"

# chunk NAME LO HI SIZE: print "a-b" ranges
chunks() { local a=$1 b=$2 s=$3; while [ "$a" -le "$b" ]; do local e=$((a + s - 1)); [ "$e" -gt "$b" ] && e=$b; echo "$a-$e"; a=$((e + 1)); done; }

# add_set NAME PYARGS GDARGS HI SIZE: py and gd jobs per chunk of seeds into $WORK/{py,gd}_NAME
add_set() {
	local name=$1 pyargs=$2 gdargs=$3 hi=$4 size=$5 c
	mkdir -p "$WORK/py_$name" "$WORK/gd_$name"
	for c in $(chunks 0 "$hi" "$size"); do
		echo "$PY --seeds $c $pyargs --out-dir $WORK/py_$name >/dev/null" >> "$JOBS"
		echo "$GD --seeds $c $gdargs --out-dir $WORK/gd_$name >/dev/null 2>&1" >> "$JOBS"
	done
}

add_set floors "--floor-only --floors 6" "--floor-only --floors 6" 199 25
add_set spawns "--floor-only --spawns --floors 1" "--floor-only --spawns --floors 1" 499 50
add_set walk "--policy walk --steps 500" "--policy walk --steps 500" 49 13
add_set hunter "--policy hunter --steps 3000" "--policy hunter --steps 3000" 49 13
COMBOS=("cat female:tradie" "dog male:rideshare" "budgie male:dog_walker" "mouse female:comedian"
	"cat :" "dog female:veteran" "mouse male:parent" "budgie female:mixologist")
for combo in "${COMBOS[@]}"; do
	set -- $combo
	add_set "hunter_$1_${2//:/_}" "--policy hunter --steps 3000 --pet $1 --hero $2" "--policy hunter --steps 3000 --pet $1 --hero $2" 49 13
done
mkdir -p "$WORK/py_chaos" "$WORK/gd_chaos" "$WORK/py_csv" "$WORK/gd_csv"
for c in $(chunks 0 215 27); do
	echo "python3 $ROOT/scripts/chaos_trace.py --seeds $c --steps 2500 --out-dir $WORK/py_chaos --telemetry-dir $WORK/py_csv" >> "$JOBS"
	echo "$GODOT --headless --path $ROOT/godot -s res://tools/chaos.gd -- --seeds $c --steps 2500 --out-dir $WORK/gd_chaos --telemetry-dir $WORK/gd_csv >/dev/null 2>&1" >> "$JOBS"
done
echo "python3 $ROOT/scripts/make_fixtures_s4.py $WORK/fixtures_s4.json 200" >> "$JOBS"

echo "parity_all: generating traces ($(wc -l < "$JOBS") jobs on $N workers)..."
xargs -d '\n' -P "$N" -I CMD bash -c CMD < "$JOBS"

fail=0
check() { # check LABEL PY_DIR GD_DIR SEEDS SCOPE
	local out
	out="$(python3 "$ROOT/scripts/parity_diff.py" --dirs "$2" "$3" --seeds "$4" --scope "$5" 2>&1)"
	local rc=$?
	echo "$1: $(echo "$out" | tail -1)"
	[ "$rc" -eq 0 ] || { echo "$out" | grep -v "PARITY OK" | head -40; fail=1; }
}
check floors "$WORK/py_floors" "$WORK/gd_floors" 0-199 full
check spawns "$WORK/py_spawns" "$WORK/gd_spawns" 0-499 full
check walk "$WORK/py_walk" "$WORK/gd_walk" 0-49 full
check hunter "$WORK/py_hunter" "$WORK/gd_hunter" 0-49 full
for combo in "${COMBOS[@]}"; do
	set -- $combo
	check "hunter $1 $2" "$WORK/py_hunter_$1_${2//:/_}" "$WORK/gd_hunter_$1_${2//:/_}" 0-49 full
done

out="$(python3 "$ROOT/scripts/chaos_diff.py" --dirs "$WORK/py_chaos" "$WORK/gd_chaos" --seeds 0-215 2>&1)"
rc=$?
echo "chaos: $(echo "$out" | tail -1)"
[ "$rc" -eq 0 ] || { echo "$out" | grep -v ": SAME" | head -40; fail=1; }

out="$(python3 "$ROOT/scripts/parity_diff.py" --csv "$WORK/py_csv" "$WORK/gd_csv" 2>&1)"
rc=$?
echo "csv: $(echo "$out" | tail -1)"
[ "$rc" -eq 0 ] || { echo "$out" | head -40; fail=1; }

log="$WORK/s4.log"
FIXTURES_S4="$WORK/fixtures_s4.json" "$GODOT" --headless --path "$ROOT/godot" -s res://addons/gut/gut_cmdln.gd \
	-gconfig=res://.gutconfig.json -gselect=test_s4_parity > "$log" 2>&1
if grep -q 'All tests passed!' "$log" && ! grep -Eq 'SCRIPT ERROR|Parse Error' "$log"; then
	echo "s4: $(grep -o 'S4 parity: [^"]*' "$log" | head -1)"
else
	echo "s4: FAILED"; tail -30 "$log"; fail=1
fi

echo "parity_all: $([ "$fail" -eq 0 ] && echo 'ALL IDENTICAL' || echo 'MISMATCH') in $(( $(date +%s) - START )) s"
exit "$fail"

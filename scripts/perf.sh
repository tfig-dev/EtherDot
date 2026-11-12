#!/bin/bash
# Measures what EtherDot costs while it sits idle in the menu bar.
#
#   scripts/perf.sh [path/to/EtherDot.app] [seconds]
#
# Launches the app, lets it settle, then reports CPU time, average CPU share,
# idle wake-ups, memory and how many times it refreshed over the interval.
# Budget: under 0.1% CPU and no periodic refreshes while nothing changes.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-build/EtherDot.app}"
SECONDS_TO_MEASURE="${2:-60}"
BIN="$APP/Contents/MacOS/EtherDot"
[ -x "$BIN" ] || { echo "error: $BIN not found (run scripts/build-app.sh)" >&2; exit 1; }

LOG="$(mktemp)"
ETHERDOT_TRACE=1 "$BIN" --allow-multiple 2>"$LOG" &
PID=$!
trap 'kill $PID 2>/dev/null; wait $PID 2>/dev/null || true; rm -f "$LOG"' EXIT
sleep 8   # launch, first refresh, Sparkle start-up

cpu_seconds() { ps -o cputime= -p "$PID" | awk -F'[:.]' '{ printf "%.2f", $1 * 60 + $2 + $3 / 100 }'; }
BEFORE_CPU="$(cpu_seconds)"
BEFORE_REFRESH="$(grep -c '^refresh' "$LOG" || true)"

SAMPLE="$(top -l 2 -s "$SECONDS_TO_MEASURE" -pid "$PID" -stats cpu,idlew,mem,power | tail -1)"

AFTER_CPU="$(cpu_seconds)"
AFTER_REFRESH="$(grep -c '^refresh' "$LOG" || true)"

echo "EtherDot idle over ${SECONDS_TO_MEASURE}s ($APP)"
awk -v a="$BEFORE_CPU" -v b="$AFTER_CPU" -v s="$SECONDS_TO_MEASURE" \
  'BEGIN { printf "  CPU time used:   %.2f s  (%.3f%% of one core)\n", b - a, (b - a) / s * 100 }'
echo "$SAMPLE" | awk '{ printf "  top: CPU %s%%, idle wake-ups %s, memory %s, power %s\n", $1, $2, $3, $4 }'
echo "  refreshes:       $((AFTER_REFRESH - BEFORE_REFRESH))"

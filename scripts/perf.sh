#!/bin/bash
# Measures what EtherDot costs while it sits idle in the menu bar, and fails when
# it goes over budget. Used locally and by CI on every push and pull request.
#
#   scripts/perf.sh [path/to/EtherDot.app] [seconds]
#
#   MAX_CPU_PERCENT=0.1        budget: average share of one CPU core while idle
#   MAX_REFRESHES_PER_MIN=2    budget: network refreshes per minute while idle
#                              (1.1.0 does one per minute as a safety net)
#
# Exits 1 when a budget is exceeded. Writes a Markdown table to $GITHUB_STEP_SUMMARY
# when that variable is set.
set -euo pipefail
cd "$(dirname "$0")/.."

APP="${1:-build/EtherDot.app}"
DURATION="${2:-60}"
MAX_CPU_PERCENT="${MAX_CPU_PERCENT:-0.1}"
MAX_REFRESHES_PER_MIN="${MAX_REFRESHES_PER_MIN:-2}"
BIN="$APP/Contents/MacOS/EtherDot"
[ -x "$BIN" ] || { echo "error: $BIN not found (run scripts/build-app.sh)" >&2; exit 1; }

LOG="$(mktemp)"
ETHERDOT_TRACE=1 "$BIN" --allow-multiple 2>"$LOG" &
PID=$!
trap 'kill $PID 2>/dev/null; wait $PID 2>/dev/null || true; rm -f "$LOG"' EXIT
sleep 8   # launch, first refresh, Sparkle start-up
kill -0 "$PID" 2>/dev/null || { echo "error: EtherDot exited during start-up" >&2; cat "$LOG" >&2; exit 1; }

cpu_seconds() { ps -o cputime= -p "$PID" | awk -F'[:.]' '{ printf "%.2f", $1 * 60 + $2 + $3 / 100 }'; }
BEFORE_CPU="$(cpu_seconds)"
BEFORE_REFRESH="$(grep -c '^refresh' "$LOG" || true)"

SAMPLE="$(top -l 2 -s "$DURATION" -pid "$PID" -stats cpu,idlew,mem | tail -1)"

AFTER_CPU="$(cpu_seconds)"
AFTER_REFRESH="$(grep -c '^refresh' "$LOG" || true)"

CPU_USED="$(awk -v a="$BEFORE_CPU" -v b="$AFTER_CPU" 'BEGIN { printf "%.2f", b - a }')"
CPU_PERCENT="$(awk -v c="$CPU_USED" -v s="$DURATION" 'BEGIN { printf "%.3f", c / s * 100 }')"
REFRESHES=$((AFTER_REFRESH - BEFORE_REFRESH))
REFRESH_RATE="$(awk -v r="$REFRESHES" -v s="$DURATION" 'BEGIN { printf "%.2f", r / s * 60 }')"
WAKEUPS="$(echo "$SAMPLE" | awk '{ print $2 }')"
MEMORY="$(echo "$SAMPLE" | awk '{ print $3 }')"

CPU_OK="$(awk -v v="$CPU_PERCENT" -v m="$MAX_CPU_PERCENT" 'BEGIN { print (v <= m) ? "pass" : "FAIL" }')"
REFRESH_OK="$(awk -v v="$REFRESH_RATE" -v m="$MAX_REFRESHES_PER_MIN" 'BEGIN { print (v <= m) ? "pass" : "FAIL" }')"

echo "EtherDot idle over ${DURATION}s ($APP)"
echo "  CPU:        ${CPU_USED} s = ${CPU_PERCENT}% of one core   (budget ${MAX_CPU_PERCENT}%)   $CPU_OK"
echo "  Refreshes:  ${REFRESHES} = ${REFRESH_RATE} per minute       (budget ${MAX_REFRESHES_PER_MIN})        $REFRESH_OK"
echo "  Wake-ups:   ${WAKEUPS} (top, idle wake-ups in the last interval)"
echo "  Memory:     ${MEMORY}"

if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
  {
    echo "### Idle performance (${DURATION} s)"
    echo "| Metric | Value | Budget | Result |"
    echo "| --- | --- | --- | --- |"
    echo "| CPU | ${CPU_PERCENT}% of one core | ${MAX_CPU_PERCENT}% | ${CPU_OK} |"
    echo "| Refreshes | ${REFRESH_RATE} / min | ${MAX_REFRESHES_PER_MIN} / min | ${REFRESH_OK} |"
    echo "| Idle wake-ups | ${WAKEUPS} | | |"
    echo "| Memory | ${MEMORY} | | |"
  } >> "$GITHUB_STEP_SUMMARY"
fi

[ "$CPU_OK" = pass ] && [ "$REFRESH_OK" = pass ]

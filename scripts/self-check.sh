#!/bin/bash
# Builds a debug copy of EtherDot and lets it drive its own UI: opens the menu,
# hovers a connection, opens each Settings tab, writes PNG snapshots and a report.
# These tools only exist in debug builds; release builds do not contain them.
#
#   scripts/self-check.sh                  real network data, output in build/self-check
#   scripts/self-check.sh --demo           sample data (no personal network names)
#   scripts/self-check.sh --screenshots    sample data, and copies the snapshots to docs/screenshots
set -euo pipefail
cd "$(dirname "$0")/.."

ARGS=()
OUT="build/self-check"
COPY=0
case "${1:-}" in
  --demo) ARGS=(--demo --expand-networks) ;;
  --screenshots) ARGS=(--demo --expand-networks); COPY=1 ;;
  "") ;;
  *) echo "usage: $0 [--demo | --screenshots]" >&2; exit 2 ;;
esac

APP_PATH=build/debug/EtherDot.app CONFIGURATION=debug ARCHS="$(uname -m)" ./scripts/build-app.sh
rm -rf "$OUT"
build/debug/EtherDot.app/Contents/MacOS/EtherDot --self-check "$PWD/$OUT" "${ARGS[@]}"
cat "$OUT/report.txt"

if [ "$COPY" = 1 ]; then
  mkdir -p docs/screenshots
  cp "$OUT"/menu.png "$OUT"/details.png "$OUT"/settings-*.png docs/screenshots/
  echo "Screenshots copied to docs/screenshots"
fi

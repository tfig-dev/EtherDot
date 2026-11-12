#!/bin/bash
# Runs the unit tests. With full Xcode this is plain `swift test`; with only the
# Command Line Tools, Swift Testing is installed outside the default search paths.
set -euo pipefail
cd "$(dirname "$0")/.."

if xcodebuild -version >/dev/null 2>&1; then
  exec swift test "$@"
fi

CLT=/Library/Developer/CommandLineTools
FRAMEWORKS="$CLT/Library/Developer/Frameworks"
exec swift test \
  -Xswiftc -F"$FRAMEWORKS" \
  -Xswiftc -plugin-path -Xswiftc "$CLT/usr/lib/swift/host/plugins/testing" \
  -Xlinker -F"$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$FRAMEWORKS" \
  -Xlinker -rpath -Xlinker "$CLT/Library/Developer/usr/lib" \
  "$@"

#!/bin/bash
# Points the Homebrew cask at the DMG that was just built.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
DMG="dist/EtherDot-$VERSION.dmg"
SHA="$(shasum -a 256 "$DMG" | awk '{print $1}')"

sed -i '' -E \
  -e "s/^  version \".*\"/  version \"$VERSION\"/" \
  -e "s/^  sha256 .*/  sha256 \"$SHA\"/" \
  Casks/etherdot.rb
echo "Cask updated to $VERSION ($SHA)"

#!/bin/bash
# Packages build/EtherDot.app into dist/EtherDot-<version>.dmg with the
# drag-to-Applications window. Signs and notarizes when credentials are present:
#
#   CODESIGN_IDENTITY                      Developer ID identity (optional)
#   NOTARY_KEY_PATH / NOTARY_KEY_ID / NOTARY_ISSUER_ID   App Store Connect API key (optional)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
APP="build/EtherDot.app"
DMG="dist/EtherDot-$VERSION.dmg"
[ -d "$APP" ] || { echo "error: $APP not found, run scripts/build-app.sh first" >&2; exit 1; }

mkdir -p dist build
rm -f "$DMG"
# One retina-aware background: 600x400 pt at 1x and 2x.
tiffutil -cathidpicheck dmg/background.png dmg/background@2x.png -out build/dmg-background.tiff >/dev/null

STAGE="$(mktemp -d)"
trap 'rm -rf "$STAGE"' EXIT
ditto "$APP" "$STAGE/EtherDot.app"

if command -v create-dmg >/dev/null 2>&1; then
  # Finder scripting on CI runners is occasionally flaky, so retry.
  for attempt in 1 2 3; do
    rm -f "$DMG"
    if create-dmg \
        --volname "EtherDot" \
        --volicon Assets/AppIcon.icns \
        --background build/dmg-background.tiff \
        --window-pos 200 120 \
        --window-size 600 428 \
        --icon-size 112 \
        --text-size 12 \
        --icon "EtherDot.app" 150 215 \
        --hide-extension "EtherDot.app" \
        --app-drop-link 450 215 \
        --no-internet-enable \
        "$DMG" "$STAGE"; then
      break
    fi
    echo "create-dmg attempt $attempt failed" >&2
    [ "$attempt" -lt 3 ] || { rm -f "$DMG"; }
  done
fi

if [ ! -f "$DMG" ]; then
  echo "==> Falling back to a plain DMG (no window layout)"
  ln -s /Applications "$STAGE/Applications"
  hdiutil create -volname "EtherDot" -srcfolder "$STAGE" -ov -format UDZO "$DMG"
fi

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  echo "==> Signing DMG"
  codesign --force --timestamp --sign "$CODESIGN_IDENTITY" "$DMG"
  if [ -n "${NOTARY_KEY_PATH:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] && [ -n "${NOTARY_ISSUER_ID:-}" ]; then
    echo "==> Notarizing"
    xcrun notarytool submit "$DMG" --key "$NOTARY_KEY_PATH" --key-id "$NOTARY_KEY_ID" --issuer "$NOTARY_ISSUER_ID" --wait
    xcrun stapler staple "$DMG"
    xcrun stapler validate "$DMG"
  else
    echo "==> Notarization credentials missing: DMG is signed but not notarized"
  fi
else
  echo "==> Unsigned build: skipping DMG signing and notarization"
fi

echo "==> Built $DMG"

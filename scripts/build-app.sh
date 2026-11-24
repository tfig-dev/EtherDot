#!/bin/bash
# Builds build/EtherDot.app from the Swift package.
#
#   ARCHS="arm64 x86_64"   architectures to build (default: universal)
#   CONFIGURATION=release  "debug" builds include the --self-check and --demo tools
#   CODESIGN_IDENTITY=...  Developer ID identity: hardened runtime, ready for notarization
#   SELF_SIGN_IDENTITY=... self-signed certificate (name or SHA-1). Gives every release the
#                          same code identity, so macOS keeps the Location permission across
#                          updates. When unset, the "EtherDot Self-Signed" certificate is used
#                          if it is in the keychain.
#   ADHOC=1                force an ad-hoc signature
#   APP_PATH=...           where to write the bundle (default build/EtherDot.app)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
ARCHS="${ARCHS:-arm64 x86_64}"
CONFIGURATION="${CONFIGURATION:-release}"
APP="${APP_PATH:-build/EtherDot.app}"
CONTENTS="$APP/Contents"

echo "==> Building EtherDot $VERSION ($ARCHS, $CONFIGURATION)"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

BINARIES=()
BIN_DIR=""
for arch in $ARCHS; do
  swift build -c "$CONFIGURATION" --product EtherDot --arch "$arch"
  BIN_DIR="$(swift build -c "$CONFIGURATION" --arch "$arch" --show-bin-path)"
  BINARIES+=("$BIN_DIR/EtherDot")
done
lipo -create "${BINARIES[@]}" -output "$CONTENTS/MacOS/EtherDot"

# Sparkle ships as a universal framework; SwiftPM drops it next to the binary.
ditto "$BIN_DIR/Sparkle.framework" "$CONTENTS/Frameworks/Sparkle.framework"
install_name_tool -add_rpath "@executable_path/../Frameworks" "$CONTENTS/MacOS/EtherDot" 2>/dev/null || true

sed "s/__VERSION__/$VERSION/g" Support/Info.plist > "$CONTENTS/Info.plist"
printf 'APPL????' > "$CONTENTS/PkgInfo"

# App icon: compile the asset catalog when Xcode is installed, otherwise use the
# pre-rendered .icns generated from the same artwork (swift run IconGenerator).
if xcrun --find actool >/dev/null 2>&1; then
  xcrun actool Assets/Assets.xcassets --compile "$CONTENTS/Resources" \
    --platform macosx --minimum-deployment-target 13.0 --app-icon AppIcon \
    --output-partial-info-plist "$(dirname "$APP")/assetcatalog-info.plist" >/dev/null
fi
[ -f "$CONTENTS/Resources/AppIcon.icns" ] || cp Assets/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

SPARKLE="$CONTENTS/Frameworks/Sparkle.framework/Versions/B"

# Signs nested code first, then the app, as codesign requires.
sign_bundle() {
  "$@" "$SPARKLE/XPCServices/Installer.xpc"
  "$@" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
  "$@" "$SPARKLE/Autoupdate"
  "$@" "$SPARKLE/Updater.app"
  "$@" "$CONTENTS/Frameworks/Sparkle.framework"
}

if [ -z "${CODESIGN_IDENTITY:-}" ] && [ -z "${SELF_SIGN_IDENTITY:-}" ] && [ "${ADHOC:-0}" != 1 ]; then
  # Untrusted self-signed identities are only listed without -v, and codesign needs the SHA-1.
  SELF_SIGN_IDENTITY="$(security find-identity -p codesigning 2>/dev/null \
    | awk '/"EtherDot Self-Signed"/ { print $2; exit }')"
fi

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  echo "==> Signing with Developer ID: $CODESIGN_IDENTITY"
  SIGN=(codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY")
  sign_bundle "${SIGN[@]}"
  "${SIGN[@]}" --entitlements Support/EtherDot.entitlements "$APP"
elif [ -n "${SELF_SIGN_IDENTITY:-}" ]; then
  # No hardened runtime: it is only needed for notarization, which a self-signed
  # certificate cannot get, and it would block loading Sparkle (no Team ID).
  echo "==> Signing with self-signed certificate $SELF_SIGN_IDENTITY"
  SIGN=(codesign --force --timestamp=none --sign "$SELF_SIGN_IDENTITY")
  sign_bundle "${SIGN[@]}"
  "${SIGN[@]}" "$APP"
else
  echo "==> No signing identity: ad-hoc signature (macOS will ask for Location again after each update)"
  codesign --force --deep --sign - "$APP"
fi

codesign --verify --deep --strict "$APP"
codesign -d -r- "$APP" 2>&1 | sed -n 's/^designated => /==> Designated requirement: /p'
echo "==> Built $APP"

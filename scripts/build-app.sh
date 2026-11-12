#!/bin/bash
# Builds build/EtherDot.app from the Swift package.
#
#   ARCHS="arm64 x86_64"   architectures to build (default: universal)
#   CODESIGN_IDENTITY=...  Developer ID identity; unset = ad-hoc signature (unsigned build)
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="$(tr -d '[:space:]' < VERSION)"
ARCHS="${ARCHS:-arm64 x86_64}"
APP="build/EtherDot.app"
CONTENTS="$APP/Contents"

echo "==> Building EtherDot $VERSION ($ARCHS)"
rm -rf "$APP"
mkdir -p "$CONTENTS/MacOS" "$CONTENTS/Resources" "$CONTENTS/Frameworks"

BINARIES=()
BIN_DIR=""
for arch in $ARCHS; do
  swift build -c release --product EtherDot --arch "$arch"
  BIN_DIR="$(swift build -c release --arch "$arch" --show-bin-path)"
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
    --output-partial-info-plist build/assetcatalog-info.plist >/dev/null
fi
[ -f "$CONTENTS/Resources/AppIcon.icns" ] || cp Assets/AppIcon.icns "$CONTENTS/Resources/AppIcon.icns"

if [ -n "${CODESIGN_IDENTITY:-}" ]; then
  echo "==> Signing with $CODESIGN_IDENTITY"
  SIGN=(codesign --force --options runtime --timestamp --sign "$CODESIGN_IDENTITY")
  SPARKLE="$CONTENTS/Frameworks/Sparkle.framework/Versions/B"
  "${SIGN[@]}" "$SPARKLE/XPCServices/Installer.xpc"
  "${SIGN[@]}" --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
  "${SIGN[@]}" "$SPARKLE/Autoupdate"
  "${SIGN[@]}" "$SPARKLE/Updater.app"
  "${SIGN[@]}" "$CONTENTS/Frameworks/Sparkle.framework"
  "${SIGN[@]}" --entitlements Support/EtherDot.entitlements "$APP"
else
  echo "==> No CODESIGN_IDENTITY: ad-hoc signing (unsigned build)"
  codesign --force --deep --sign - "$APP"
fi

codesign --verify --deep --strict "$APP"
echo "==> Built $APP"

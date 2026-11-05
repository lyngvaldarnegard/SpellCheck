#!/bin/sh
# Builds SpellCheck.app into build/ (requires macOS + Swift 6 toolchain).
#
# Usage:
#   scripts/build-app.sh                 # release build -> build/SpellCheck.app
#   scripts/build-app.sh debug           # debug build
#   SIGNING_IDENTITY="Developer ID Application: …" scripts/build-app.sh
#     additionally code-signs the bundle (needed for distribution outside
#     the App Store / to avoid Gatekeeper warnings after notarization).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CONFIG="${1:-release}"
APP_DIR="$ROOT/build/SpellCheck.app"

swift build --package-path "$ROOT/App" -c "$CONFIG"
BIN_DIR="$(swift build --package-path "$ROOT/App" -c "$CONFIG" --show-bin-path)"

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"
cp "$BIN_DIR/SpellCheck" "$APP_DIR/Contents/MacOS/SpellCheck"
cp "$ROOT/App/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

if [ -d "$ROOT/App/Resources/AppIcon.iconset" ]; then
    iconutil -c icns "$ROOT/App/Resources/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

if [ -f "$ROOT/App/Resources/MenuBarIconTemplate.png" ]; then
    cp "$ROOT/App/Resources/MenuBarIconTemplate.png" "$APP_DIR/Contents/Resources/"
    cp "$ROOT/App/Resources/MenuBarIconTemplate@2x.png" "$APP_DIR/Contents/Resources/" 2>/dev/null || true
fi

if [ -n "${SIGNING_IDENTITY:-}" ]; then
    codesign --force --deep --options runtime --sign "$SIGNING_IDENTITY" "$APP_DIR"
    echo "Signed $APP_DIR with: $SIGNING_IDENTITY"
fi

echo "Built $APP_DIR"

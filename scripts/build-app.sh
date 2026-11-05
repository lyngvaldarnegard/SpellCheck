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

if swift build --package-path "$ROOT/App" -c "$CONFIG" --arch arm64 --arch x86_64 2>/dev/null; then
    BIN_DIR="$(swift build --package-path "$ROOT/App" -c "$CONFIG" --arch arm64 --arch x86_64 --show-bin-path)"
else
    swift build --package-path "$ROOT/App" -c "$CONFIG"
    BIN_DIR="$(swift build --package-path "$ROOT/App" -c "$CONFIG" --show-bin-path)"
fi

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" "$APP_DIR/Contents/Frameworks"
cp "$BIN_DIR/SpellCheck" "$APP_DIR/Contents/MacOS/SpellCheck"
cp "$ROOT/App/Info.plist" "$APP_DIR/Contents/Info.plist"
printf 'APPL????' > "$APP_DIR/Contents/PkgInfo"

# Embed dynamic dependency frameworks (e.g. Sparkle). Without these the app
# dies at launch with "dyld: Library not loaded: @rpath/...".
for fw in "$BIN_DIR"/*.framework; do
    [ -e "$fw" ] || continue
    cp -R "$fw" "$APP_DIR/Contents/Frameworks/"
done
if ! ls "$APP_DIR/Contents/Frameworks"/*.framework >/dev/null 2>&1; then
    find "$ROOT/App/.build" -maxdepth 4 -type d -name "*.framework" 2>/dev/null | while read -r fw; do
        cp -R "$fw" "$APP_DIR/Contents/Frameworks/"
    done
fi

# Make sure the executable can find its frameworks at runtime.
if ! otool -l "$APP_DIR/Contents/MacOS/SpellCheck" 2>/dev/null | grep -q "@executable_path/../Frameworks"; then
    install_name_tool -add_rpath "@executable_path/../Frameworks" "$APP_DIR/Contents/MacOS/SpellCheck"
fi

# Stamp the release version into the bundle (e.g. VERSION=v0.1.4).
if [ -n "${VERSION:-}" ]; then
    plutil -replace CFBundleShortVersionString -string "$VERSION" "$APP_DIR/Contents/Info.plist"
    plutil -replace CFBundleVersion -string "${VERSION#v}" "$APP_DIR/Contents/Info.plist"
fi

if [ -d "$ROOT/App/Resources/AppIcon.iconset" ]; then
    iconutil -c icns "$ROOT/App/Resources/AppIcon.iconset" -o "$APP_DIR/Contents/Resources/AppIcon.icns"
fi

if [ -f "$ROOT/App/Resources/MenuBarIconTemplate.png" ]; then
    cp "$ROOT/App/Resources/MenuBarIconTemplate.png" "$APP_DIR/Contents/Resources/"
    cp "$ROOT/App/Resources/MenuBarIconTemplate@2x.png" "$APP_DIR/Contents/Resources/" 2>/dev/null || true
fi

# selectable menu-bar icon styles (Settings -> Menu Bar Icon)
if [ -d "$ROOT/App/Resources/MenuBarIcons" ]; then
    cp -R "$ROOT/App/Resources/MenuBarIcons" "$APP_DIR/Contents/Resources/"
fi

if [ -n "${SIGNING_IDENTITY:-}" ]; then
    # sign embedded frameworks first, then the bundle itself
    for fw in "$APP_DIR/Contents/Frameworks"/*.framework; do
        [ -e "$fw" ] || continue
        codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$fw"
    done
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" "$APP_DIR"
    echo "Signed $APP_DIR with: $SIGNING_IDENTITY"
fi

echo "Built $APP_DIR"

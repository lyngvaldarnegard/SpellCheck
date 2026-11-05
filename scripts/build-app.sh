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

# Always sign the complete bundle. An unsigned .app only carries the
# linker's ad-hoc signature on the raw executable, with Info.plist unbound
# and no TeamIdentifier — macOS TCC (Accessibility) then treats every build
# as a different app and keeps re-prompting. Signing the whole bundle binds
# Info.plist and resources into the signature.
#
# IMPORTANT — hardened runtime / library validation:
#   `--options runtime` enables the hardened runtime, which turns on
#   library validation: every loaded library must then be signed by the
#   SAME team as the main executable. Embedded binaries like Sparkle's
#   framework are pre-signed by Sparkle's Developer ID team; loading them
#   into an ad-hoc (no team) hardened process aborts at launch with
#   "dyld: ... different Team IDs". Therefore:
#     - ad-hoc builds (no SIGNING_IDENTITY) are signed WITHOUT the
#       hardened runtime, and every embedded component is re-signed
#       ad-hoc as well, so the whole bundle carries one consistent
#       (team-less) identity;
#     - Developer ID builds re-sign all embedded components with the
#       Developer ID identity (innermost first, preserving entitlements)
#       and use the hardened runtime.
# With SIGNING_IDENTITY (Developer ID Application: …) the stable identity
# survives across builds. Without it we fall back to ad-hoc signing
# (--sign -), which makes each build self-consistent but yields a NEW
# identity per build — re-adding the app in Accessibility settings may be
# needed after each update until a Developer ID certificate is configured.
IDENTITY="${SIGNING_IDENTITY:--}"
if [ "$IDENTITY" = "-" ]; then
    RUNTIME_OPTS=""
else
    RUNTIME_OPTS="--options runtime"
fi

# Re-sign one code item, preserving its existing entitlements.
sign_item() {
    item="$1"
    ent_file=$(mktemp)
    if codesign -d --entitlements :- "$item" 2>/dev/null | head -c 1 | grep -q '<'; then
        codesign -d --entitlements :- "$item" 2>/dev/null > "$ent_file"
        codesign --force $RUNTIME_OPTS --entitlements "$ent_file" --sign "$IDENTITY" "$item"
    else
        codesign --force $RUNTIME_OPTS --sign "$IDENTITY" "$item"
    fi
    rm -f "$ent_file"
}

# Sign embedded frameworks innermost-first: nested XPC services and helper
# apps first, then helper binaries, then the framework itself, then the app.
for fw in "$APP_DIR/Contents/Frameworks"/*.framework; do
    [ -e "$fw" ] || continue
    find "$fw" -name "*.xpc" -type d | while read -r nested; do
        sign_item "$nested"
    done
    find "$fw" -name "*.app" -type d | while read -r nested; do
        sign_item "$nested"
    done
    find "$fw/Versions" -type f ! -name "*.plist" ! -name "*.nib" 2>/dev/null | while read -r bin; do
        # only Mach-O binaries carry a signature to replace
        if codesign -d "$bin" >/dev/null 2>&1; then
            sign_item "$bin"
        fi
    done
    sign_item "$fw"
done
codesign --force $RUNTIME_OPTS --sign "$IDENTITY" "$APP_DIR"
if [ "$IDENTITY" = "-" ]; then
    echo "Ad-hoc signed $APP_DIR (no hardened runtime; set SIGNING_IDENTITY to a Developer ID certificate for a stable identity)"
else
    echo "Signed $APP_DIR with: $IDENTITY (hardened runtime)"
fi

echo "Built $APP_DIR"

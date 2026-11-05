#!/bin/sh
# Verifies that a built .app bundle is complete and self-contained, so a broken
# release can never ship silently:
#   - Info.plist exists and CFBundleExecutable points at a real file
#   - the executable has the @executable_path/../Frameworks rpath
#   - every @rpath dependency of the executable AND of every embedded framework
#     resolves inside Contents/Frameworks (catches the classic
#     "dyld: Library not loaded: @rpath/Sparkle.framework/..." launch crash)
#   - required resources are present
#
# Usage (macOS): scripts/verify-bundle.sh [path/to/SpellCheck.app]
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:-$ROOT/build/SpellCheck.app}"

fail=0
bad() { echo "FAIL: $*"; fail=1; }
ok() { echo "  ok: $*"; }

INFO="$APP_DIR/Contents/Info.plist"
if [ ! -f "$INFO" ]; then
    echo "FAIL: missing $INFO"
    exit 1
fi

exe_name="$(plutil -extract CFBundleExecutable raw "$INFO")"
EXE="$APP_DIR/Contents/MacOS/$exe_name"
if [ ! -f "$EXE" ]; then
    bad "missing executable Contents/MacOS/$exe_name (CFBundleExecutable=$exe_name)"
else
    ok "executable Contents/MacOS/$exe_name"
fi

if [ -f "$EXE" ]; then
    if otool -l "$EXE" | grep -q "@executable_path/../Frameworks"; then
        ok "executable has @executable_path/../Frameworks rpath"
    else
        bad "executable lacks @executable_path/../Frameworks rpath — @rpath frameworks will not load"
    fi
fi

# check that every @rpath dependency of a Mach-O binary resolves inside the bundle
check_deps() {
    bin="$1"
    otool -L "$bin" 2>/dev/null | awk 'NR>1 && $1 ~ /^@rpath\// {print $1}' | while read -r dep; do
        rel="${dep#@rpath/}"
        if [ ! -e "$APP_DIR/Contents/Frameworks/$rel" ]; then
            echo "FAIL: $bin needs $dep but Contents/Frameworks/$rel is missing"
        else
            echo "  ok: $dep"
        fi
    done
}

if [ -f "$EXE" ]; then
    echo "Checking executable dependencies:"
    out="$(check_deps "$EXE")"
    echo "$out"
    echo "$out" | grep -q FAIL && fail=1
fi

archs_of() {
    lipo -info "$1" 2>/dev/null | sed -n 's/.*are: //p; s/.*architecture: //p'
}

if [ -d "$APP_DIR/Contents/Frameworks" ]; then
    for fw in "$APP_DIR/Contents/Frameworks"/*.framework; do
        [ -e "$fw" ] || continue
        echo "Checking framework $(basename "$fw"):"
        for bin in "$fw"/Versions/*/*; do
            [ -f "$bin" ] || continue
            otool -L "$bin" >/dev/null 2>&1 || continue
            out="$(check_deps "$bin")"
            [ -n "$out" ] && echo "$out"
            echo "$out" | grep -q FAIL && fail=1
            # the framework binary must support every arch the executable has
            if [ -f "$EXE" ]; then
                exe_archs="$(archs_of "$EXE")"
                fw_archs="$(archs_of "$bin")"
                for arch in $exe_archs; do
                    if ! echo "$fw_archs" | grep -qw "$arch"; then
                        bad "$bin is missing arch '$arch' (executable has: $exe_archs)"
                    fi
                done
            fi
        done
    done
else
    # no frameworks dir at all is only OK if the executable has no @rpath deps
    if [ -f "$EXE" ] && otool -L "$EXE" | awk 'NR>1 && $1 ~ /^@rpath\//' | grep -q .; then
        bad "executable has @rpath dependencies but Contents/Frameworks is missing"
    fi
fi

for res in AppIcon.icns MenuBarIconTemplate.png MenuBarIcons/omega-check.png MenuBarIcons/omega-check.pdf MenuBarIcons/omega.pdf MenuBarIcons/spellcheck.pdf MenuBarIcons/checkmark.pdf; do
    if [ -e "$APP_DIR/Contents/Resources/$res" ]; then
        ok "resource $res"
    else
        bad "missing resource Contents/Resources/$res"
    fi
done

# The bundle must be code-signed as a whole (Info.plist bound into the
# signature). "adhoc, linker-signed" with an unbound Info.plist makes TCC
# treat every build as a new app.
codesign_info="$(codesign -dv "$APP_DIR" 2>&1 || true)"
app_flags="$(echo "$codesign_info" | sed -n 's/.*flags=[^ ]*(\([^)]*\)).*/\1/p' | head -1)"
app_team="$(echo "$codesign_info" | sed -n 's/^TeamIdentifier=//p' | head -1)"
if echo "$codesign_info" | grep -q "Signature=adhoc"; then
    ok "bundle is code-signed (adhoc)"
elif echo "$codesign_info" | grep -q "Signature="; then
    ok "bundle is code-signed"
else
    bad "bundle is NOT code-signed (Accessibility/TCC identity will be unstable)"
fi
if ! codesign --verify "$APP_DIR" >/dev/null 2>&1; then
    bad "bundle signature does not verify (codesign --verify failed)"
fi

# Library-validation safety: a hardened-runtime (flags contain "runtime")
# main executable turns on library validation — every loaded library must
# then be signed by the SAME team. Sparkle and other embedded frameworks
# ship pre-signed by their own Developer ID teams, so an ad-hoc hardened
# build aborts at launch with "dyld: ... different Team IDs". Reject that
# combination outright instead of shipping an app that cannot start.
if echo "$app_flags" | grep -qw runtime; then
    ok "hardened runtime is enabled"
    if [ -z "$app_team" ]; then
        bad "ad-hoc signature + hardened runtime = library validation will reject embedded frameworks at launch (dyld: different Team IDs). Either sign with a Developer ID identity or drop --options runtime for ad-hoc builds."
    fi
fi

# Every embedded framework must be signed, and with the same team as the
# app when the app has a team (mixed teams are fine without library
# validation, but consistency is what TCC and updates want).
if [ -d "$APP_DIR/Contents/Frameworks" ]; then
    for fw in "$APP_DIR/Contents/Frameworks"/*.framework; do
        [ -e "$fw" ] || continue
        fw_info="$(codesign -dv "$fw" 2>&1 || true)"
        fw_team="$(echo "$fw_info" | sed -n 's/^TeamIdentifier=//p' | head -1)"
        if ! echo "$fw_info" | grep -q "Signature="; then
            bad "$fw is NOT code-signed"
        elif [ -n "$app_team" ] && [ "$fw_team" != "$app_team" ]; then
            bad "$fw team ($fw_team) differs from the app team ($app_team)"
        else
            ok "$(basename "$fw") signed (team: ${fw_team:-adhoc})"
        fi
    done
fi

if [ "$fail" -ne 0 ]; then
    echo "BUNDLE VERIFICATION FAILED: $APP_DIR"
    exit 1
fi
echo "BUNDLE OK: $APP_DIR"

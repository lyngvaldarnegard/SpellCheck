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

for res in AppIcon.icns MenuBarIconTemplate.png MenuBarIcons/omega-check.png; do
    if [ -e "$APP_DIR/Contents/Resources/$res" ]; then
        ok "resource $res"
    else
        bad "missing resource Contents/Resources/$res"
    fi
done

if [ "$fail" -ne 0 ]; then
    echo "BUNDLE VERIFICATION FAILED: $APP_DIR"
    exit 1
fi
echo "BUNDLE OK: $APP_DIR"

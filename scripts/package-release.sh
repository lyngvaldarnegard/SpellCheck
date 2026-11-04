#!/bin/sh
# Builds SpellCheck.app and packs it as build/SpellCheck-macOS.zip, ready to
# attach to a GitHub Release (requires macOS).
#
#   scripts/package-release.sh
#   SIGNING_IDENTITY="Developer ID Application: …" scripts/package-release.sh
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

"$ROOT/scripts/build-app.sh" release

mkdir -p "$ROOT/build"
rm -f "$ROOT/build/SpellCheck-macOS.zip"
ditto -c -k --keepParent "$ROOT/build/SpellCheck.app" "$ROOT/build/SpellCheck-macOS.zip"

echo "Packaged $ROOT/build/SpellCheck-macOS.zip"

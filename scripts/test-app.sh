#!/bin/sh
# Builds and tests the macOS app (requires macOS + Xcode toolchain).
set -euo pipefail
cd "$(dirname "$0")/../App"
exec swift test "$@"

#!/bin/sh
# Builds the SpellCheck macOS app in release mode (requires macOS + Xcode).
set -euo pipefail
cd "$(dirname "$0")/../App"
exec swift build -c release "$@"

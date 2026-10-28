#!/bin/sh
# Runs the platform-independent Engine test suite.
set -euo pipefail
cd "$(dirname "$0")/../Engine"
exec swift test "$@"

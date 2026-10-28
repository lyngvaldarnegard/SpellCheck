#!/bin/sh
# Runs the platform-independent Core test suite.
set -euo pipefail
cd "$(dirname "$0")/../Core"
exec swift test "$@"

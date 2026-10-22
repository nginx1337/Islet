#!/bin/zsh
# Unit tests, then the app bundle and its launch self-check.
set -euo pipefail
cd "$(dirname "$0")/.."
swift test
scripts/build-app.sh release
build/Islet.app/Contents/MacOS/Islet --self-check

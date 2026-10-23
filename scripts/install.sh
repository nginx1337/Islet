#!/bin/zsh
# Builds Islet and installs it into /Applications, replacing the previous version.
#   scripts/install.sh              build, then install
#   scripts/install.sh --no-build   install the existing build/Islet.app
#
# The old version is moved to the Trash (not deleted), so it can be put back. Settings are kept:
# they belong to the bundle identifier, which does not change.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="/Applications/Islet.app"
SRC="build/Islet.app"
BUNDLE_ID="app.islet.mac"

bundle_id() { /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true; }

if [[ "${1:-}" != "--no-build" ]]; then
  scripts/build-app.sh
fi

[[ -d "$SRC" ]] || { echo "error: $SRC not found; run without --no-build" >&2; exit 1; }
[[ "$(bundle_id "$SRC")" == "$BUNDLE_ID" ]] || { echo "error: $SRC is not Islet" >&2; exit 1; }
codesign --verify --deep --strict "$SRC" || { echo "error: $SRC has a broken signature" >&2; exit 1; }

# Quit the running copy. SIGTERM makes Islet quit normally (it stops the adapter and the audio tap).
if pgrep -x Islet >/dev/null; then
  echo "Quitting the running Islet…"
  killall -TERM Islet || true
  for _ in {1..50}; do pgrep -x Islet >/dev/null || break; sleep 0.1; done
  if pgrep -x Islet >/dev/null; then echo "error: Islet did not quit; quit it from the menu bar and run again" >&2; exit 1; fi
fi

# Replace the old version, but only if what is there really is Islet.
if [[ -e "$DEST" ]]; then
  if [[ "$(bundle_id "$DEST")" != "$BUNDLE_ID" ]]; then
    echo "error: $DEST is not Islet; not touching it" >&2
    exit 1
  fi
  old="$HOME/.Trash/Islet-$(date +%Y%m%d-%H%M%S).app"
  mv "$DEST" "$old"
  echo "Old version moved to the Trash: $old"
fi

ditto "$SRC" "$DEST"
xattr -cr "$DEST"
codesign --verify --deep --strict "$DEST"
echo "Installed $DEST"
open "$DEST"

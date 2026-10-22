#!/bin/zsh
# Builds Islet.app with the command line tools only (no Xcode project needed).
# Usage: scripts/build-app.sh [release|debug]
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG=${1:-release}
swift build -c "$CONFIG"
BIN=$(swift build -c "$CONFIG" --show-bin-path)

scripts/build-adapter.sh build/adapter

if [[ ! -f build/AppIcon.icns || scripts/make-icon.swift -nt build/AppIcon.icns ]]; then
  mkdir -p build/icon
  swiftc -O scripts/make-icon.swift -o build/icon/make-icon
  build/icon/make-icon build/icon
  iconutil -c icns build/icon/AppIcon.iconset -o build/AppIcon.icns
fi

APP=build/Islet.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks" "$APP/Contents/Helpers"
cp "$BIN/Islet" "$APP/Contents/MacOS/Islet"
cp Resources/Info.plist "$APP/Contents/Info.plist"
cp build/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp -R Resources/en.lproj Resources/ru.lproj "$APP/Contents/Resources/"
# The adapter: script and framework for /usr/bin/perl, plus the test client for the health check.
cp Vendor/mediaremote-adapter/bin/mediaremote-adapter.pl "$APP/Contents/Resources/"
cp -R build/adapter/MediaRemoteAdapter.framework "$APP/Contents/Frameworks/"
cp build/adapter/MediaRemoteAdapterTestClient "$APP/Contents/Helpers/"
mkdir -p "$APP/Contents/Resources/Licenses"
cp LICENSE "$APP/Contents/Resources/Licenses/Islet-LICENSE.txt"
cp Vendor/mediaremote-adapter/LICENSE "$APP/Contents/Resources/Licenses/mediaremote-adapter-LICENSE.txt"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ "$CONFIG" == "release" ]]; then
  # Drop debug symbols and their source paths (they contain the builder's home folder).
  strip -S -x "$APP/Contents/MacOS/Islet"
fi

# Ad-hoc signatures with the hardened runtime, inside out. Replace "-" with a Developer ID to distribute.
codesign --force --sign - "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign --force --sign - --options runtime "$APP/Contents/Helpers/MediaRemoteAdapterTestClient"
codesign --force --sign - --options runtime --entitlements Resources/Islet.entitlements "$APP"
echo "Built $APP"

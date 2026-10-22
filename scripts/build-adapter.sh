#!/bin/zsh
# Compiles the vendored mediaremote-adapter into MediaRemoteAdapter.framework and the test client.
# Plain clang, no CMake. Usage: scripts/build-adapter.sh <output-dir>
set -euo pipefail
cd "$(dirname "$0")/.."

OUT=${1:-build/adapter}
SRC=Vendor/mediaremote-adapter
FW="$OUT/MediaRemoteAdapter.framework"
BIN="$FW/Versions/A/MediaRemoteAdapter"
CLIENT="$OUT/MediaRemoteAdapterTestClient"
MIN=14.0

# Rebuild only when a source file is newer than the output.
if [[ -f "$BIN" && -f "$CLIENT" && -z "$(find "$SRC" -newer "$BIN" -type f -print -quit)" ]]; then
  echo "Adapter is up to date"
  exit 0
fi

rm -rf "$FW" "$CLIENT"
mkdir -p "$FW/Versions/A/Resources"
clang -dynamiclib -fobjc-arc -fvisibility=default -O2 \
  -arch arm64 -arch x86_64 -mmacosx-version-min=$MIN \
  -I"$SRC/include" -I"$SRC/src" \
  "$SRC"/src/adapter/*.m "$SRC/src/private/MediaRemote.m" "$SRC"/src/utility/*.m \
  -framework Foundation -framework AppKit -framework UniformTypeIdentifiers \
  -install_name @rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter \
  -o "$BIN"
ln -sfh A "$FW/Versions/Current"
ln -sfh Versions/Current/MediaRemoteAdapter "$FW/MediaRemoteAdapter"
ln -sfh Versions/Current/Resources "$FW/Resources"
cat > "$FW/Versions/A/Resources/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>MediaRemoteAdapter</string>
	<key>CFBundleIdentifier</key>
	<string>com.vandenbe.MediaRemoteAdapter</string>
	<key>CFBundleName</key>
	<string>MediaRemoteAdapter</string>
	<key>CFBundlePackageType</key>
	<string>FMWK</string>
	<key>CFBundleShortVersionString</key>
	<string>0.1</string>
	<key>CFBundleVersion</key>
	<string>0.1.0</string>
</dict>
</plist>
PLIST

clang -fobjc-arc -O2 -Wno-gnu-folding-constant -arch arm64 -arch x86_64 -mmacosx-version-min=$MIN \
  -I"$SRC/src/test" "$SRC/src/test/main.m" "$SRC/src/test/NowPlayingTest.m" \
  -framework Foundation -framework MediaPlayer -o "$CLIENT"
echo "Built $FW and $CLIENT"

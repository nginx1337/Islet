#!/usr/bin/env bash
# Static security audit of the sources. Fails when anything new reaches for the network, starts
# another program, loads code at run time or asks for a permission that SECURITY.md does not list.
# Runs in CI and by hand: scripts/audit.sh
set -euo pipefail
cd "$(dirname "$0")/.."

failed=0
fail() { echo "audit: $*" >&2; failed=1; }

# Lists the files under Sources that match a pattern, one per line.
matches() { grep -rlE "$1" Sources --include='*.swift' 2>/dev/null | sort || true; }

# Fails unless every file matching the pattern is in the allowed list (space separated).
only_in() {
    local pattern="$1" allowed="$2" what="$3" file
    for file in $(matches "$pattern"); do
        case " $allowed " in
            *" $file "*) ;;
            *) fail "$what in $file (allowed only in: $allowed)" ;;
        esac
    done
}

# Fails when the pattern appears anywhere.
nowhere() {
    local pattern="$1" what="$2" file
    for file in $(matches "$pattern"); do fail "$what in $file"; done
}

# 1. Permissions: exactly the entitlements and usage descriptions SECURITY.md documents.
entitlements=$(grep -o '<key>[^<]*</key>' Resources/Islet.entitlements | sed -e 's/<key>//' -e 's/<\/key>//' | sort | tr '\n' ' ')
[ "$entitlements" = "com.apple.security.automation.apple-events com.apple.security.device.audio-input " ] \
    || fail "entitlements changed: $entitlements"
usage=$(grep -o '<key>NS[A-Za-z]*UsageDescription</key>' Resources/Info.plist | sed -e 's/<key>//' -e 's/<\/key>//' | sort | tr '\n' ' ')
[ "$usage" = "NSAppleEventsUsageDescription NSAudioCaptureUsageDescription " ] \
    || fail "usage descriptions changed: $usage"

# 2. Network: only the Spotify artwork download, over an ephemeral session, https only.
only_in 'URLSession|URLRequest|NWConnection|NWPathMonitor|CFNetwork|WKWebView|import WebKit' \
    'Sources/Islet/App/NowPlayingModel.swift' 'network API'
nowhere 'http://' 'plain http URL'

# App Transport Security stays on: no exceptions for plain http or weak TLS.
if grep -nE 'NSAppTransportSecurity|NSAllowsArbitraryLoads|NSExceptionDomains|NSAllowsLocalNetworking' Resources/Info.plist >/dev/null; then
    fail "Info.plist weakens App Transport Security"
fi
# The scripts build and install from the local source; none of them downloads anything.
for script in scripts/*.sh; do
    [ "$script" = "scripts/audit.sh" ] && continue # its own patterns
    if grep -nE '\b(curl|wget|nc|ftp|scp|rsync|git (clone|pull|fetch))\b' "$script" >/dev/null; then
        fail "$script reaches the network"
    fi
done

# 3. Other programs: the adapter runs through /usr/bin/perl, fallback mode talks to Music and Spotify.
only_in '\bProcess\(\)|NSTask|posix_spawn|execv|popen' \
    'Sources/Islet/Sources/MediaRemoteAdapterSource.swift' 'program launch'
only_in 'NSAppleScript|NSUserAppleScriptTask|ScriptingBridge' \
    'Sources/Islet/Sources/MusicSpotifySource.swift' 'AppleScript'

# 4. Nothing loads code or reaches private symbols at run time (the adapter is loaded by perl, not by the app).
nowhere 'dlopen|dlsym|NSClassFromString|@_silgen_name|NSBundle\(path|Bundle\(path' 'run-time code loading'

# Global event monitors: pointer moves for hover, and the wheel click that brings a hidden island back.
# Nothing may watch the keyboard outside the app (the shortcut uses Carbon RegisterEventHotKey).
if grep -nE 'addGlobalMonitorForEvents\(matching: [^)]*(keyDown|keyUp|flagsChanged|\.any)' -r Sources --include='*.swift' >/dev/null; then
    fail "a global monitor reads the keyboard"
fi
nowhere 'CGEventTapCreate|CGEvent\.tapCreate|IOHIDManager' 'event tap or raw input device access'

# 5. The logic target stays free of UI, network and system frameworks.
for file in Sources/IsletCore/*.swift; do
    for module in $(grep -E '^import ' "$file" | awk '{print $2}'); do
        case "$module" in
            Foundation|CoreGraphics|ImageIO|Accelerate) ;;
            *) fail "$file imports $module" ;;
        esac
    done
done

# 6. No third-party packages.
if grep -nE '\.package\(' Package.swift >/dev/null; then fail "Package.swift has a dependency"; fi

# 7. Live activities never read file names or contents (they read progress only).
if grep -nE '\.fileURL\b|\.userInfo|localizedDescription|localizedAdditionalDescription' Sources/Islet/Activities/TransferMonitor.swift >/dev/null; then
    fail "TransferMonitor reads file information"
fi

if [ "$failed" -ne 0 ]; then
    echo "audit: FAILED" >&2
    exit 1
fi
echo "audit: OK"

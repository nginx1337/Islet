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
    'Sources/Islet/App/NowPlayingModel.swift Sources/Islet/Settings/UpdateChecker.swift' 'network API'
nowhere 'http://' 'plain http URL'
# The update check talks to the GitHub API only, and the update script to GitHub's API and source archives.
hosts=$(grep -oE 'https://[A-Za-z0-9.-]+' Sources/Islet/Settings/UpdateChecker.swift | sort -u | tr '\n' ' ')
[ "$hosts" = "https://api.github.com " ] || fail "UpdateChecker contacts: $hosts"
hosts=$(grep -oE 'https?://[A-Za-z0-9.-]+' scripts/update.sh | sort -u | tr '\n' ' ')
[ "$hosts" = "https://api.github.com https://codeload.github.com " ] || fail "update.sh contacts: $hosts"
if grep -nE '\b(Timer|scheduledTimer|asyncAfter|BGTask)\b' Sources/Islet/Settings/UpdateChecker.swift >/dev/null; then
    fail "UpdateChecker must only run when the button is pressed"
fi

# 3. Other programs: the adapter runs through /usr/bin/perl, fallback mode talks to Music and Spotify.
only_in '\bProcess\(\)|NSTask|posix_spawn|execv|popen' \
    'Sources/Islet/Sources/MediaRemoteAdapterSource.swift' 'program launch'
only_in 'NSAppleScript|NSUserAppleScriptTask|ScriptingBridge' \
    'Sources/Islet/Sources/MusicSpotifySource.swift' 'AppleScript'

# 4. Nothing loads code or reaches private symbols at run time (the adapter is loaded by perl, not by the app).
nowhere 'dlopen|dlsym|NSClassFromString|@_silgen_name|NSBundle\(path|Bundle\(path' 'run-time code loading'

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

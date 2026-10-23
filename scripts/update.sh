#!/bin/zsh
# Updates Islet from its source on GitHub: shows the latest version of main, asks, downloads that exact
# commit, runs the security audit and the tests, builds it on this Mac and installs it in place of the
# current version (scripts/install.sh: the old one goes to the Trash).
#
# Only source code is downloaded, over https, from api.github.com and codeload.github.com; the app is
# always built here. Run it by hand, or press "Update…" in Islet's settings (it opens in Terminal).
set -euo pipefail

REPO="nginx1337/Islet"
BRANCH="main"

fetch() { curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 --max-time 300 "$@"; }

WORK=$(mktemp -d "${TMPDIR:-/tmp}/islet-update.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

echo "Checking the latest version of $REPO ($BRANCH)…"
fetch -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$REPO/commits/$BRANCH" -o "$WORK/commit.json"
SHA=$(plutil -extract sha raw -o - "$WORK/commit.json")
if [[ ! "$SHA" =~ ^[0-9a-f]{40}$ ]]; then
  echo "error: unexpected answer from GitHub" >&2
  exit 1
fi
DATE=$(plutil -extract commit.committer.date raw -o - "$WORK/commit.json" 2>/dev/null || echo "?")
TITLE=$(plutil -extract commit.message raw -o - "$WORK/commit.json" 2>/dev/null | head -1 || true)

echo
echo "Latest version: ${SHA:0:7}  ${DATE%%T*}  $TITLE"
if ! read -q "REPLY?Download, check, build and install it? [y/N] "; then
  echo
  echo "Cancelled, nothing changed."
  exit 0
fi
echo

echo "Downloading the source…"
fetch "https://codeload.github.com/$REPO/tar.gz/$SHA" -o "$WORK/source.tar.gz"
mkdir "$WORK/src"
tar -xzf "$WORK/source.tar.gz" -C "$WORK/src" --strip-components 1
cd "$WORK/src"

echo "Security audit…"
scripts/audit.sh
echo "Tests…"
swift test
echo "Building and installing…"
ISLET_COMMIT="$SHA" scripts/install.sh --build

echo
echo "Islet is up to date (${SHA:0:7}). You can close this window."

#!/bin/bash
# DuskMode installer.
#   curl -fsSL https://raw.githubusercontent.com/neerajsingh869/DuskMode/main/install.sh | bash
#
# Downloads the latest release, puts DuskMode.app in /Applications and opens it.
# DuskMode isn't signed with a paid Apple Developer ID yet. Files downloaded with curl
# aren't quarantined, so macOS opens the app without the "can't be checked" block.
# Read every line before you run it; that's the point of a readable installer.
set -euo pipefail

REPO="neerajsingh869/DuskMode"
URL="https://github.com/$REPO/releases/latest/download/DuskMode.zip"
DEST="${DUSKMODE_INSTALL_DIR:-/Applications}"

fail() { echo "✗ $1" >&2; exit 1; }

[[ "$(uname -s)" == "Darwin" ]] || fail "DuskMode is a Mac app."
[[ "$(uname -m)" == "arm64" ]] || fail "This build needs an Apple Silicon Mac (M1 or later)."
MAJOR="$(sw_vers -productVersion | cut -d. -f1)"
(( MAJOR >= 13 )) || fail "DuskMode needs macOS 13 Ventura or later."

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "==> Downloading DuskMode"
curl -fsSL "$URL" -o "$TMP/DuskMode.zip" || fail "Download failed. Check your connection and try again."
ditto -x -k "$TMP/DuskMode.zip" "$TMP" || fail "The download looks damaged. Try again."
[[ -d "$TMP/DuskMode.app" ]] || fail "The download didn't contain DuskMode.app."

echo "==> Moving it to $DEST"
pkill -x DuskMode 2>/dev/null || true
rm -rf "$DEST/DuskMode.app"
ditto "$TMP/DuskMode.app" "$DEST/DuskMode.app" || fail "Couldn't write to $DEST."

if [[ -z "${DUSKMODE_NO_OPEN:-}" ]]; then
  echo "==> Opening DuskMode"
  open "$DEST/DuskMode.app"
fi
echo "✓ DuskMode is in your menu bar. Sleep well."

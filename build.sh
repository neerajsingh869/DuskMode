#!/bin/bash
# Build DuskMode.app from the Swift package — no Xcode required, just Command Line Tools.
# Usage: ./build.sh [debug|release] [run]
#   debug|release  build config (default: release)
#   run            quit any running copy and relaunch the fresh build when done
set -euo pipefail

CONFIG="${1:-release}"
DO_RUN="${2:-}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/DuskMode.app"
BUNDLE_ID="app.duskmode"

# Always quit any running copy first — a previously-opened build keeps living in the
# menu bar and would otherwise stack up as duplicate moon icons.
pkill -f "DuskMode.app/Contents/MacOS/DuskMode" 2>/dev/null && echo "==> Quit running DuskMode" || true

echo "==> Compiling ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/DuskMode"
if [[ ! -f "$BIN" ]]; then
  echo "Build produced no binary at $BIN" >&2
  exit 1
fi

echo "==> Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/DuskMode"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>DuskMode</string>
    <key>CFBundleDisplayName</key>     <string>DuskMode</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>0.1</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>DuskMode</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <!-- Menu-bar-only app: no Dock icon. -->
    <key>LSUIElement</key>             <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>DuskMode needs Accessibility access to toggle macOS grayscale (Color Filters) on your wind-down schedule.</string>
    <key>NSLocationUsageDescription</key>
    <string>DuskMode uses your approximate location once to compute local sunset and sunrise times for the automatic wind-down schedule. It never leaves your Mac.</string>
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>DuskMode uses your approximate location once to compute local sunset and sunrise times for the automatic wind-down schedule. It never leaves your Mac.</string>
</dict>
</plist>
PLIST

# Ad-hoc codesign so the overlay/Accessibility permissions attach to a stable identity
# during local use. Real Developer ID signing + notarization comes in Phase 5.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "   (ad-hoc codesign skipped — not fatal for local runs)"

echo "==> Done: $APP"

if [[ "$DO_RUN" == "run" || "$DO_RUN" == "open" ]]; then
  echo "==> Launching…"
  open "$APP"
else
  echo "    Run with:  ./build.sh release run    (builds + relaunches)"
  echo "    Or:        open \"$APP\""
fi

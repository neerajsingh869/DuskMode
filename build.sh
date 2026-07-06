#!/bin/bash
# Build NightFlow.app from the Swift package — no Xcode required, just Command Line Tools.
# Usage: ./build.sh [debug|release]   (default: release)
set -euo pipefail

CONFIG="${1:-release}"
ROOT="$(cd "$(dirname "$0")" && pwd)"
APP="$ROOT/NightFlow.app"
BUNDLE_ID="com.nightflow.app"

echo "==> Compiling ($CONFIG)…"
swift build -c "$CONFIG"

BIN="$(swift build -c "$CONFIG" --show-bin-path)/NightFlow"
if [[ ! -f "$BIN" ]]; then
  echo "Build produced no binary at $BIN" >&2
  exit 1
fi

echo "==> Assembling app bundle…"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/NightFlow"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>NightFlow</string>
    <key>CFBundleDisplayName</key>     <string>NightFlow</string>
    <key>CFBundleIdentifier</key>      <string>$BUNDLE_ID</string>
    <key>CFBundleVersion</key>         <string>0.1</string>
    <key>CFBundleShortVersionString</key> <string>0.1</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleExecutable</key>      <string>NightFlow</string>
    <key>LSMinimumSystemVersion</key>  <string>13.0</string>
    <!-- Menu-bar-only app: no Dock icon. -->
    <key>LSUIElement</key>             <true/>
    <key>NSAccessibilityUsageDescription</key>
    <string>NightFlow needs Accessibility access to toggle macOS grayscale (Color Filters) on your wind-down schedule.</string>
</dict>
</plist>
PLIST

# Ad-hoc codesign so the overlay/Accessibility permissions attach to a stable identity
# during local use. Real Developer ID signing + notarization comes in Phase 5.
codesign --force --deep --sign - "$APP" >/dev/null 2>&1 || \
  echo "   (ad-hoc codesign skipped — not fatal for local runs)"

echo "==> Done: $APP"
echo "    Run with:  open \"$APP\"    (or)    \"$APP/Contents/MacOS/NightFlow\""

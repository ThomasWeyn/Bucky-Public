#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"
APP="${BUCKY_APP_PATH:-$HOME/Applications/Bucky.app}"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc -O -swift-version 5 "$ROOT/Sources/main.swift" "$ROOT/Sources/Shortcuts.swift" "$ROOT/Sources/History.swift" "$ROOT/Sources/Workspace.swift" -o "$APP/Contents/MacOS/Bucky" -framework AppKit -framework SwiftUI -framework AVFoundation -framework Carbon
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>nl.quickmouse.spreek</string>
<key>CFBundleName</key><string>Bucky</string>
<key>CFBundleExecutable</key><string>Bucky</string>
<key>CFBundleShortVersionString</key><string>0.2.0</string>
<key>CFBundleVersion</key><string>2</string>
<key>CFBundleIconFile</key><string>Bucky</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSMicrophoneUsageDescription</key><string>Bucky records only when you start dictation, and transcribes locally on this Mac.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Add :BuckyProjectRoot string $ROOT" "$APP/Contents/Info.plist"
cp Assets/Bucky.icns "$APP/Contents/Resources/Bucky.icns"
codesign --force --sign - --identifier nl.quickmouse.spreek "$APP"
printf 'Built %s\n' "$APP"

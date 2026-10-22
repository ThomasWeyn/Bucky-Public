#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
ROOT="$(pwd -P)"
APP="${BUCKY_APP_PATH:-$HOME/Applications/Bucky.app}"
# Ad-hoc signatures bind macOS permissions to this exact app version.
# Engine-only changes do not need a native rebuild. Protect every existing app,
# including targets selected with BUCKY_APP_PATH, before touching its bundle.
if [[ -e "$APP" && "${BUCKY_REPLACE_APP:-0}" != "1" ]]; then
    printf 'Refusing to replace existing app: %s\n' "$APP" >&2
    printf '%s\n' 'A native rebuild/re-sign can require macOS permission renewal.' 'For validation, set BUCKY_APP_PATH to a new temporary .app path.' 'For engine-only updates, use Settings > Speech engine > Restart.' 'Only for a deliberate replacement: BUCKY_REPLACE_APP=1 bash scripts/build.sh' >&2
    exit 2
fi
FLAGS=(-O -swift-version 5)
IDENTIFIER=nl.quickmouse.spreek
if [[ "${BUCKY_UI_TESTING:-0}" == "1" ]]; then
    if [[ -z "${BUCKY_APP_PATH:-}" ]]; then
        printf '%s\n' 'UI previews require an explicit isolated BUCKY_APP_PATH.' >&2
        exit 2
    fi
    FLAGS+=(-D UI_TESTING)
    IDENTIFIER=nl.quickmouse.bucky-ui-test
fi
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
xcrun swiftc "${FLAGS[@]}" "$ROOT/Sources/main.swift" "$ROOT/Sources/Shortcuts.swift" "$ROOT/Sources/History.swift" "$ROOT/Sources/Workspace.swift" "$ROOT/Sources/TextTools.swift" "$ROOT/Sources/Clipboard.swift" -o "$APP/Contents/MacOS/Bucky" -framework AppKit -framework SwiftUI -framework AVFoundation -framework Carbon
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>nl.quickmouse.spreek</string>
<key>CFBundleName</key><string>Bucky</string>
<key>CFBundleExecutable</key><string>Bucky</string>
<key>CFBundleShortVersionString</key><string>0.3.0</string>
<key>CFBundleVersion</key><string>3</string>
<key>CFBundleIconFile</key><string>Bucky</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSUIElement</key><true/>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSMicrophoneUsageDescription</key><string>Bucky records only when you start dictation, and transcribes locally on this Mac.</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
/usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier $IDENTIFIER" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Add :BuckyProjectRoot string $ROOT" "$APP/Contents/Info.plist"
cp Assets/Bucky.icns "$APP/Contents/Resources/Bucky.icns"
codesign --force --sign - --identifier "$IDENTIFIER" "$APP"
printf 'Built %s\n' "$APP"

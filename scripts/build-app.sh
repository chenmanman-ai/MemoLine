#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
swift build -c release --product MemoLine
BIN_DIR="$(swift build -c release --show-bin-path)"
APP="build/MemoLine.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/MemoLine" "$APP/Contents/MacOS/MemoLine"
swift scripts/make-icon.swift build/MemoLine.iconset
iconutil -c icns build/MemoLine.iconset -o "$APP/Contents/Resources/MemoLine.icns"
cp LICENSE "$APP/Contents/Resources/LICENSE.txt"
cp LICENSE-MEMOLINE "$APP/Contents/Resources/LICENSE-MEMOLINE.txt"
cp THIRD_PARTY_NOTICES.md "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp PRIVACY.md "$APP/Contents/Resources/PRIVACY.md"
cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>MemoLine</string>
<key>CFBundleDisplayName</key><string>MemoLine</string>
<key>CFBundleIdentifier</key><string>local.memoline.desktop</string>
<key>CFBundleExecutable</key><string>MemoLine</string>
<key>CFBundleIconFile</key><string>MemoLine</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>1.10</string>
<key>CFBundleVersion</key><string>15</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>LSUIElement</key><false/>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>NSHumanReadableCopyright</key><string>Based on MIT-licensed code © 2026 Alejandro Buján. Independent MemoLine adaptation.</string>
</dict></plist>
PLIST
codesign --force --deep --sign - "$APP"
printf 'Built %s\n' "$PWD/$APP"

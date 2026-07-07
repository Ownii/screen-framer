#!/bin/bash
# Baut das Release-Binary und verpackt es als "Screen Framer.app".
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release

APP="build/Screen Framer.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ScreenFramer "$APP/Contents/MacOS/ScreenFramer"

cat > "$APP/Contents/Info.plist" <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>ScreenFramer</string>
    <key>CFBundleIdentifier</key>
    <string>de.martinfoerster.screen-framer</string>
    <key>CFBundleName</key>
    <string>Screen Framer</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
EOF

# Ad-hoc-Signatur: nötig, damit macOS die Bildschirmaufnahme-Berechtigung
# der App über Rebuilds hinweg zuordnen kann.
codesign --force --sign - "$APP"

echo "Fertig: $APP"

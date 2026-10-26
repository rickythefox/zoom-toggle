#!/bin/sh
# Builds build/ZoomToggle.app: a windowless one-shot app that toggles zoom and quits.
set -eu
cd "$(dirname "$0")"

swift build -c release
app=build/ZoomToggle.app
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/zoom-toggle "$app/Contents/MacOS/ZoomToggle"
cat > "$app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key><string>ZoomToggle</string>
    <key>CFBundleIdentifier</key><string>com.richard.zoom-toggle</string>
    <key>CFBundleName</key><string>ZoomToggle</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>LSMinimumSystemVersion</key><string>13.0</string>
    <key>LSUIElement</key><true/>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"
echo "built $app"

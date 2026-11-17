#!/bin/bash
# Builds Wallflow.app (Release) into ./build. Requires Xcode or the Xcode Command Line Tools (Swift 5.9+).
set -euo pipefail
cd "$(dirname "$0")/.."

swift build -c release --arch arm64 --arch x86_64 2>/dev/null || swift build -c release
BIN="$(swift build -c release --show-bin-path)/Wallflow"

APP="build/Wallflow.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/Wallflow"

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>Wallflow</string>
    <key>CFBundleDisplayName</key><string>Wallflow</string>
    <key>CFBundleIdentifier</key><string>app.wallflow.Wallflow</string>
    <key>CFBundleExecutable</key><string>Wallflow</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0</string>
    <key>CFBundleVersion</key><string>1</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>LSApplicationCategoryType</key><string>public.app-category.utilities</string>
    <key>NSHighResolutionCapable</key><true/>
    <key>NSAppleEventsUsageDescription</key><string>Wallflow asks for your password to install a live wallpaper on the lock screen.</string>
</dict>
</plist>
PLIST

# Ad-hoc signature so macOS will launch it locally.
codesign --force --deep --sign - "$APP"
echo "Built $APP"
echo "Install with:  cp -R \"$APP\" /Applications/"

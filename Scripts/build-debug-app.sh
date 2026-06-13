#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Spectra"
APP_BUNDLE="$ROOT_DIR/.build/$APP_NAME.app"
EXECUTABLE_SOURCE="$ROOT_DIR/.build/arm64-apple-macosx/debug/$APP_NAME"

cd "$ROOT_DIR"
swift build --product "$APP_NAME"

rm -rf "$APP_BUNDLE"
mkdir -p "$APP_BUNDLE/Contents/MacOS" "$APP_BUNDLE/Contents/Resources"
cp "$EXECUTABLE_SOURCE" "$APP_BUNDLE/Contents/MacOS/$APP_NAME"

cat > "$APP_BUNDLE/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>Spectra</string>
    <key>CFBundleExecutable</key>
    <string>Spectra</string>
    <key>CFBundleIdentifier</key>
    <string>com.christianzbox.spectra.debug</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Spectra</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.music</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSMicrophoneUsageDescription</key>
    <string>Spectra does not need microphone input for system audio visualization. This string is present only if future user-selected device capture is enabled.</string>
    <key>NSScreenCaptureUsageDescription</key>
    <string>Spectra uses Screen and System Audio Recording permission to analyze live system audio locally for visualizations. Audio is not uploaded, recorded, or saved by default.</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "$APP_BUNDLE"

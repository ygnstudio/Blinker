#!/bin/zsh
# Packages a built Blinker binary into a signed Blinker.app bundle.
# Usage: package-app.sh <binary-path> <version> [build-number] [output-app]
#
# Single source of truth for Info.plist generation; used by both the local
# build-app.sh workflow and the GitHub Actions release workflow.

set -euo pipefail

BINARY_PATH="${1:?usage: package-app.sh <binary-path> <version> [build-number] [output-app]}"
APP_VERSION="${2:?missing version}"
BUNDLE_VERSION="${3:-1}"
APP_DIR="${4:-Blinker.app}"
BUNDLE_ID="com.ygnstudio.Blinker"

[[ -x "$BINARY_PATH" ]] || { echo "error: binary not found at $BINARY_PATH" >&2; exit 1; }

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/Blinker"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>Blinker</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>Blinker</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>$APP_VERSION</string>
    <key>CFBundleVersion</key>
    <string>$BUNDLE_VERSION</string>
    <key>LSMinimumSystemVersion</key>
    <string>15.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

codesign --force --sign - "$APP_DIR" 2>/dev/null || true

echo "packaged: $APP_DIR ($APP_VERSION build $BUNDLE_VERSION)"

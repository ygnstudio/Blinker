#!/bin/zsh
# Builds the Blinker.app bundle from the Swift package.
# Usage: ./Scripts/build-app.sh [release]

set -euo pipefail

CONFIGURATION="${1:-release}"
APP_NAME="Blinker"
BUNDLE_ID="com.ygnstudio.Blinker"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BUILD_DIR="$ROOT_DIR/.build/$CONFIGURATION"
APP_DIR="$ROOT_DIR/$APP_NAME.app"

cd "$ROOT_DIR"
arch -arm64 swift build -c "$CONFIGURATION"

BINARY="$BUILD_DIR/$APP_NAME"
[[ -x "$BINARY" ]] || { echo "error: built binary not found at $BINARY" >&2; exit 1; }

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"
mkdir -p "$APP_DIR/Contents/Resources"

cp "$BINARY" "$APP_DIR/Contents/MacOS/$APP_NAME"

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>
    <string>$APP_NAME</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>$APP_NAME</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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

echo "built: $APP_DIR"
echo "run:   open $APP_DIR"

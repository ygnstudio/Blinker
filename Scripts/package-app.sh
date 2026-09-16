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
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_PATH="$REPO_ROOT/Assets/Blinker.icns"

[[ -x "$BINARY_PATH" ]] || { echo "error: binary not found at $BINARY_PATH" >&2; exit 1; }

rm -rf "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS"

cp "$BINARY_PATH" "$APP_DIR/Contents/MacOS/Blinker"

# Stamp the real build SDK into LC_BUILD_VERSION. SwiftPM's link step does
# not record the SDK version (the field falls back to the deployment
# target, e.g. sdk 15.0), and macOS 26+ only applies the Liquid Glass
# design to binaries declaring an SDK of 26 or later. Rewrite it here,
# before the bundle is signed below.
BUILD_SDK="$(xcrun --show-sdk-version 2>/dev/null || echo "")"
if [[ -n "$BUILD_SDK" ]] && xcrun vtool \
    -set-build-version macos 15.0 "$BUILD_SDK" -replace \
    -output "$APP_DIR/Contents/MacOS/Blinker" "$APP_DIR/Contents/MacOS/Blinker" 2>/dev/null; then
  echo "stamped build sdk: $BUILD_SDK"
else
  echo "warning: could not stamp the build sdk (vtool); the app may keep the pre-26 appearance" >&2
fi

# Bundle icon (rendered by Scripts/render-app-icon.py when present).
ICON_PLIST_ENTRY=""
if [[ -f "$ICON_PATH" ]]; then
  mkdir -p "$APP_DIR/Contents/Resources"
  cp "$ICON_PATH" "$APP_DIR/Contents/Resources/Blinker.icns"
  ICON_PLIST_ENTRY=$'    <key>CFBundleIconFile</key>\n    <string>Blinker</string>'
else
  echo "warning: $ICON_PATH not found — bundling without an app icon" >&2
fi

# Localizations. SwiftPM compiles each target's String Catalog into a
# resource bundle next to the binary:
#   Blinker_BlinkerApp.bundle  — the app target's strings, which resolve via
#     Bundle.main: unpack its .lproj tables straight into Contents/Resources.
#   Blinker_BlinkerCore.bundle — Core resolves via Bundle.module, whose
#     search path is Bundle.main.resourceURL: copy the bundle whole.
BUILD_DIR="$(cd "$(dirname "$BINARY_PATH")" && pwd)"
APP_RESOURCE_BUNDLE="$BUILD_DIR/Blinker_BlinkerApp.bundle"
CORE_RESOURCE_BUNDLE="$BUILD_DIR/Blinker_BlinkerCore.bundle"
mkdir -p "$APP_DIR/Contents/Resources"
if [[ -d "$APP_RESOURCE_BUNDLE/Contents/Resources" ]]; then
  for LPROJ in "$APP_RESOURCE_BUNDLE"/Contents/Resources/*.lproj; do
    [[ -d "$LPROJ" ]] && cp -R "$LPROJ" "$APP_DIR/Contents/Resources/"
  done
else
  echo "warning: $APP_RESOURCE_BUNDLE missing — the app falls back to source-language keys" >&2
fi
if [[ -d "$CORE_RESOURCE_BUNDLE" ]]; then
  cp -R "$CORE_RESOURCE_BUNDLE" "$APP_DIR/Contents/Resources/"
else
  echo "warning: $CORE_RESOURCE_BUNDLE missing — the hover HUD falls back to source-language keys" >&2
fi

cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>zh-Hans</string>
    <key>CFBundleExecutable</key>
    <string>Blinker</string>
    <key>CFBundleIdentifier</key>
    <string>$BUNDLE_ID</string>
    <key>CFBundleName</key>
    <string>Blinker</string>
${ICON_PLIST_ENTRY}
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

# Sign with the local BlinkerDev development certificate when available;
# fall back to ad-hoc signing (e.g. on CI runners without the certificate).
# A stable certificate keeps TCC permission grants (Accessibility) valid
# across rebuilds, unlike ad-hoc signing.
SIGN_IDENTITY="${CODESIGN_IDENTITY:-BlinkerDev}"
if ! security find-identity -v -p codesigning 2>/dev/null | grep -q "\"$SIGN_IDENTITY\""; then
  SIGN_IDENTITY="-"
fi
codesign --force --sign "$SIGN_IDENTITY" "$APP_DIR" 2>/dev/null \
  || codesign --force --sign - "$APP_DIR" 2>/dev/null \
  || true

echo "packaged: $APP_DIR ($APP_VERSION build $BUNDLE_VERSION, signed: $SIGN_IDENTITY)"

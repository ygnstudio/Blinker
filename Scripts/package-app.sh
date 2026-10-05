#!/bin/zsh
# Packages a built Blinker binary into a signed Blinker.app bundle.
# Usage: package-app.sh <binary-path> <version> [build-number] [output-app]
# Requires an explicit, non-empty BLINKER_BUNDLE_ID.
#
# Single source of truth for Info.plist generation; used by both the local
# build-app.sh workflow and the GitHub Actions release workflow.

set -euo pipefail

BINARY_PATH="${1:?usage: package-app.sh <binary-path> <version> [build-number] [output-app]}"
APP_VERSION="${2:?missing version}"
BUNDLE_VERSION="${3:-1}"
APP_DIR="${4:-Blinker.app}"
# Callers choose the installation identity explicitly. Separate development
# and release IDs isolate app registration, preferences and permission grants.
BUNDLE_ID="${BLINKER_BUNDLE_ID:?BLINKER_BUNDLE_ID must be explicitly set and non-empty}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
ICON_PATH="$REPO_ROOT/Assets/Blinker.icns"

[[ -x "$BINARY_PATH" ]] || { echo "error: binary not found at $BINARY_PATH" >&2; exit 1; }

# Never remove an arbitrary output path or replace a different application's bundle.
OUTPUT_APP="${APP_DIR:a}"
[[ "$OUTPUT_APP" == *.app && ! -L "$OUTPUT_APP" ]] || {
  echo "error: output must be a non-symlink .app path" >&2; exit 1;
}
if [[ -e "$OUTPUT_APP" ]]; then
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$OUTPUT_APP/Contents/Info.plist" 2>/dev/null || true)"
  [[ "$EXISTING_ID" == "$BUNDLE_ID" ]] || {
    echo "error: refusing to replace a bundle with a different or missing identifier" >&2; exit 1;
  }
fi
mkdir -p "$(dirname "$OUTPUT_APP")"
LOCK_DIR="$OUTPUT_APP.packaging-lock"
if ! mkdir "$LOCK_DIR" 2>/dev/null; then
  echo "error: another build owns $LOCK_DIR; remove it only if that build has stopped" >&2
  exit 1
fi
STAGING=""
trap 'rmdir "$LOCK_DIR"' EXIT
STAGING="$(mktemp -d "$(dirname "$OUTPUT_APP")/.Blinker-package.XXXXXX")"
INSTALL_SUCCEEDED=false
cleanup() {
  # If installation/rollback was interrupted, keep the old bundle recoverable.
  if [[ -e "$STAGING/previous.app" && "$INSTALL_SUCCEEDED" != true ]]; then
    echo "warning: previous app preserved at $STAGING/previous.app" >&2
  else
    rm -rf "$STAGING"
  fi
  rmdir "$LOCK_DIR"
}
trap cleanup EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
APP_DIR="$STAGING/Blinker.app"
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
# The distributed application carries its license and project attribution offline.
cp "$REPO_ROOT/LICENSE" "$REPO_ROOT/NOTICE" "$APP_DIR/Contents/Resources/"
mkdir -p "$APP_DIR/Contents/Resources/ThirdParty/StatusTrio"
for NOTICE_FILE in LICENSE NOTICE README.md; do
  cp "$REPO_ROOT/ThirdParty/StatusTrio/$NOTICE_FILE" "$APP_DIR/Contents/Resources/ThirdParty/StatusTrio/"
done
mkdir -p "$APP_DIR/Contents/Resources/ThirdParty/MacbookDuoEffect"
for NOTICE_FILE in LICENSE README.md; do
  cp "$REPO_ROOT/ThirdParty/MacbookDuoEffect/$NOTICE_FILE" "$APP_DIR/Contents/Resources/ThirdParty/MacbookDuoEffect/"
done
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
    <key>NSLocationWhenInUseUsageDescription</key>
    <string>定位权限仅用于解除系统对 Wi-Fi 名称的隐藏，以便在状态面板显示当前网络名称。Blinker 不会读取或记录您的位置。Location access is only used to un-redact the Wi-Fi network name for the status panel. Blinker never reads or records your location.</string>
    <key>NSBluetoothAlwaysUsageDescription</key>
    <string>开启「扫描附近设备电量」后，蓝牙权限用于读取附近设备的公开电量信息。Blinker 不会配对或上传任何数据。Bluetooth access is only used to read the public battery level of nearby devices when Nearby Device Battery is enabled. Blinker never pairs or uploads anything.</string>
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
if [[ "$SIGN_IDENTITY" != "-" ]] && ! security find-identity -v -p codesigning 2>/dev/null | grep -Fq "\"$SIGN_IDENTITY\""; then
  if [[ -n "${CODESIGN_IDENTITY:-}" ]]; then
    echo "error: requested signing identity is unavailable" >&2
    exit 1
  fi
  SIGN_IDENTITY="-"
fi
# Once an identity is chosen, a signing failure is fatal: silently changing it
# would invalidate the existing permission grants while reporting success.
plutil -lint "$APP_DIR/Contents/Info.plist" >/dev/null
codesign --force --sign "$SIGN_IDENTITY" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

# Replace only after verification; recheck the target after the potentially long build.
EXPECTED_BINARY="$(shasum -a 256 < "$APP_DIR/Contents/MacOS/Blinker")"
if [[ -e "$OUTPUT_APP" || -L "$OUTPUT_APP" ]]; then
  EXISTING_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$OUTPUT_APP/Contents/Info.plist" 2>/dev/null || true)"
  [[ ! -L "$OUTPUT_APP" && "$EXISTING_ID" == "$BUNDLE_ID" ]] || {
    echo "error: output changed while packaging; installed app was left untouched" >&2; exit 1;
  }
  mv "$OUTPUT_APP" "$STAGING/previous.app"
fi
if ! mv "$APP_DIR" "$OUTPUT_APP"; then
  if [[ -e "$STAGING/previous.app" ]]; then mv "$STAGING/previous.app" "$OUTPUT_APP"; fi
  echo "error: could not install $OUTPUT_APP" >&2
  exit 1
fi
# mv can nest a directory if another writer recreates the destination in the gap.
# Do not report success or delete the backup in that case.
if [[ -e "$OUTPUT_APP/Blinker.app" || ! -f "$OUTPUT_APP/Contents/MacOS/Blinker" ]] \
    || [[ "$(shasum -a 256 < "$OUTPUT_APP/Contents/MacOS/Blinker")" != "$EXPECTED_BINARY" ]]; then
  echo "error: output changed during installation; previous app remains in $STAGING" >&2
  exit 1
fi
INSTALL_SUCCEEDED=true
echo "packaged: $OUTPUT_APP ($APP_VERSION build $BUNDLE_VERSION, signed: $SIGN_IDENTITY)"

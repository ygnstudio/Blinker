#!/bin/zsh
# Builds the Blinker.app bundle from the Swift package (local development).
# Usage: ./Scripts/build-app.sh [release]

set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
APP_OUTPUT="${BLINKER_APP_PATH:-$HOME/Applications/Blinker.app}"

cd "$ROOT_DIR"
# Local development has a separate installation identity, preferences and
# permission grants from releases. A new ID starts with fresh defaults,
# TCC grants and login-item registration.
export BLINKER_BUNDLE_ID="com.ygnstudio.Blinker.dev"
arch -arm64 swift build -c "$CONFIGURATION"

BINARY="$(arch -arm64 swift build -c "$CONFIGURATION" --show-bin-path)/Blinker"
VERSION="$(git -C "$ROOT_DIR" describe --tags --always 2>/dev/null || echo 0.0.0)"
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"

mkdir -p "$(dirname "$APP_OUTPUT")"
"$ROOT_DIR/Scripts/package-app.sh" "$BINARY" "$VERSION" "$BUILD_NUMBER" "$APP_OUTPUT"

echo "run:   open \"$APP_OUTPUT\""

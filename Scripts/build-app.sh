#!/bin/zsh
# Builds the Blinker.app bundle from the Swift package (local development).
# Usage: ./Scripts/build-app.sh [release]

set -euo pipefail

CONFIGURATION="${1:-release}"
ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

cd "$ROOT_DIR"
# Local dev builds carry a distinct bundle ID so they never collide with an
# installed release in LaunchServices (same-ID apps at multiple paths broke
# the menu bar icon; see package-app.sh). Note: fresh ID = fresh defaults,
# TCC grants and login-item registration on first launch.
export BLINKER_BUNDLE_ID="com.ygnstudio.Blinker.dev"
arch -arm64 swift build -c "$CONFIGURATION"

BINARY="$ROOT_DIR/.build/$CONFIGURATION/Blinker"
VERSION="$(git -C "$ROOT_DIR" describe --tags --always 2>/dev/null || echo 0.0.0)"
BUILD_NUMBER="$(git -C "$ROOT_DIR" rev-list --count HEAD 2>/dev/null || echo 1)"

"$ROOT_DIR/Scripts/package-app.sh" "$BINARY" "$VERSION" "$BUILD_NUMBER" "$ROOT_DIR/Blinker.app"

echo "run:   open $ROOT_DIR/Blinker.app"

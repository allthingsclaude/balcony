#!/usr/bin/env bash
#
# Quick dev cycle: kill running app, regenerate project, build debug, launch.
#
# Usage: ./Scripts/dev.sh
#
set -euo pipefail

APP_NAME="Balcony"
SCHEME="BalconyMac"

echo "==> Killing running $APP_NAME..."
killall "$APP_NAME" 2>/dev/null || true

echo "==> Regenerating Xcode project..."
xcodegen generate

echo "==> Building $SCHEME (Debug)..."
xcodebuild \
    -project Balcony.xcodeproj \
    -scheme "$SCHEME" \
    -configuration Debug \
    build \
    2>&1 | tail -5

# Find and open the built app
BUILD_DIR=$(xcodebuild -project Balcony.xcodeproj -scheme "$SCHEME" -configuration Debug -showBuildSettings 2>/dev/null | grep "BUILT_PRODUCTS_DIR" | head -1 | awk '{print $3}')
APP_PATH="$BUILD_DIR/$APP_NAME.app"

if [[ -d "$APP_PATH" ]]; then
    echo "==> Launching $APP_PATH"
    open "$APP_PATH"
else
    echo "==> Build succeeded but app not found at expected path"
    echo "    Try: open \$(find ~/Library/Developer/Xcode/DerivedData -name '$APP_NAME.app' -path '*/Debug/*' | head -1)"
fi

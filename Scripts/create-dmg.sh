#!/usr/bin/env bash
#
# Create a DMG from a macOS .app bundle.
# Includes an Applications symlink for drag-to-install.
#
# Usage: ./Scripts/create-dmg.sh <path-to-.app> [output-dmg-path]
#
set -euo pipefail

APP_PATH="${1:?Usage: create-dmg.sh <path-to-.app> [output.dmg]}"
APP_NAME="$(basename "$APP_PATH" .app)"

# Default output path
DMG_PATH="${2:-$(dirname "$APP_PATH")/${APP_NAME}.dmg}"

if [[ ! -d "$APP_PATH" ]]; then
    echo "Error: $APP_PATH not found or not a directory"
    exit 1
fi

echo "==> Creating DMG: $DMG_PATH"

# Clean up any existing DMG
rm -f "$DMG_PATH"

# Create a temporary directory for DMG contents
STAGING_DIR="$(mktemp -d)"
trap 'rm -rf "$STAGING_DIR"' EXIT

# Copy app and create Applications symlink
cp -R "$APP_PATH" "$STAGING_DIR/$APP_NAME.app"
ln -s /Applications "$STAGING_DIR/Applications"

# Create DMG
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

echo "==> Created: $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"

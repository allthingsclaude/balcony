#!/usr/bin/env bash
#
# Create a styled DMG from a macOS .app bundle.
# Features: custom background, icon layout, drag-to-install.
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

# Generate background image
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BG_DIR="$STAGING_DIR/.background"
mkdir -p "$BG_DIR"

# Create a 600x400 background with gradient and install arrow using Python
python3 -c "
import struct, zlib

WIDTH, HEIGHT = 600, 400

def create_png(width, height, pixels):
    def chunk(chunk_type, data):
        c = chunk_type + data
        return struct.pack('>I', len(data)) + c + struct.pack('>I', zlib.crc32(c) & 0xffffffff)

    header = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack('>IIBBBBB', width, height, 8, 2, 0, 0, 0))

    raw = b''
    for y in range(height):
        raw += b'\x00'  # filter byte
        for x in range(width):
            raw += bytes(pixels(x, y))
    idat = chunk(b'IDAT', zlib.compress(raw))
    iend = chunk(b'IEND', b'')
    return header + ihdr + idat + iend

def lerp(a, b, t):
    return int(a + (b - a) * t)

def pixel(x, y):
    t = y / HEIGHT
    # Warm gradient: light cream to soft terracotta (matching the app icon)
    r = lerp(250, 205, t)
    g = lerp(245, 155, t)
    b = lerp(240, 130, t)

    # Draw a subtle arrow in the center pointing right
    cx, cy = WIDTH // 2, HEIGHT // 2
    ax = x - cx
    ay = y - cy

    # Arrow body (horizontal line)
    if -40 <= ax <= 30 and -3 <= ay <= 3:
        return (80, 80, 80)
    # Arrow head (triangle)
    if 20 <= ax <= 50 and abs(ay) <= (50 - ax):
        return (80, 80, 80)

    return (r, g, b)

data = create_png(WIDTH, HEIGHT, pixel)
open('$BG_DIR/background.png', 'wb').write(data)
"

# Create a read-write DMG first (needed for AppleScript styling)
# Place RW DMG outside staging dir so hdiutil -srcfolder doesn't include it
RW_DMG="$(mktemp -d)/rw.dmg"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$STAGING_DIR" \
    -ov \
    -format UDRW \
    "$RW_DMG"

# Mount the read-write DMG
MOUNT_DIR=$(hdiutil attach "$RW_DMG" -readwrite -noverify | grep "/Volumes/" | sed 's/.*\/Volumes/\/Volumes/')

# Style the DMG window with AppleScript
osascript <<APPLESCRIPT
tell application "Finder"
    tell disk "$APP_NAME"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {100, 100, 700, 500}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set background picture of theViewOptions to file ".background:background.png"
        set position of item "$APP_NAME.app" of container window to {150, 200}
        set position of item "Applications" of container window to {450, 200}
        close
        open
        update without registering applications
        delay 1
        close
    end tell
end tell
APPLESCRIPT

# Ensure Finder writes .DS_Store
sync

# Unmount
hdiutil detach "$MOUNT_DIR" -quiet

# Convert to compressed read-only DMG
hdiutil convert "$RW_DMG" \
    -format UDZO \
    -imagekey zlib-level=9 \
    -o "$DMG_PATH"

echo "==> Created: $DMG_PATH"
echo "    Size: $(du -h "$DMG_PATH" | cut -f1)"

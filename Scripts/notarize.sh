#!/usr/bin/env bash
#
# Notarize a macOS .app or .dmg with Apple's notary service.
#
# Environment variables (required):
#   APPLE_ID        - Apple Developer account email
#   APPLE_APP_PASSWORD - App-specific password (from appleid.apple.com)
#   APPLE_TEAM_ID   - 10-character team ID
#
# Usage: ./Scripts/notarize.sh <path-to-app-or-dmg>
#
set -euo pipefail

TARGET="${1:?Usage: notarize.sh <path-to-.app-or-.dmg>}"

# Validate required env vars
: "${APPLE_ID:?Set APPLE_ID to your Apple Developer email}"
: "${APPLE_APP_PASSWORD:?Set APPLE_APP_PASSWORD to your app-specific password}"
: "${APPLE_TEAM_ID:?Set APPLE_TEAM_ID to your 10-char team ID}"

if [[ ! -e "$TARGET" ]]; then
    echo "Error: $TARGET not found"
    exit 1
fi

EXT="${TARGET##*.}"

# If target is a .app, zip it for submission
if [[ "$EXT" == "app" ]]; then
    echo "==> Zipping .app for notarization..."
    ZIP_PATH="${TARGET%.app}.zip"
    ditto -c -k --keepParent "$TARGET" "$ZIP_PATH"
    SUBMIT_PATH="$ZIP_PATH"
else
    SUBMIT_PATH="$TARGET"
fi

echo "==> Submitting for notarization: $SUBMIT_PATH"

xcrun notarytool submit "$SUBMIT_PATH" \
    --apple-id "$APPLE_ID" \
    --password "$APPLE_APP_PASSWORD" \
    --team-id "$APPLE_TEAM_ID" \
    --wait

# Clean up temp zip
if [[ "$EXT" == "app" && -f "${ZIP_PATH:-}" ]]; then
    rm -f "$ZIP_PATH"
fi

echo "==> Stapling notarization ticket..."
xcrun stapler staple "$TARGET"

echo "==> Notarization complete: $TARGET"

#!/usr/bin/env bash
# Sign Burnrate.app and embedded Sparkle helpers.
# Sparkle requires nested components to be signed individually — not with --deep.
set -euo pipefail

APP_DIR="${1:?Usage: sign-app.sh path/to/Burnrate.app [codesign identity]}"
IDENTITY="${2:?Usage: sign-app.sh path/to/Burnrate.app \"Developer ID Application: …\"}"

SPARKLE="$APP_DIR/Contents/Frameworks/Sparkle.framework"
VERSIONS_B="$SPARKLE/Versions/B"
MACOS_BIN="$APP_DIR/Contents/MacOS/Tokens"

sign() {
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$@"
}

if [[ -d "$VERSIONS_B/XPCServices/Installer.xpc" ]]; then
  sign "$VERSIONS_B/XPCServices/Installer.xpc"
fi
if [[ -d "$VERSIONS_B/XPCServices/Downloader.xpc" ]]; then
  sign --preserve-metadata=entitlements "$VERSIONS_B/XPCServices/Downloader.xpc"
fi
if [[ -x "$VERSIONS_B/Autoupdate" ]]; then
  sign "$VERSIONS_B/Autoupdate"
fi
if [[ -d "$VERSIONS_B/Updater.app" ]]; then
  sign "$VERSIONS_B/Updater.app"
fi
if [[ -d "$SPARKLE" ]]; then
  sign "$SPARKLE"
fi

sign "$MACOS_BIN"
sign "$APP_DIR"

echo "Signed $APP_DIR with: $IDENTITY"

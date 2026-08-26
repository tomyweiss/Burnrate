#!/usr/bin/env bash
# Notarize and staple a signed .app before packaging for Sparkle.
set -euo pipefail

APP_DIR="${1:?Usage: notarize-app.sh path/to/Burnrate.app}"
SUBMIT_ZIP="${2:?Usage: notarize-app.sh path/to/Burnrate.app /tmp/Burnrate-notarize.zip}"

KEY_ID="${ASC_KEY_ID:?Set ASC_KEY_ID}"
ISSUER_ID="${ASC_ISSUER_ID:?Set ASC_ISSUER_ID}"
KEY_PATH="${ASC_KEY_PATH:-$HOME/.appstoreconnect/private_keys/AuthKey_${KEY_ID}.p8}"

if [[ ! -f "$KEY_PATH" ]]; then
  echo "Missing App Store Connect API key at $KEY_PATH" >&2
  exit 1
fi

rm -f "$SUBMIT_ZIP"
ditto -c -k --keepParent "$APP_DIR" "$SUBMIT_ZIP"

echo "Submitting $APP_DIR for notarization..."
xcrun notarytool submit "$SUBMIT_ZIP" \
  --key "$KEY_PATH" \
  --key-id "$KEY_ID" \
  --issuer "$ISSUER_ID" \
  --wait

echo "Stapling notarization ticket to $APP_DIR..."
xcrun stapler staple "$APP_DIR"
spctl -a -vv "$APP_DIR" 2>&1 | head -3

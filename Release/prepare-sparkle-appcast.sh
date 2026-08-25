#!/usr/bin/env bash
# After packaging Burnrate-x.y.z.zip, regenerate appcast.xml with Sparkle.
# Requires Tom's Sparkle private key in Keychain (generate_keys). Optional:
# SPARKLE_ED_KEY_FILE=/path/to/ed.priv
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${VERSION:?Set VERSION=x.y.z}"
VERSION="${VERSION#v}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
ARCHIVE="$DIST_DIR/Burnrate-${VERSION}.zip"
SPARKLE_BIN="$ROOT/.build/artifacts/sparkle/Sparkle/bin"
DOWNLOAD_PREFIX="https://github.com/tomyweiss/Burnrate/releases/download/v${VERSION}/"

if [[ ! -x "$SPARKLE_BIN/generate_appcast" ]]; then
  echo "Sparkle tools missing. Run: swift package resolve" >&2
  exit 1
fi
if [[ ! -f "$ARCHIVE" ]]; then
  echo "Missing $ARCHIVE — package the zip first." >&2
  exit 1
fi

key_args=()
if [[ -n "${SPARKLE_ED_KEY_FILE:-}" ]]; then
  key_args=(--ed-key-file "$SPARKLE_ED_KEY_FILE")
fi

cp "$ROOT/appcast.xml" "$DIST_DIR/appcast.xml"
"$SPARKLE_BIN/generate_appcast" \
  "${key_args[@]}" \
  --download-url-prefix "$DOWNLOAD_PREFIX" \
  --maximum-deltas 0 \
  --maximum-versions 0 \
  -o "$DIST_DIR/appcast.xml" \
  "$DIST_DIR"
cp "$DIST_DIR/appcast.xml" "$ROOT/appcast.xml"

echo "Updated appcast.xml. Upload Burnrate-${VERSION}.zip to GitHub release v${VERSION}, then commit appcast.xml."

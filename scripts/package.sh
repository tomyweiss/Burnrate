#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Burnrate"
EXECUTABLE_NAME="Tokens"
BUILD_DIR="$ROOT/.build"
APP_DIR="$BUILD_DIR/App/${APP_NAME}.app"
CONTENTS="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS/MacOS"
RESOURCES_DIR="$CONTENTS/Resources"
DIST_DIR="$ROOT/dist"

# Version can be overridden: VERSION=0.0.3 bash scripts/package.sh --release
VERSION="${VERSION:-0.0.2}"
BUNDLE_VERSION="${BUNDLE_VERSION:-$(echo "$VERSION" | tr -cd '0-9')}"
if [[ -z "$BUNDLE_VERSION" ]]; then
  BUNDLE_VERSION=2
fi

INSTALL=0
OPEN=0
RELEASE=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --open) OPEN=1 ;;
    --release) RELEASE=1 ;;
  esac
done

echo "Building ${APP_NAME} ${VERSION} (release)…"
swift build -c release

BINARY="$BUILD_DIR/release/${EXECUTABLE_NAME}"
if [[ ! -x "$BINARY" ]]; then
  echo "Missing binary at $BINARY" >&2
  exit 1
fi

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"
cp "$BINARY" "$MACOS_DIR/${EXECUTABLE_NAME}"
chmod +x "$MACOS_DIR/${EXECUTABLE_NAME}"

if [[ -f "$ROOT/Resources/AppIcon.icns" ]]; then
  cp "$ROOT/Resources/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi

# Remove old Tokens.app install if present
rm -rf "/Applications/Tokens.app" 2>/dev/null || true

cat > "$CONTENTS/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>Tokens</string>
  <key>CFBundleIdentifier</key>
  <string>com.tomyweiss.burnrate</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>Burnrate</string>
  <key>CFBundleDisplayName</key>
  <string>Burnrate</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>${BUNDLE_VERSION}</string>
  <key>LSMinimumSystemVersion</key>
  <string>26.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSUserNotificationAlertStyle</key>
  <string>alert</string>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP_DIR" >/dev/null 2>&1 || true

echo "Built $APP_DIR"

if [[ "$RELEASE" -eq 1 ]]; then
  mkdir -p "$DIST_DIR"
  ZIP_NAME="${APP_NAME}-${VERSION}.zip"
  ZIP_PATH="$DIST_DIR/$ZIP_NAME"
  SHA_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.sha256"
  SIG_PATH="$DIST_DIR/${APP_NAME}-${VERSION}.zip.minisig"
  rm -f "$ZIP_PATH" "$SHA_PATH" "$SIG_PATH"
  (
    cd "$BUILD_DIR/App"
    /usr/bin/ditto -c -k --sequesterRsrc --keepParent "${APP_NAME}.app" "$ZIP_PATH"
  )
  (
    cd "$DIST_DIR"
    shasum -a 256 "$ZIP_NAME" | awk '{print $1"  '$ZIP_NAME'"}' > "${APP_NAME}-${VERSION}.sha256"
  )

  MINISIGN_SECRET_KEY="${MINISIGN_SECRET_KEY:-$HOME/.config/burnrate/burnrate.key}"
  if ! command -v minisign &>/dev/null; then
    echo "minisign is required for --release (brew install minisign)" >&2
    exit 1
  fi
  if [[ ! -f "$MINISIGN_SECRET_KEY" ]]; then
    echo "Missing minisign secret key at $MINISIGN_SECRET_KEY" >&2
    echo "Set MINISIGN_SECRET_KEY or place the key at ~/.config/burnrate/burnrate.key" >&2
    exit 1
  fi
  # Legacy (-l) unhashed Ed25519 signatures — matches SignatureVerifier in the app.
  # Empty password prompt for keys generated without a passphrase.
  printf '\n' | minisign -Sm "$ZIP_PATH" -s "$MINISIGN_SECRET_KEY" -l
  # minisign writes next to the zip; normalize the expected release asset name.
  if [[ -f "${ZIP_PATH}.minisig" && "${ZIP_PATH}.minisig" != "$SIG_PATH" ]]; then
    mv "${ZIP_PATH}.minisig" "$SIG_PATH"
  fi
  if [[ ! -f "$SIG_PATH" ]]; then
    echo "Expected signature at $SIG_PATH after minisign" >&2
    exit 1
  fi

  echo "Release artifacts:"
  echo "  $ZIP_PATH"
  echo "  $SHA_PATH"
  echo "  $SIG_PATH"
  echo "Upload all three to a GitHub Release tagged v${VERSION} (or ${VERSION})."
fi

if [[ "$INSTALL" -eq 1 ]]; then
  DEST="/Applications/${APP_NAME}.app"
  rm -rf "$DEST"
  cp -R "$APP_DIR" "$DEST"
  xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
  echo "Installed to $DEST"
  APP_DIR="$DEST"
fi

if [[ "$OPEN" -eq 1 ]]; then
  open "$APP_DIR"
fi

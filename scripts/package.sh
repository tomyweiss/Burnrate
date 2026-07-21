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

INSTALL=0
OPEN=0
for arg in "$@"; do
  case "$arg" in
    --install) INSTALL=1 ;;
    --open) OPEN=1 ;;
  esac
done

echo "Building ${APP_NAME} (release)…"
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

cat > "$CONTENTS/Info.plist" <<'PLIST'
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
  <string>1.0.0</string>
  <key>CFBundleVersion</key>
  <string>1</string>
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

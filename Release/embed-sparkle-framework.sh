#!/usr/bin/env bash
# Copy Sparkle.framework into a packaged Burnrate.app (call from local package.sh).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP_DIR="${1:?Usage: embed-sparkle-framework.sh path/to/Burnrate.app}"
MACOS_BIN="$APP_DIR/Contents/MacOS/Tokens"
FRAMEWORK_SRC="$ROOT/.build/artifacts/sparkle/Sparkle/Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework"

if [[ ! -d "$FRAMEWORK_SRC" ]]; then
  echo "Sparkle.framework not found at $FRAMEWORK_SRC" >&2
  echo "Run: swift package resolve && swift build -c release --product Tokens" >&2
  exit 1
fi
if [[ ! -x "$MACOS_BIN" ]]; then
  echo "Missing app executable at $MACOS_BIN" >&2
  exit 1
fi

mkdir -p "$APP_DIR/Contents/Frameworks"
rm -rf "$APP_DIR/Contents/Frameworks/Sparkle.framework"
cp -R "$FRAMEWORK_SRC" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
/usr/bin/install_name_tool -add_rpath "@executable_path/../Frameworks" "$MACOS_BIN" 2>/dev/null || true
# Final codesign happens in package.sh sign_app(); don't ad-hoc sign here.
echo "Embedded Sparkle.framework into $APP_DIR"

#!/usr/bin/env bash
# Watch Swift sources and hot-reinstall Burnrate-dev on change.
# Usage: bash scripts/dev-watch.sh
#        make watch-dev
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Burnrate-dev"
APP_PATH="/Applications/${APP_NAME}.app"
DEBOUNCE_SECONDS="${DEBOUNCE_SECONDS:-0.6}"
POLL_SECONDS="${POLL_SECONDS:-0.4}"

fingerprint() {
  # mtime+path for every watched file — cheap enough to poll.
  local list
  list="$(
    find Sources Resources \( -name '*.swift' -o -name '*.icns' \) -type f 2>/dev/null || true
    [[ -f Package.swift ]] && echo Package.swift
    [[ -f Package.resolved ]] && echo Package.resolved
  )"
  if [[ -z "${list}" ]]; then
    echo "none"
    return 0
  fi
  # shellcheck disable=SC2086
  echo "$list" | while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    stat -f '%m %N' "$path" 2>/dev/null || true
  done | sort | shasum | awk '{print $1}'
}

quit_app() {
  if pgrep -f "${APP_NAME}.app/Contents/MacOS" >/dev/null 2>&1; then
    osascript -e "tell application \"${APP_NAME}\" to quit" >/dev/null 2>&1 || true
    for _ in $(seq 1 30); do
      pgrep -f "${APP_NAME}.app/Contents/MacOS" >/dev/null 2>&1 || return 0
      sleep 0.1
    done
    pkill -f "${APP_NAME}.app/Contents/MacOS" >/dev/null 2>&1 || true
  fi
}

rebuild() {
  local reason="$1"
  echo ""
  echo "↻ $(date '+%H:%M:%S') ${reason} — rebuilding ${APP_NAME} (debug)…"
  quit_app
  if bash scripts/package.sh --dev --debug --install --open; then
    echo "✓ $(date '+%H:%M:%S') live at ${APP_PATH}"
  else
    echo "✗ $(date '+%H:%M:%S') build failed — fix errors and save again" >&2
  fi
}

echo "Burnrate-dev watch mode"
echo "  watching: Sources/ Resources/ Package.swift"
echo "  install:  ${APP_PATH}"
echo "  stop:     Ctrl-C"
echo ""

rebuild "initial build"
LAST="$(fingerprint)"

while true; do
  sleep "$POLL_SECONDS"
  NOW="$(fingerprint)"
  if [[ "$NOW" == "$LAST" ]]; then
    continue
  fi
  # Debounce bursty editor writes.
  sleep "$DEBOUNCE_SECONDS"
  NOW="$(fingerprint)"
  if [[ "$NOW" == "$LAST" ]]; then
    continue
  fi
  LAST="$NOW"
  rebuild "change detected"
done

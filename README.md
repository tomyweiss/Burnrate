# Tokens

Lightweight macOS menu bar app that shows your **Cursor spend since local midnight**, breaks it down **per model** (cost + tokens), and notifies you when spend spikes (**$10 in 10 minutes** by default).

## Requirements

- macOS 14+
- [Cursor](https://cursor.com) installed and signed in on this Mac
- Swift toolchain (Xcode or Command Line Tools) to build from source

## Install

```bash
cd /Users/tom/workspace/tokens
bash scripts/package.sh --install --open
```

This builds a release binary, installs `Tokens.app` to `/Applications`, and launches it.

Rebuild later:

```bash
bash scripts/package.sh --install --open
```

## Usage

| Menu bar | Click |
|----------|--------|
| `$12.40` | Today’s total, per-model cost and tokens, Refresh / Settings / Quit |
| `!` | Auth or API error — open the dropdown for details |

**Settings:** refresh interval, anomaly threshold / window / cooldown, launch at login.

**Status check:**

```bash
/Applications/Tokens.app/Contents/MacOS/Tokens --status
```

Expected: `OK $12.40 today (67 events)` (your numbers will differ).

## How it works

1. Reads `cursorAuth/accessToken` from Cursor’s local SQLite DB  
   `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
2. Builds a `WorkosCursorSessionToken` cookie from the JWT (never stored by Tokens)
3. Polls `POST https://cursor.com/api/dashboard/get-filtered-usage-events` for events since midnight
4. Aggregates `chargedCents` and token counts in memory for the menu bar, dropdown, and anomaly window

## Limitations

- Uses Cursor’s **undocumented** dashboard API — may change without notice
- Personal / individual session only (local IDE login)
- Not notarized — first open may need right-click → Open, or use `scripts/package.sh --install`

## Development

```bash
swift build
.build/debug/Tokens --status   # may fail outside an .app for notifications; prefer the packaged binary
bash scripts/package.sh --open
```

## License

Private — for personal use.

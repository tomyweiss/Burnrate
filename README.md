# Burnrate

Lightweight macOS menu bar app for **Cursor spend since local midnight** — how fast you're burning money, broken down by model and session, with spike alerts.

## Requirements

- macOS 26+
- [Cursor](https://cursor.com) installed and signed in on this Mac
- Xcode 26 / macOS 26 SDK to build from source

## Install

```bash
bash scripts/package.sh --install --open
```

Installs `Burnrate.app` to `/Applications` and launches it. The app uses a flame icon in Finder (matching the menu bar symbol).

## Usage

| Menu bar | Click |
|----------|--------|
| Flame + `$12.40` | Today total, burn pill, hourly sparkline, Models / Sessions tabs |
| Flame filled | Recent-window spend is at/above your spike threshold |
| Warning triangle | Auth/API error (amount still shown when known) |

**Settings:** refresh interval, spike threshold / window / cooldown, launch at login, hide amount in menu bar, test notification.

**Status check:**

```bash
/Applications/Burnrate.app/Contents/MacOS/Tokens --status
```

## How it works

1. Reads Cursor’s local session from `state.vscdb`
2. Polls Cursor’s dashboard usage events API for today’s events
3. Aggregates `chargedCents` into today total, hourly bars, models, and sessions
4. Resolves session titles / workspaces from local composer metadata

See [CAPABILITIES.md](CAPABILITIES.md) for the full feature list.

## Limitations

- Undocumented Cursor dashboard API — may change
- Personal session only (local IDE login)
- Not notarized — first open may need right-click → Open

## License

Private — for personal use.

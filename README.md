# Burnrate

**See how fast you’re burning Cursor spend — without opening the dashboard.**

Burnrate is a lightweight macOS menu bar app that shows today’s Cursor usage since local midnight, breaks it down by model and chat session, and notifies you when spend spikes.

<img src="Resources/AppIcon-1024.png" width="128" alt="Burnrate icon" />

## Features

- **Menu bar total** — today’s cost at a glance (flame icon; fills when you’re in a spike)
- **Burn pill** — spend in your rolling alert window (e.g. last 10 minutes)
- **Hourly sparkline** — shape of the day from midnight to now
- **Models tab** — cost share bars, expand for tokens and per-session rows
- **Sessions tab** — chats across models, with titles and workspace names from local Cursor data
- **Spike alerts** — macOS notification when spend crosses your threshold (default $10 / 10 min)
- **Zero cookie paste** — uses your signed-in Cursor IDE session on this Mac
- **Privacy-minded** — does not store your auth token; does not call models (won’t bump AI usage)

## Requirements

- macOS 26 or later
- [Cursor](https://cursor.com) installed and signed in on the same Mac
- Xcode 26 (or Command Line Tools with the macOS 26 SDK) to build from source

## Install

```bash
git clone https://github.com/tomyweiss/Burnrate.git
cd Burnrate
bash scripts/package.sh --install --open
```

This builds a release binary, installs `Burnrate.app` to `/Applications`, and launches it.

**First launch:** the app isn’t notarized. If Gatekeeper blocks it, right-click the app → **Open**, or run:

```bash
xattr -dr com.apple.quarantine /Applications/Burnrate.app
open /Applications/Burnrate.app
```

### Verify

```bash
/Applications/Burnrate.app/Contents/MacOS/Tokens --status
```

Example: `OK $12.40 today (67 events)`

## Usage

| Menu bar | Meaning |
|----------|---------|
| Flame + `$12.40` | Today’s spend; click for the panel |
| Filled flame | Recent-window spend ≥ your spike threshold |
| Warning triangle | Auth or API problem (last known amount still shown when possible) |

**Panel:** today total, burn pill, sparkline, **Models** / **Sessions** tabs, Settings, Refresh, and overflow (open Cursor dashboard / Quit).

**Settings:** poll interval, spike threshold / window / cooldown, launch at login, hide amount in the menu bar, test notification.

## Privacy & security

- Reads `cursorAuth/accessToken` from Cursor’s local SQLite DB on each refresh — **never written** to Burnrate’s own storage or Keychain
- Fetches usage over HTTPS from Cursor’s dashboard endpoints using that session
- Session names and workspace folders come from **local** Cursor composer metadata
- No analytics, no third-party servers, no model/API calls that consume Cursor usage

## How it works

1. Load the local Cursor session from  
   `~/Library/Application Support/Cursor/User/globalStorage/state.vscdb`
2. Poll `POST https://cursor.com/api/dashboard/get-filtered-usage-events` for events since midnight
3. Sum Cursor’s `chargedCents` for totals, hourly bars, models, and sessions
4. Resolve chat titles / workspaces from local composer data when available

Costs are Cursor-reported charges from usage events, not a hand-rolled price estimate. Full behavior: [CAPABILITIES.md](CAPABILITIES.md).

## Limitations

- Relies on Cursor’s **undocumented** dashboard API — it can change or break without notice
- Individual / personal session only (the account signed into Cursor on this Mac)
- “Today” means **local midnight**, not UTC or billing-cycle start
- Not an official Cursor product; totals may differ slightly from the website
- Not notarized for distribution outside building from source

## Development

```bash
swift build
bash scripts/package.sh --open
```

Package layout: Swift package target `Tokens` (internal name), shipped as **Burnrate.app**.

## Contributing

Issues and PRs are welcome. Please keep changes focused; this is intentionally a small menu bar utility.

## License

[MIT](LICENSE) © Tom Weiss

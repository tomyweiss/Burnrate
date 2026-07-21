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
- **Self-updates** — checks GitHub Releases, verifies SHA-256, replaces the app (not Apple-notarized)

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

**Settings:** poll interval, spike threshold / window / cooldown, launch at login, hide amount in the menu bar, test notification, updates.

## Updates (messy OTA)

Burnrate can update itself from [GitHub Releases](https://github.com/tomyweiss/Burnrate/releases) without an Apple Developer ID:

1. Checks `releases/latest` for a newer version tag
2. Downloads `Burnrate-x.y.z.zip`, verifies `Burnrate-x.y.z.sha256`, then verifies the minisign signature (`Burnrate-x.y.z.zip.minisig`) against the embedded public key
3. Quits, replaces the running `.app`, strips quarantine, relaunches

Use **⋯ → Check for Updates…** or Settings → Updates. You confirm before install. Builds are **not notarized**; if macOS blocks a new build, right-click → Open or run `xattr -dr com.apple.quarantine` on the app.

### Cutting a release (maintainers)

Requires [minisign](https://jedisct1.github.io/minisign/) and the release signing secret key at `~/.config/burnrate/burnrate.key` (or set `MINISIGN_SECRET_KEY`). The matching public key is committed as [`burnrate.pub`](burnrate.pub) and embedded in the app.

```bash
VERSION=0.0.6 bash scripts/package.sh --release
# uploads:
#   dist/Burnrate-0.0.6.zip
#   dist/Burnrate-0.0.6.sha256
#   dist/Burnrate-0.0.6.zip.minisig
```

Create a GitHub Release tagged `0.0.6` or `v0.0.6` and attach **all three** files. The zip must contain `Burnrate.app` at the top level (as produced by the script). Updates without a valid `.minisig` are rejected.

## Privacy & security

- Reads `cursorAuth/accessToken` from Cursor’s local SQLite DB on each refresh — **never written** to Burnrate’s own storage or Keychain
- Fetches usage over HTTPS from Cursor’s dashboard endpoints using that session
- Session names and workspace folders come from **local** Cursor composer metadata
- No analytics, no third-party servers, no model/API calls that consume Cursor usage
- Self-updates require a minisign signature matching the embedded public key (not only a SHA-256 checksum from the same release)

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

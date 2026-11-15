# Burnrate — Capabilities

## Idea

**Burnrate** is a lightweight macOS menu bar app that answers: *how fast am I burning Cursor spend, and what is Claude Code using, right now?*

It shows **the selected timeline** (Today, Last 24h, Last 7d, or This billing), a **burn pill** for the rolling spike window, a **sparkline** across the active window, and breakdowns by **model** and **session**. It notifies when a source spikes (default: **$10 in 10 minutes**). Cursor dollars are billed. Claude Code dollars are estimates, shown with `~`, and the two are never added.

No Dock icon. Cursor auth comes from the local IDE login. Claude Code spend is read from local transcripts.

---

## Core capabilities

### Menu bar

- Flame SF Symbol + the figures chosen in Settings. Cursor figures first (window spend, Cursor models %, Other models %, Grok Bot %), then Claude Code (estimated spend, and `5h` / `wk` when plan limits are on). All off hides the text.
- Estimated Claude Code spend is `CC ~$31.20` when Cursor spend is also shown, and `~$31.20` on its own. Off after an update when Cursor is signed in. On when Claude Code is the only source and the toggle has never been set. Before the first index finishes it reads `~$—`.
- `flame.fill` when recent spend on any enabled source ≥ spike threshold
- Warning triangle when any enabled source has an error, while keeping the last known amount
- Polls on a timer (default 60s; 15s–10m presets). Plan limits are not requested more than once a minute

### Usage panel (460×580)

- **Source switcher** — Cursor | Claude Code, only when both are enabled and detected. Each segment shows that source's window figure. Selection is remembered. Claude-only (no Cursor login) opens on Claude Code with no switcher.
- **Hero** matches the status-bar figures for Cursor. A percent-only choice keeps the timeline dollar total smaller underneath. Claude Code uses `~` and the caption "Estimated at API list prices · not your bill".
- **Plan limits** — off by default. When on, 5-hour and weekly gauges sit above the token line. The token line is always shown. A model with no price adds "No price for <model>. Tokens shown, cost excluded".
- **One-time hint** — "Burnrate now tracks Claude Code", with Show in menu bar and Dismiss, the first time Claude Code is detected while Cursor is signed in and Claude spend is off.
- **Timeline picker** — Today, Last 24h, Last 7d, This billing. Shared by both sources.
- **Burn pill** (glass) for rolling-window spend, tinted by severity. Claude Code amounts use `~`.
- **Sparkline** for the active window (hourly or daily buckets)
- Caption only while indexing, or when data is offline or stale
- Tabs: **Models** | **Sessions** | **Skills** | **Feed** | **Bench**
- **Community** opens from a trophy chip in the header (next to the timeline). Cursor scope only.
- Footer: Settings (glass), Refresh, overflow menu (Dashboard / Quit)

### Models tab

- Share bar (fraction of window total)
- Sessions · events · total tokens summary
- Expand for in/out/cache detail and per-session rows

### Sessions tab

- Cross-model sessions sorted by cost
- Cursor: name from local chat metadata, workspace, model chips, relative activity
- Claude Code: one row per session transcript. Workspace is the folder. Subagents open inside the session. Archive and cloud icons are not shown
- Share bar vs window total

### Community (opt-in)

- Cursor only. Claude Code events are never uploaded. The chip is hidden when Cursor is not selected
- Locked until you enable sharing
- Uploads anonymous 24h Cursor spend + per-model cost breakdown (no session/prompt data)
- Share-to-view: cohort rank, median, and near-you list only when sharing is on
- Optional fun nickname (Shuffle / Clear); opt-out deletes server data

### Anomaly alerts

- Configurable threshold / window / cooldown, evaluated per source. Cooldown is per source. The sources are never summed
- Test notification from Settings
- Cursor title: “Burnrate spike”. Claude Code title: “Burnrate spike · Claude Code”, and the body says the amount is estimated

### Settings

- **Sources** — enable Cursor and Claude Code (on by default). Labels show signed-in / session count. **Show plan limits** is off by default
- Timeline window picker (Today / 24h / 7d / This billing)
- Billing day stepper (1–31, when This billing is selected)
- Timezone picker (System or searchable IANA list)
- Poll interval picker
- Native steppers for spike rules
- Launch at login
- Status bar grouped by source. Cursor: window spend, Cursor models, Other models, Grok Bot. Claude Code: spend (estimated), and, only while plan limits are on, session limit (5h) and weekly limit
- About + dashboard link

### Auth & data

- Cursor token from `state.vscdb`, Agent CLI `~/.cursor/auth.json`, or the CLI Keychain login (not stored by Burnrate)
- Cursor costs from `chargedCents` on dashboard usage events (network)
- Cursor session names / workspaces from local composer metadata
- Claude Code from `~/.claude/projects` (session and subagent `.jsonl`). Incremental index at `~/Library/Application Support/Burnrate/claude-index.json`. Never uploaded
- Claude Code cost is local token counts × a bundled Anthropic API list-price table, including separate 5-minute and 1-hour cache-write prices. Unknown models: tokens shown, cost excluded
- Plan limits (opt-in): `Claude Code-credentials` Keychain item, read in memory only, never stored or refreshed. `GET https://api.anthropic.com/api/oauth/usage` at most once a minute. Does not consume model usage

### CLI

```bash
/Applications/Burnrate.app/Contents/MacOS/Tokens --status
```

### Updates

- Auto-check Sparkle appcast daily (toggle in Settings, default on)
- Manual check from Settings; Sparkle prompts before install
- Burnrate-dev: updates stay disabled
- Sparkle-signed zips only; minisign is no longer used for new tags

---

## Limitations

- Undocumented Cursor API
- Needs Cursor signed in on this Mac (app or `agent login`), or Claude Code transcripts under `~/.claude/projects`
- Default timeline is Today (local midnight in chosen timezone)
- Longer Cursor windows may hit API pagination limits (~4000 events)
- Cursor costs are reported charges, not a formal invoice
- Claude Code dollars are estimates, not your Anthropic bill. Long-context price tiers are not modeled
- Claude Code deletes old transcripts. The index keeps events already read

## Defaults

| Setting | Default |
|--------|---------|
| Timeline | Today |
| Billing day | 1 |
| Timezone | System (local) |
| Refresh | 60 seconds |
| Anomaly threshold | $10 |
| Anomaly window | 10 minutes |
| Alert cooldown | 15 minutes |
| Status bar figures | Window spend on; Cursor percents off |
| Claude Code source | On when `~/.claude/projects` has a transcript |
| Show plan limits | Off |
| Status bar Claude Code spend | Off when Cursor is signed in. On when Claude Code is the only source and the toggle has never been set |
| Status bar 5h / weekly | Off. Toggles appear only while plan limits are on |
| Launch at login | off unless already enabled |

## License

[MIT](LICENSE)


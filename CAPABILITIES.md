# Burnrate — Capabilities

## Idea

**Burnrate** is a lightweight macOS menu bar app that answers: *how fast am I burning Cursor spend, and what is Claude Code using, right now?*

It shows **the selected timeline** (Today, Last 24h, Last 7d, or This billing), a **burn pill** for the rolling spike window, a **sparkline** across the active window, and breakdowns by **model** and **session**. It notifies when a source spikes (default: **$10 in 10 minutes**). Cursor dollars are billed. Claude Code dollars are estimates, shown with `~`, and the two are never added.

No Dock icon. Cursor auth comes from the local IDE login. Claude Code spend is read from local transcripts.

---

## Core capabilities

### Menu bar

- Flame SF Symbol + the figures chosen in Settings. Cursor figures first (window spend, Cursor models %, Other models %, Grok Bot %), then Claude Code (estimated spend, and `5h` / `wk` only when plan limits are on and those status-bar toggles are on). All off hides the text.
- Estimated Claude Code spend is `CC ~$31.20` when Cursor spend is also shown, and `~$31.20` on its own. Off after an update when Cursor is signed in. On when Claude Code is the only source and the toggle has never been set. Before the first index finishes it reads `~$—`.
- `flame.fill` when recent spend on any enabled source ≥ spike threshold
- Warning triangle when any enabled source has an error, while keeping the last known amount
- Polls on a timer (default 60s; 15s–10m presets). Plan limits are not requested more than once a minute

### Usage panel (500×620)

- **Top row** — timeline picker (Today, Last 24h, Last 7d, This billing, Custom; shared by both sources), the **Keep awake** button, the **Community** button, and the **···** menu.
- **Source cards** — one card per enabled and detected source. Each shows the window spend, a burn pill for rolling-window spend (tinted by severity), and a small sparkline of the window. Clicking a card selects that source; the selection is remembered. With one source the card is full width and not a button. The Cursor card is always window spend. The Claude Code card is titled "Claude Code · estimated" and its amounts use `~`.
- **Bucket rows** — name, bar, percent used, and reset time when known. Cursor: Cursor models, Other models (when the period has that bucket), Grok Bot (when present). Claude Code: 5h limit, Weekly limit, Opus weekly, Sonnet weekly, Extra usage, for the windows Anthropic reports.
- **Plan limits** — off by default. While off, the Claude Code rows are replaced by a **Show plan limits** button. A sign-in problem shows its message in that row.
- **This cycle** — the last row. Cursor splits Included and On-demand. Claude Code is the list-price estimate, with Extra when that pool is on.
- Captions under the rows only when needed: a model with no price ("No price for <model>. Tokens shown, cost excluded"), indexing, offline or stale data, and why keep-awake stopped.
- **One-time hint** — "Burnrate now tracks Claude Code", with Show in menu bar and Dismiss, the first time Claude Code is detected while Cursor is signed in and Claude spend is off.
- Tabs: **Models** | **Sessions** | **Skills** | **Feed** | **Bench** (Bench is 500×660). Sort and search are on the tab row.
- **Community** opens from the trophy button in the top row. One button for both sources.
- **Keep awake** — a labelled cup button in the top row. Idle, it is violet, reads "Keep awake", and offers the durations. While a trip runs it turns green, reads "Awake · 28m", and offers Stop. It reads "Starting…" while macOS asks for the password. When the row is too narrow it drops the title and keeps the cup and the time left. The first time the panel opens, a note explains the button until you dismiss it or start a trip. That note waits while the Claude Code hint is showing.
- **··· menu** — Settings, Stats (the stat tiles and the token line), Refresh (⌘R), Quit (⌘Q). There is no footer.

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

- One leaderboard for Cursor and Claude Code. The same person's spend is added together. The chip is on both sources
- Locked until you enable sharing
- Uploads anonymous 24h spend + per-model cost breakdown for both sources (no session/prompt data). Claude Code amounts are the local list-price estimates
- Share-to-view: cohort rank, median, and near-you list only when sharing is on
- Optional fun nickname (Shuffle / Clear); opt-out deletes server data

### Anomaly alerts

- Configurable threshold / window / cooldown, evaluated per source. Cooldown is per source. The sources are never summed
- Test notification from Settings
- Cursor title: “Burnrate spike”. Claude Code title: “Burnrate spike · Claude Code”, and the body says the amount is estimated

### Settings

- Opens as a list. Each row shows its current value and opens a page. **Launch at login** and **Blur session & prompt titles** are switches on the list
- **Sources** — enable Cursor and Claude Code (on by default). Labels show signed-in / session count. **Show plan limits** is off by default
- **Menu bar** — a preview, then the figures grouped by source. Cursor: window spend, Cursor models, Other models, Grok Bot. Claude Code: spend (estimated), and, only while plan limits are on, session limit (5h) and weekly limit
- **Spike alert** — native steppers for threshold, window, and cooldown, plus Test notification
- **Panel** — which tabs are visible, and the session display options
- **Data** — poll interval, timezone (System or searchable IANA list), billing day (1–31, when This billing is selected or Claude Code is enabled), and the custom date range when that window is selected
- **Updates** — auto-check, Check for Updates, and the change log
- About + dashboard link

### Auth & data

- Cursor token from `state.vscdb`, Agent CLI `~/.cursor/auth.json`, or the CLI Keychain login (not stored by Burnrate)
- Cursor costs from `chargedCents` on dashboard usage events (network)
- Cursor session names / workspaces from local composer metadata
- Claude Code from `~/.claude/projects` (session and subagent `.jsonl`). Incremental index at `~/Library/Application Support/Burnrate/claude-index.json`. Never uploaded
- Claude Code cost is local token counts × a bundled Anthropic API list-price table, including separate 5-minute and 1-hour cache-write prices. Unknown models: tokens shown, cost excluded
- Plan limits (opt-in): `Claude Code-credentials` Keychain item, read in memory only. When the token is expired or rejected, renewed with its refresh token (`POST https://platform.claude.com/v1/oauth/token`, at most every 5 minutes) and written back to the same item. `GET https://api.anthropic.com/api/oauth/usage` at most once a minute. Does not consume model usage

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


# Burnrate — Capabilities

## Idea

**Burnrate** is a lightweight macOS menu bar app that answers: *how fast am I burning money in Cursor right now?*

It shows **spend for your selected timeline** (Today, Last 24h, Last 7d, or This billing), a **burn pill** for the rolling spike window, a **sparkline** across the active window, and breakdowns by **model** and **session**. It notifies when spend spikes (default: **$10 in 10 minutes**).

No Dock icon. Auth comes from the local Cursor IDE login.

---

## Core capabilities

### Menu bar

- Flame SF Symbol + window total (optional: hide amount)
- `flame.fill` when recent-window spend ≥ spike threshold
- Warning triangle on error while keeping the last known amount
- Polls on a timer (default 60s; 15s–10m presets)

### Usage panel (380×520)

- **Hero** window total with numeric transitions
- **Timeline picker** — Today, Last 24h, Last 7d, This billing
- **Burn pill** (glass) for rolling-window spend, tinted by severity
- **Sparkline** for the active window (hourly or daily buckets)
- Caption: updated time · event count (orange when stale)
- Tabs: **Models** | **Sessions**
- Footer: Settings (glass), Refresh, overflow menu (Dashboard / Quit)

### Models tab

- Share bar (fraction of window total)
- Sessions · events · total tokens summary
- Expand for in/out/cache detail and per-session rows

### Sessions tab

- Cross-model sessions sorted by cost
- Name (from local Cursor chat metadata), workspace, model chips, relative activity
- Share bar vs window total

### Anomaly alerts

- Configurable threshold / window / cooldown
- Test notification from Settings
- Notification title: “Burnrate spike”

### Settings

- Timeline window picker (Today / 24h / 7d / This billing)
- Billing day stepper (1–31, when This billing is selected)
- Timezone picker (System or searchable IANA list)
- Poll interval picker
- Native steppers for spike rules
- Launch at login, hide menu-bar amount
- About + dashboard link

### Auth & data

- Token from Cursor `state.vscdb` (not stored by Burnrate)
- Costs from `chargedCents` on dashboard usage events (network)
- Session names / workspaces from local composer metadata

### CLI

```bash
/Applications/Burnrate.app/Contents/MacOS/Tokens --status
```

### Updates

- Auto-check GitHub Releases (toggle in Settings, default on)
- Manual check from overflow menu / Settings
- SHA-256 verified zip replace of the running app (not notarized)

---

## Limitations

- Undocumented Cursor API
- Requires Cursor signed in on this Mac
- Default timeline is Today (local midnight in chosen timezone)
- Longer windows may hit API pagination limits (~4000 events)
- Costs are Cursor-reported charges, not a formal invoice

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
| Hide menu-bar amount | off |
| Launch at login | off unless already enabled |

## License

[MIT](LICENSE)


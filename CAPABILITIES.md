# Burnrate — Capabilities

## Idea

**Burnrate** is a lightweight macOS menu bar app that answers: *how fast am I burning money in Cursor right now?*

It shows **today’s spend since local midnight**, a **burn pill** for the rolling spike window, an **hourly sparkline** of the day, and breakdowns by **model** and **session**. It notifies when spend spikes (default: **$10 in 10 minutes**).

No Dock icon. Auth comes from the local Cursor IDE login.

---

## Core capabilities

### Menu bar

- Flame SF Symbol + today’s amount (optional: hide amount)
- `flame.fill` when recent-window spend ≥ spike threshold
- Warning triangle on error while keeping the last known amount
- Polls on a timer (default 60s; 15s–10m presets)

### Usage panel (380×520)

- **Hero** today total with numeric transitions
- **Burn pill** (glass) for rolling-window spend, tinted by severity
- **24-hour sparkline** (midnight → now)
- Caption: updated time · event count (orange when stale)
- Tabs: **Models** | **Sessions**
- Footer: Settings (glass), Refresh, overflow menu (Dashboard / Quit)

### Models tab

- Share bar (fraction of today’s cost)
- Sessions · events · total tokens summary
- Expand for in/out/cache detail and per-session rows

### Sessions tab

- Cross-model sessions sorted by cost
- Name (from local Cursor chat metadata), workspace, model chips, relative activity
- Share bar vs today’s total

### Anomaly alerts

- Configurable threshold / window / cooldown
- Test notification from Settings
- Notification title: “Burnrate spike”

### Settings

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

---

## Limitations

- Undocumented Cursor API
- Requires Cursor signed in on this Mac
- “Today” = local midnight
- Costs are Cursor-reported charges, not a formal invoice

## Defaults

| Setting | Default |
|--------|---------|
| Refresh | 60 seconds |
| Anomaly threshold | $10 |
| Anomaly window | 10 minutes |
| Alert cooldown | 15 minutes |
| Hide menu-bar amount | off |
| Launch at login | off unless already enabled |

## License

[MIT](LICENSE)


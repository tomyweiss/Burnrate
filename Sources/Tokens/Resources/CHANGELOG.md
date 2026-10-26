# Changelog

## 0.60.5

- Keychain guidance for encrypted Cursor logins says to choose Always Allow, so the "Cursor Safe Storage" prompt stops returning on every launch.

## 0.60.4

- Spend loads again when Cursor keeps your login locked in the Mac keychain.

## 0.60.3

- Status bar and header can show any mix of window spend, Cursor models percent, and Other models percent. Both percents use C and O labels. All off leaves the flame alone.
- Settings grouped into sections; redundant captions removed.
- Event cache no longer treats a range that starts before the cache as covered.
- Keychain membership migration clears the leftover UserDefaults secret.

## 0.60.2

- Number tied community leaderboard rows in order, so two people with the same spend get consecutive places.

## 0.60.1

- Regroup the header into two columns: included-allowance rings on the left, and on the right a single stacked bar splitting this cycle's spend between included and on-demand, with the hourly usage chart beneath it.
- Blue now always means covered by the plan and orange means paying: an exhausted pool turns orange to match the on-demand segment.
- Drop the cycle-reset caption and the "Updated … ago" line; the caption only appears for offline or stale data.
- Align the spike pill with the Community and timeline controls, and narrow the panel to 540pt.

## 0.60.0

- Show Cursor models and Other models included-pool usage, plus on-demand and included spend, as gauges in the header.
- Widen the panel so the Community button stays on one line.
- Document installing from the latest GitHub release zip or by building from source.

## 0.0.58

- Add a frosted panel background so the menu bar window stays readable on busy wallpapers. (04e3e3b)

## 0.0.57

- Community sharing uploads per-UTC-day slash-command invocation counts and spend (operator Postgres only; no UI change).

## 0.0.56

- Load spend from Agent CLI login (`agent login`) without opening the Cursor app.

## 0.0.55

- Notarize releases and fix Sparkle signing so in-app updates install successfully.

## 0.0.54

- Fix By day leaderboard showing stale Live data when a historical fetch fails.
- Fix community API auth for swift run and other ad-hoc local builds.

## 0.0.53

- Sign releases with Developer ID so Sparkle in-app updates install successfully.

## 0.0.52

- Fix Sparkle update dialogs hidden behind the floating menu bar panel.

## 0.0.51

- Retire minisign self-updates. New releases are Sparkle-signed only. Install the previous Sparkle bridge release first if you are still on the old zip updater.

## 0.0.50

- Use Sparkle for in-app updates (daily check; you confirm before install). This GitHub Release is still minisign-signed so older apps can update to it. Burnrate-dev still does not auto-update.

## 0.0.48

- Show each community leaderboard row's top 24h model and app version. (929eb4f)
- Compact long model names by dropping the `claude-` prefix and truncating with a prefix ellipsis. (929eb4f)
- Remove client-side leaderboard nickname dedup; the API now returns one row per participant. (929eb4f)

## 0.0.41

- Community sharing always uses your Cursor display name; removed random and anonymous nickname options.

## 0.0.40

- Show top 30 community leaderboard entries with scrollable layout. (ad87c0a)

## 0.0.39

- Add community daily analytics with backward-compatible server support. (f7abf0c)

## 0.0.38

- Fix the calculation (6cdf1af)

## 0.0.37

- feat: Custom timeline preset with inclusive date-range picker (5358475)

## 0.0.36

- Changelog for v0.0.35 (4c108f7)

## 0.0.35

- Fix changelog crash in packaged app by avoiding Bundle.module. (02a130b)

## 0.0.34

- Route changelog at panel level to avoid Settings Form teardown crash. (875b38a)

## 0.0.33

- Replace changelog overlay with full view swap so Settings does not show through. (62b5649)
- Stay usable offline and log client failures for debugging. (5b9ed17)

## 0.0.32

- Fix changelog crash by removing Liquid Glass and make usage tabs configurable. (6c84c1f)

## 0.0.31

- Fix Settings change log crash from mismatched glass effect IDs

## 0.0.30

- Fix changelog navigation and show the last three versions. (ac02358)

## 0.0.29

- Copy conversation log source path from session detail
- Open a model session in the Sessions tab and drill into its detail view
- Change log in Settings with what's new for your version

## 0.0.28

- Opt-in community interaction stats for panel opens and tab changes
- Fix panel ghost artifacts when dismissing the menu bar panel
- Fix panel behavior when switching macOS fullscreen spaces
- Community tab moved to a header trophy chip
- Section search on Models, Sessions, Skills, and Feed tabs
- Bench breakdown picker moved to the secondary control row

## 0.0.27

- Community nickname options including Cursor display name
- Client version sent with community snapshots
- Session subagent hierarchy in session detail

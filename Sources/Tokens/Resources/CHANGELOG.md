# Changelog

## 0.60.17

- Claude Code always shows the Weekly limit row under the 5h limit. Before, the row disappeared whenever Anthropic left the 7-day window out of its reply, such as early in a fresh week. A window that isn't reported shows a dash.
- Burnrate also reads the 5h and weekly windows from the newer limits list Anthropic sends, so they still show when the older fields are empty.
- When you have signed out of Claude Code, the panel asks you to sign in again. Before, Burnrate tried to read the blank login and showed a less helpful error.

## 0.60.16

- Keep awake has a Custom option. Type how long to stay awake, like 2h, 1h30, or 75 minutes, from 5 minutes up to 8 hours. Burnrate remembers the last length you typed.
- Trips longer than an hour show the time left in hours and minutes, such as 1h 24m.
- The Keep awake menu heading is shorter.
- When another app has already turned sleep off, Burnrate now offers to turn sleep back on. Before, the message had two buttons that both just closed it, and there was no way out from Burnrate.
- The "Burnrate couldn't change sleep" message has a single OK button.

## 0.60.15

- Burnrate now tells you when an update is out. The daily check posts a notification and shows a banner at the top of the panel. Before, it could find an update and say nothing until you checked by hand in Settings.
- If Burnrate already downloaded an update in the background, the banner offers Restart to Update instead of waiting for you to quit the app.
- The panel is simpler and shorter. Cursor and Claude Code are two cards at the top. Each card shows that source's spend for the window, the burn pill, and a small chart. Click a card to see that source.
- Included usage and plan limits are rows instead of rings: a name, a bar, the percent used, and the reset time when there is one. This cycle is the last row.
- The Cursor card always shows window spend. Before, the big figure followed the menu bar figures.
- Keep awake is a labelled button in the top row, next to Community. Idle, the cup is violet. It turns green and shows the time left while the Mac is held awake. Settings, Stats, Refresh, and Quit are in the ··· menu at the top right. The footer is gone, so the list has more room. The stat tiles and the token line moved to Stats.
- The first time you open the panel, a short note explains Keep awake. It goes away when you dismiss it or start a trip, and it waits if the Claude Code hint is showing.
- Sort and search are on the tab row.
- Settings opens as a short list that shows each current value. Sources, Menu bar, Spike alert, Panel, Data, and Updates each open their own page. Launch at login and Blur session & prompt titles are switches on the list.

## 0.60.14

- Community is one leaderboard, available from both Cursor and Claude Code. Cursor spend and estimated Claude Code spend for the same person are added together. Session transcripts and prompts stay on this Mac.
- Claude Code shows Spend this cycle: estimated list-price spend since the billing cycle started. Extra, when that pool is on, is the on-demand amount Anthropic has billed and is not added to the estimate.
- The Included allowance heading is gone. The pool rings sit directly above Spend this cycle.

## 0.60.13

- Claude Code plan limits keep working when you only use Claude Code from the Claude desktop app. The desktop app never renews the login Burnrate reads, so the gauges went blank about 8 hours after you last ran `claude` in Terminal. Burnrate now renews that login itself and saves it back for Claude Code, at most every 5 minutes, and keeps Claude Code's token if it renewed first.

## 0.60.12

- Claude Code plan limits no longer bring up a Keychain password prompt every time Claude Code renews its login. Burnrate now reads the login with the same macOS tool Claude Code uses, so "Always Allow" is no longer needed.

## 0.60.11

- Track Claude Code next to Cursor. The panel switches between them when both are present, and opens on Claude Code alone when Cursor is not signed in. The two amounts are never added.
- Claude Code dollars are estimates from local token counts times Anthropic API list prices, shown with `~`. They are not your bill. Pro and Max still pay a flat rate. A model with no price shows its tokens and is left out of the cost. Long-context price tiers are not in the table, so an estimate can differ from an API bill.
- Session and subagent transcripts are read from `~/.claude/projects` on this Mac and indexed locally. Claude Code deletes old transcripts later; the index keeps what Burnrate already read. Nothing from Claude Code is uploaded, and Community stays Cursor-only.
- The menu bar can show estimated Claude Code spend, tagged `CC` only when Cursor spend is also on. The first time both sources are present, the panel offers to show it. With plan limits on, it can also show `5h` and `wk` percents.
- Plan limits are off until you turn them on in Settings. Burnrate reads the Claude Code login from Keychain in memory and checks the 5-hour, weekly, and per-model weekly limits at most once a minute, plus extra usage when that pool is on. It does not store or refresh the token, and the request does not use model quota.
- Spike alerts use the same threshold, window, and cooldown for each source. A Claude Code alert says the amount is estimated.
- Settings has a Sources section to enable each source, and status bar figures are grouped by source.
- The panel header now leads: larger allowance rings and a stats grid (sessions, events, top model, cache read, per hour, average per session), with the tabs in a shorter list below. The panel is a little taller.

## 0.60.10

- Team accounts see their spend again. Cursor stopped returning a team member's usage events unless the request names the team, which left today and every Feed prompt at $0.00.
- Sessions you're working in show up right away, before Cursor bills them. Grok Bot agents that were idle in the selected window no longer appear in it.

## 0.60.9

- Other models shows named-model usage of the shared included allowance. An API quota that stays at 0% no longer hides that spend.

## 0.60.8

- Included-allowance rings follow the same monthly cycle as spend, so Cursor models no longer copies the weekly Grok Bot pool.

## 0.60.7

- Included allowance follows Cursor's current billing period. The Other models ring hides when this period has no separate bucket, and usage under 1% shows as 1% so Grok Bot does not look empty.

## 0.60.6

- Open a Grok Bot usage row on the bot that ran it, with that bot's name and prompts. A task with no local transcript stays labeled Grok Bot task.

## 0.60.5

- Show the weekly Grok Bot allowance as a third included-pool ring, with the date it resets. Settings can add it to the status bar; it reads GB when another percent is showing.
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

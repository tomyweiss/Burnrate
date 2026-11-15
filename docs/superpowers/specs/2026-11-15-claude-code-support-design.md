# Claude Code support — design

**Date:** 2026-11-15
**Status:** Draft, awaiting review
**Product:** Burnrate (macOS menu bar app)

## Summary

Burnrate gains a second usage source, Claude Code, next to Cursor. The panel gets a **Cursor | Claude Code** source switcher; each source feeds its own `UsageSnapshot`, so the existing tabs render either one. Cursor dollars are billed charges; Claude Code dollars are estimates at Anthropic API list prices. The two are never summed, and every Claude Code dollar is shown with a `~`.

Claude Code data is read locally from `~/.claude/projects`. Plan limits (5-hour and weekly %) are available in v1 behind an opt-in toggle, because reading them needs the Claude Code OAuth token from Keychain and one network call.

## Decisions

| Question | Decision |
|---|---|
| Layout | Source switcher at the top of the panel, one snapshot per source |
| Combined total | None. The two figures appear side by side, never added |
| Menu bar after update | Unchanged; one-time hint in the panel with a **Show in menu bar** button |
| Plan limits | In v1, opt-in toggle, off by default |
| Spike alerts | On for both sources, evaluated per source, never summed |
| Community | Cursor only |

## Sources and detection

- `UsageSource` enum: `.cursor`, `.claudeCode`.
- Settings gets a **Sources** section at the top: "Cursor · Signed in" / "Claude Code · 164 sessions in ~/.claude". Each source has an enable toggle, on by default when detected.
- Claude Code is detected when `~/.claude/projects` exists and contains at least one `.jsonl`.
- **Claude Code only** (no Cursor login): the Cursor source is disabled quietly instead of raising `tokenNotFound`. The panel opens in Claude Code scope with no switcher and no Community chip; the Claude Code spend figure defaults on in the status bar.
- **Neither source:** "No Cursor session or Claude Code data found. Sign in to Cursor, or run Claude Code once."

## Reading Claude Code data

New types: `ClaudeTranscriptIndex` (scan + parse), `ClaudePricing` (price table), `ClaudeCodeStore` (refresh loop, publishes a `UsageSnapshot`).

### Files

- Sessions: `~/.claude/projects/<escaped-cwd>/<sessionId>.jsonl`.
- Subagents: `~/.claude/projects/<escaped-cwd>/<sessionId>/subagents/agent-*.jsonl`. They belong to the parent session.

### Events

One usage event per assistant line with `message.usage`, carrying: `timestamp`, `sessionId`, `cwd`, `gitBranch`, `message.model`, `message.id`, input / output / cache-creation / cache-read tokens, `isSidechain`.

- **Dedupe:** streaming can write several lines with the same `message.id`. Keep one event per `message.id` (the last line seen, which carries final output tokens). This must be covered by a test using a fixture with repeated ids.
- Skip `model == "<synthetic>"`.
- Session title comes from `custom-title` lines when present, else the first user prompt, truncated.
- Prompts for the Feed tab are user lines that are real prompts; tool results and injected lines are excluded. A prompt's cost is the sum of events until the next prompt, subagents included.
- Slash commands are parsed from user prompts with the same rule as Cursor skills.

### Performance

The transcripts are large (2.1 GB on Tom's Mac, largest file 85 MB). Burnrate must never parse everything on each refresh.

- Only open files whose modification time is inside the selected window.
- Keep a persistent index in Application Support: per file, the byte offset read so far, its mtime, and the parsed events. On refresh, read only appended bytes; re-parse a file if it shrank or its mtime moved backwards.
- Parsing runs off the main actor.
- While the first pass runs, the status caption says "Indexing Claude Code · 12 of 71 sessions" and the menu bar shows `~$—`. Results appear progressively, newest sessions first.
- Claude Code deletes old transcripts. The index keeps parsed events for deleted files, so long windows don't undercount after deletion.

### Pricing

- `ClaudePricing` maps a model id to per-million-token prices for input, output, cache write, and cache read. The table is bundled as a resource JSON.
- Short aliases (`opus`, `sonnet`, `fable`) map to the current default model of that family.
- Unknown models: tokens are shown, cost is excluded, and a caption says "No price for <model>. Tokens shown, cost excluded". Never a silent $0.
- Models seen on Tom's Mac that need prices: `claude-opus-5-5`, `claude-opus-5`, `claude-sonnet-5-5`, `claude-sonnet-5`, `claude-fable-5-2`, `claude-haiku-5-5`, `claude-haiku-4-5-20251001`.

## Panel

```
┌────────────────────────────────────────────────────────┐
│ [  Cursor  $12.40  │  Claude Code  ~$31.20  ]          │
│                                                        │
│ ~$31.20 ⟳ [▲ ~$4.10 · 10m]      [🏆 Community][Today ▾]│
│ Estimated at API list prices · not your bill           │
│ ▁▂▁▃▅▇▅▂▁▁▂▃▅▂▁▁  12am ─────────────────────── now     │
│ 5h 62% · resets 3:40pm   wk 34% · resets Thu           │
│ [ Models │ Sessions │ Skills │ Feed │ Bench ]          │
└────────────────────────────────────────────────────────┘
```

- The switcher appears only when both sources are enabled and detected. Each segment shows that source's window figure. Selection persists in `@AppStorage("panelSource")`.
- The timeline picker is shared by both sources. The Community chip shows only in Cursor scope.
- In Claude Code scope, the Cursor included-pool rings are replaced by plan-limit gauges when limits are enabled, or by a token line ("48.2M tokens · 91% cache read") when they are not.
- The header hero follows the selected source.

### Per tab

| Surface | Claude Code behavior |
|---|---|
| Hero, sparkline, burn pill | Same, `~` style |
| Models | Same; `<synthetic>` hidden |
| Sessions | Session = `sessionId`, workspace = `cwd`, subtitle shows `gitBranch`; archive and cloud icons not shown |
| Session detail | Subagents from the `subagents/` folder; "Source path" points to the transcript file |
| Skills | Slash commands from user prompts |
| Feed | User prompts with attributed estimated cost |
| Bench | Unchanged |
| Community | Not shown |

### Estimated cost style

- One formatter, `MoneyFormat.estimated`, prefixes `~`. An environment value `\.costStyle` is set in `RootPanel`, like `\.blurSensitiveContent`, so rows don't need to know the source.
- Caption under the hero in Claude Code scope: "Estimated at API list prices · not your bill".
- Tooltip on hero and burn pill: "Estimated from local token counts × Anthropic list prices. Claude Code doesn't record charges. On Pro and Max you pay a flat rate; this is what the same usage would cost on the API."
- `EmptySpendView` and `UsageTimeWindow.emptyStateMessage` are parametrized by source: "No usage since midnight" for Claude Code.

## Plan limits (opt-in)

- Settings toggle under Claude Code: **Show plan limits**, off by default. Caption: "Reads your Claude Code login from Keychain to fetch your 5-hour and weekly limits. macOS may ask for permission once."
- When on, Burnrate reads the `Claude Code-credentials` Keychain item in memory only, never stores it, and calls the Claude Code usage endpoint once per refresh. The endpoint and response shape must be verified during implementation; if they can't be confirmed, the toggle ships hidden.
- The response gives utilization % and reset time for the 5-hour and weekly windows. They render as gauges in the header, reusing `percentGauge` with its "resets …" detail.
- Status-bar figures `5h %` and `wk %` become available when limits are on.
- Failure (expired token, network, unknown shape): gauges show "Limits unavailable"; spend still works. The token is never refreshed by Burnrate.
- This call does not consume model usage.

## Menu bar

Order: Cursor parts, then Claude Code parts.

```
Cursor only                🔥 $12.40
Both, default after update 🔥 $12.40
Both spends on             🔥 $12.40 · CC ~$31.20
Claude Code only           🔥 ~$31.20
With limits on             🔥 $12.40 · 5h 62% · wk 34%
```

- New `StatusBarFigures` entries: Claude Code spend (estimated), 5h limit, weekly limit. Defaults off. The `CC` tag appears only when Cursor window spend is also on, like the existing `C` / `O` rule.
- Settings → Status bar is grouped by source.
- The flame fills when any source crosses its spike threshold. The warning triangle shows when any enabled source has an error.
- **One-time hint:** the first time Claude Code is detected after the update, the panel shows "Burnrate now tracks Claude Code" with **Show in menu bar** (turns on Claude Code spend) and **Dismiss**. Stored as `claudeCodeHintDismissed`.

## Spike alerts

- `AnomalyMonitor` evaluates each source separately with the same threshold, window, and cooldown settings. Cooldown is tracked per source.
- Notification: title "Burnrate spike · Claude Code", body "~$12.40 estimated in the last 10 minutes". The Cursor notification is unchanged.

## Community

Unchanged and Cursor only. `UsageStore.communityAnalyticsEvents` keeps taking Cursor events only, so no Claude Code data is uploaded. The Community chip is hidden when Cursor is not enabled.

## "This billing"

Uses the shared `billingDayOfMonth` for both sources. Plan limits don't follow the timeline.

## Docs

README and CAPABILITIES are updated: Claude Code support, the estimated-cost explanation (replacing "not a hand-rolled price estimate"), local file access under `~/.claude`, and the opt-in Keychain read for limits. CHANGELOG gets a section for the release.

## Testing

Unit tests in `TokensTests` with JSONL fixtures:

- Dedupe of repeated `message.id`.
- Subagent files attributed to the parent session.
- Incremental read: appended bytes only; shrunk file re-parsed.
- Pricing, including aliases and unknown models excluded from cost.
- Window filtering by timestamp.
- Prompt and slash-command attribution.
- Status-bar figure formatting with the `CC` tag rule.
- Per-source anomaly cooldown.

## Out of scope

- A combined "All" view or total.
- Community for Claude Code.
- Per-source billing day.
- `CLAUDE_CONFIG_DIR` support.
- File watching instead of polling.
- `--status --source` CLI flag.
- Model-invoked Skill tool attribution.

## Open item

The bundled price table needs confirmed list prices for the seven models above before release.

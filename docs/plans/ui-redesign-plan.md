# Tokens → Burnrate: UI/UX Redesign Plan

Status: ready to implement
Audience: implementing agent (no prior context assumed)
Codebase: `/Users/tom/workspace/tokens` — Swift Package, SwiftUI `MenuBarExtra` app
Target: **macOS 26 (Tahoe)** — bump `Package.swift` from `.macOS(.v14)` to `.macOS(.v26)`
as part of Phase 1. This is a personal, locally-built app and the owner's Mac runs
macOS 26, so there is no back-compat concern. Build with Xcode 26 / the macOS 26 SDK
so system components adopt Liquid Glass automatically.

---

## 1. Context

The app is a macOS menu bar utility that shows today's Cursor AI spend (since local
midnight), a per-model / per-session breakdown, and fires a notification when spend
spikes. Read `CAPABILITIES.md` for full behavior. All UI currently lives in a single
file, `Sources/Tokens/App.swift` (~625 lines): `RootPanel`, `UsagePanel`, `ModelCard`,
`SessionRow`, `SettingsPanel`.

Data available per refresh (see `Models.swift`, `Aggregator.swift`):

- `UsageSnapshot`: `todayCostCents`, `recentCostCents` (rolling window), `models`,
  `eventCount`, `fetchedAt`
- `ModelUsage`: model name, cost, in/out/cache tokens, event count, `sessions`
- `SessionUsage`: conversationId, resolved name, workspace name, cost, tokens,
  event count, `lastTimestampMs`
- Raw `UsageEvent`s carry a `timestamp` (ms) — currently discarded after aggregation
  except for per-session `lastTimestampMs`. The redesign needs hourly buckets, so the
  aggregator must be extended (section 5).

## 2. Name

Rename the app **Burnrate**.

Rationale: the app's whole job is answering "how fast am I burning money in Cursor
right now?" — the hero number, the rolling-window hint, and the spike alert are all
burn-rate concepts. "Tokens" is generic and collides with what the app measures.

Rename scope (mechanical, do it last — Phase 4):

- Display name / bundle name in `scripts/package.sh` and `Resources` (Info.plist keys)
- User-facing strings ("Start Tokens when you sign in…", CLI output, notification title)
- README / CAPABILITIES headings
- Keep the Swift package/target name `Tokens` internally to avoid churn — renaming the
  executable target is optional and not worth the risk.

Rejected alternatives (for the record): Tally (too generic), Ticker (implies stocks),
Toll, Meter.

## 3. UX audit of the current UI (what's wrong)

Refer to the three screenshots in
`/Users/tom/.cursor/projects/Users-tom-workspace-tokens/assets/` if useful.

1. **No sense of trend.** A single "$106.98" number gives no idea whether today is
   normal or scary, or when the money was spent. Nothing shows the shape of the day.
2. **The recent-window burn ("$0.80 in last 10m") is buried** in a caption line even
   though it's the most actionable signal the app has.
3. **Model rows are visually flat.** Every model gets equal weight; you can't see at
   a glance that opus is 85% of spend. Costs are only comparable by reading numbers.
4. **Sessions are trapped under models.** To answer "which chat cost me $76?" you must
   expand each model. There is no cross-model session view, even though sessions are
   the thing users actually recognize.
5. **Token detail ("in 523.7K out 216.3K cache 82.7M") is noise at the top level.**
   It's precise but not decision-relevant; it crowds out cost share.
6. **Header wastes space**: "TODAY" label + big number + caption uses ~90pt to convey
   one number.
7. **Footer actions look like plain text links**; Quit sits next to Refresh with equal
   prominence.
8. **Settings** are fine functionally but visually homemade (custom −/+ buttons,
   green checkmark circle for a toggle instead of a `Toggle`).
9. **Error state** is a raw red string wedged between dividers.
10. **Menu bar item** is text-only; when auth breaks it shows `!` with no affordance.

## 4. Redesign specification

Panel stays a fixed-size `MenuBarExtra` window. New size: **380 × 520** (narrower and
taller than today's 440×480 — feels like a menu bar panel, not a dialog).

### 4.1 Menu bar item

- Label: small flame SF Symbol (`flame`) + `$12.40` monospaced-digit text.
  Menu bar items render as template images, so do not rely on color:
  - Normal: `flame` outline symbol.
  - Spike active (recent-window spend ≥ threshold): `flame.fill`.
  - Error: `exclamationmark.triangle` + last-known amount (keep showing the number;
    never replace it with just `!`).
- Optional (Settings → General): "Hide amount in menu bar" — icon only, for people
  who screen-share.

### 4.2 Panel layout — Usage view

Top to bottom:

**Header (hero zone)**

- Row 1: today total, `.system(size: 34, weight: .semibold, design: .rounded)`,
  monospaced digits, with a subtle count-up `contentTransition(.numericText())` when
  the value changes. Right-aligned in the same row: refresh spinner while loading.
- Row 2: burn pill — a capsule chip showing the rolling window spend, e.g.
  `▲ $0.80 · 10m`. Color-coded:
  - gray/secondary when < 25% of the alert threshold
  - orange when ≥ 25% of threshold
  - red when ≥ threshold (i.e., an alert would fire / has fired)
  Tooltip: "Spend in the last N minutes (your spike window)". Hidden when $0.
- Row 3: **24-hour sparkline** (Swift Charts `BarMark`, one bar per hour, midnight →
  now, current hour highlighted in accent color, past hours in
  `.secondary.opacity(0.5)`). Height ≈ 36pt, no axes, no labels except a faint "12am"
  / "now" caption at the ends. This is the single biggest UX addition: the shape of
  the day at a glance.
- Row 4 (caption, secondary): `Updated 8s ago · 79 events`.

**Scope tabs**

A segmented control (`Picker` with `.segmented` style, or two text tabs styled like
native pickers): **Models | Sessions**. Persist last selection in
`@AppStorage("panelTab")`.

**Models tab** (default)

Each model row (no card-in-card nesting, flat list rows with a hairline separator):

- Line 1: model name (medium weight, middle-truncated) …… cost (semibold,
  monospaced digits).
- Line 2: a **share bar** — thin (4pt) rounded horizontal bar whose filled fraction =
  this model's share of today's cost, in the accent color at 0.8/0.25 opacity.
  This replaces scanning numbers to compare models.
- Line 3 (caption, secondary): `3 sessions · 36 events · 740K tok` (total tokens
  summarized; detailed in/out/cache moves into the expanded state).
- Chevron on the right; clicking anywhere on the row expands it **with animation**
  (`withAnimation(.snappy)` — the current code explicitly disables animation; remove
  that).
- Expanded content: first a one-line token detail
  `in 523.7K · out 216.3K · cache read 82.7M · cache write 1.2M`, then the session
  rows (same component as the Sessions tab, indented, without the model chip).

**Sessions tab** (new)

A flat list of sessions aggregated **across models**, sorted by cost desc:

- Line 1: session display name …… cost.
- Line 2 (caption): workspace name (if any) · model chip(s) — show the top model
  name, and `+2` if the session used more than one model · relative last-activity
  time ("12m ago", from `lastTimestampMs`).
- Same 4pt share bar as model rows (share of today's total).
- Hovering shows the conversationId tooltip (keep existing `.help`).
- No expansion needed in v1.

**Footer**

- Left: gear icon button (Settings) — icon only, `.help("Settings")`.
- Center: nothing.
- Right: "Refresh" icon button (`arrow.clockwise`, ⌘R) and an overflow menu (`…`,
  `Menu`) containing **Open Cursor Dashboard** (link to
  `https://cursor.com/dashboard`) and **Quit** (⌘Q). Quit moves out of the
  always-visible row — it's a rare action.
- All footer buttons: `.buttonStyle(.borderless)`, secondary color, hover highlight.

### 4.3 States

- **Loading (first ever fetch):** skeleton — hero shows `$—.——` in tertiary color,
  sparkline area shows a redacted placeholder (`.redacted(reason: .placeholder)`).
- **Empty (fetched, $0):** friendly center state: flame outline symbol, "No spend
  since midnight", caption "Usage appears here as you work in Cursor."
- **Error:** replace the raw red text with a banner card at the top of the list area:
  yellow `exclamationmark.triangle` icon, one-line message, and a **Retry** button
  inline. Keep the last good snapshot visible below it (stale data > no data), with
  the "Updated…" caption switching to "Data from 3:02 PM (stale)".
- **Stale:** if `fetchedAt` is older than 3× the poll interval, show the updated
  caption in orange.

### 4.4 Settings view

Keep the in-panel back-navigation pattern, but rebuild the body with a native
`Form` + `.formStyle(.grouped)`:

- **Refresh**: `Picker` ("15s / 30s / 1m / 2m / 5m / 10m") instead of a stepper —
  nobody needs 15-second granularity across the whole range.
- **Spike alert**: keep steppers but use native `Stepper` with the value in the
  label; keep the live example sentence ("Alert when ≥ $10 is spent in 10 minutes.").
  Add a **Test notification** button (fires the notification path with a sample
  payload) so users can verify permission is granted.
- **General**: real `Toggle` for Launch at login; the new "Hide amount in menu bar"
  toggle.
- **About** section: app name + version, "Uses your local Cursor sign-in. Data may
  differ slightly from the official dashboard." and a link to the dashboard.

### 4.5 Liquid Glass adoption (macOS 26)

Targeting macOS 26 unlocks the Liquid Glass design language. Apply it selectively —
Apple's guidance is that glass belongs on floating controls at the top of the UI
hierarchy, **not** on content. Rules for this app:

**Gets glass:**

- **Burn pill** (header): `.glassEffect(.regular.tint(<state color>))` in a capsule —
  this is the app's signature control and the tint (gray/orange/red) reads through
  the vibrant glass treatment.
- **Footer buttons** (settings gear, refresh, overflow menu):
  `.glassEffect(.regular.interactive())` so they scale/shimmer on click like system
  toolbar buttons. Wrap the footer's buttons in a single `GlassEffectContainer`
  (glass cannot sample other glass; grouping is required for correct rendering and
  lets adjacent shapes blend).
- **Models | Sessions segmented control**: prefer the system `.segmented` picker,
  which picks up the new design automatically when compiled with the 26 SDK. Do not
  hand-roll a glass version unless the system one looks wrong inside the panel.

**Stays on standard backgrounds (no glass):** hero number, sparkline, model/session
list rows, settings form, error banner. These are content; keep them on
`.background`/`.quaternary` fills for legibility.

**Morphing (nice-to-have, Phase 3):** if usage ↔ settings navigation is rebuilt
anyway, coordinate the transition with `glassEffectID(_:in:)` on the footer
gear / settings back button inside a shared namespace so the control morphs between
the two views. Skip if it fights the `MenuBarPanelKeeper` behavior.

**Verify:** on macOS 26 the menu bar is fully transparent — check the menu bar label
(flame + amount) renders legibly on both light and dark wallpapers.

### 4.6 Motion & polish

- Numeric transitions: `.contentTransition(.numericText())` on hero and row costs.
- Expansion: `.snappy` spring; chevron rotation animated.
- Hover: rows get `.background(.quaternary.opacity(0.4))` highlight on hover
  (use `onHover` or `.hoverEffect`-equivalent for AppKit-hosted SwiftUI).
- Respect Reduce Motion (`@Environment(\.accessibilityReduceMotion)`): skip count-up
  and springs.
- All money strings: one shared formatter (`$1,234.56`, always 2 decimals); all token
  counts: one shared `K/M` formatter (already duplicated twice — consolidate).

## 5. Technical notes for the implementer

### Aggregator additions (`Aggregator.swift`, `Models.swift`)

- Add `hourlyCostCents: [Double]` (24 entries, index = hour of local day) to
  `UsageSnapshot`; fill it in the existing event loop from `event.timestampMs`.
- Add `sessionsAcrossModels: [SessionUsage]` to `UsageSnapshot`: aggregate by
  `sessionKey` across all models; extend `SessionUsage` with
  `models: [String]` (sorted by that session's per-model cost desc) for the model
  chips. Reuse the existing `SessionCatalog` enrichment for names/workspaces.
- No API or storage changes needed; everything derives from data already fetched.

### File structure (split `App.swift`)

```
Sources/Tokens/
  App.swift               // @main, MenuBarExtra scene, CLI --status only
  UI/RootPanel.swift      // routing usage <-> settings
  UI/UsagePanel.swift     // header, tabs, footer
  UI/SparklineView.swift  // Swift Charts hourly bars
  UI/ModelRow.swift
  UI/SessionRow.swift
  UI/StateViews.swift     // empty / error banner / skeleton
  UI/SettingsPanel.swift
  UI/Formatters.swift     // money + token formatting, relative time
```

### Constraints & gotchas

- `MenuBarPanelKeeper.keepOpen()` must keep being called on any interaction that
  could dismiss the panel (see existing call sites); preserve this in the new views.
- Building for macOS 26 requires the macOS 26 SDK (Xcode 26). Verify `swift build`
  uses it (`xcrun --show-sdk-version`). `glassEffect`, `GlassEffectContainer`, and
  `glassEffectID` are SwiftUI APIs available at deployment target 26 — no
  availability guards needed once the platform is `.v26`.
- The panel is an `LSUIElement` `MenuBarExtra(.window)`; there is no resizable
  window — keep every state within 380×520.
- Menu bar label: `MenuBarExtra` labels support `Image` + `Text` but colors are
  stripped to template rendering — encode state via symbol choice, not color.
- Swift Charts: `import Charts` is available (platform is macOS 14). If chart
  rendering inside the menu bar window misbehaves, fall back to a hand-rolled
  `HStack` of `RoundedRectangle` bars — visually identical at 36pt with no axes.
- Settings changes must not reset the poll timer incorrectly — check how
  `UsageStore` consumes `refreshIntervalSeconds` before switching to the picker.

### Verification

- `swift build` must pass.
- `bash scripts/package.sh --install --open` to smoke-test the real menu bar
  behavior (panel open/close, expansion clicks not dismissing the panel).
- CLI `--status` must still work (it bypasses the UI but shares formatters if you
  move them).
- Manually verify: empty state (set system clock forward or filter), error state
  (rename `state.vscdb` temporarily or force an invalid URL in a debug build).

## 6. Phases

Implement in order; each phase leaves the app shippable.

**Phase 1 — Structure & data.** Bump platform to `.macOS(.v26)` and confirm the
build uses the macOS 26 SDK. Split `App.swift` into the file layout above (pure
move, no visual change). Extend `Aggregator`/`UsageSnapshot` with hourly buckets and
cross-model sessions. Consolidate formatters. Acceptance: builds against the 26 SDK,
panel looks identical (modulo automatic system glass on chrome), snapshot exposes
new fields.

**Phase 2 — Usage panel redesign.** New header (hero + burn pill + sparkline +
caption), tabs, model rows with share bars, sessions tab, new footer with overflow
menu, animated expansion. Liquid Glass per section 4.5 (glass pill, interactive
glass footer buttons in a `GlassEffectContainer`). Acceptance: matches sections
4.2 and 4.5, all interactions keep the panel open, hover/expand animations work.

**Phase 3 — States & settings.** Skeleton, empty, error banner with retry, stale
indicator. Settings rebuilt as grouped Form with interval picker, native toggle,
test-notification button, About section, hide-amount toggle (+ menu bar label
support for it). Acceptance: matches sections 4.3–4.4.

**Phase 4 — Rename to Burnrate.** Section 2 scope. Acceptance: menu bar app shows
as Burnrate in Notification Center and `/Applications`, CLI prints unchanged format.

## 7. Out of scope (unchanged from v1)

Historical charts beyond today, billing-cycle quotas, team/admin API, notarized
distribution, onboarding flows.

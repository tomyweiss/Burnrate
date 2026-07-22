# Cloud session titles, location subtitle, and -dev install

**Date:** 2026-07-22  
**Status:** Approved for planning (pending final review)  
**PR goal:** Fix unnamed cloud agents, show a cloud icon, optional location subtitle for all sessions, and a parallel `Burnrate-dev` install path.

## Problem

Burnrate resolves session titles only from local Cursor IDE composer headers and CLI `store.db` files. Cloud / background agents use conversation IDs like `bc-774b4fb1-…`. Those IDs are not in the composer catalog, so the UI falls back to `Session bc-774b4`.

Cursor itself shows the real title (e.g. **Nightly scan vulnerabilities**) plus a cloud badge and `repo · branch`.

## Verification (local Cursor state)

On this Mac, Cursor stores cloud agents in:

`ItemTable` key prefix: `cloudAgentRepository.agents.<userId>`

Each entry is a JSON object with at least:

| Field | Example | Use |
|-------|---------|-----|
| `bcId` | `bc-774b4fb1-2274-5349-8448-dc4e1045764c` | Match `UsageEvent.conversationId` |
| `name` | `Nightly scan vulnerabilities` | Session display title |
| `repoUrl` | `github.com/drift-team/drift` | Location subtitle (repo) |
| `branchName` | `chore-DR-4740-fix-fixable-vulns` | Location subtitle (branch) |

Detection: treat a session as cloud when `conversationId` has a matching `bcId` in that catalog, or when the id starts with `bc-` (icon even if name not yet cached).

No new Cursor network API calls for this feature. Titles come from the same local `state.vscdb` Burnrate already reads.

## Goals

1. Show the real cloud agent name when present in local Cursor cache.
2. Show a cloud SF Symbol on cloud sessions only.
3. Keep primary subtitle as **model(s) · relative time** (and cost on the right as today).
4. Optional second subtitle for **all** sessions (settings-gated): workspace/worktree for local; `repo · branch` for cloud.
5. Support packaging/installing a side-by-side `-dev` app so contributors can test without overwriting production Burnrate.

## Non-goals

- Fetching cloud agent metadata from Cursor HTTP APIs.
- Changing spend aggregation or usage API decoding beyond enrichment fields.
- Notarization / production release signing changes.
- Renaming the production app or changing the production bundle id.

## Design

### 1. Session enrichment (`SessionCatalog` + models)

Extend `SessionMeta` / `SessionUsage`:

```swift
struct SessionMeta {
  let conversationId: String
  let name: String?
  let workspaceName: String?   // local workspace folder (existing)
  let isCloud: Bool            // new
  let repoName: String?        // new — short repo, e.g. drift-team/drift
  let branchName: String?      // new
}
```

Lookup order for a conversation id:

1. Existing IDE composer headers / `composerData:*`
2. Existing CLI `store.db` meta
3. **New:** scan `ItemTable` keys matching `cloudAgentRepository.agents.%`, parse JSON arrays, index by `bcId`

Cloud catalog wins for `name` / location when the id is a cloud agent (composer rarely has these ids). Merge: if cloud entry exists, set `isCloud = true`, fill `name` from `name`, `repoName` from normalized `repoUrl`, `branchName` from `branchName`.

`displayName` stays: prefer `name`, else `Session <first 8 of id>`.

Repo display helper: strip scheme/`github.com/` prefix from `repoUrl` so UI shows `drift-team/drift`.

### 2. Session row UI

Primary line: optional cloud icon + title | cost  
Share bar (unchanged)  
Primary subtitle: **model(s) · relative time** only (workspace moves out of this line)  
Secondary subtitle (if settings on and text non-empty): location string

```
☁ Nightly scan vulnerabilities              $1.29
███░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
composer-2.5 · 24 min ago
drift-team/drift · chore-DR-4740-fix-fixab…
```

Local with location setting on:

```
Traffic Light - Network Speed Indicators    $2.80
████████░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░
gpt-5.6-terra-high · 1 min ago
code
```

Cloud icon: SwiftUI `Image(systemName: "cloud")`, secondary style, before the title. Only when `session.isCloud`.

Location string:

- Cloud: join non-empty `repoName` and `branchName` with ` · `
- Local: `workspaceName` when present
- If empty → omit the second row entirely (even if setting is on)

### 3. Settings

New bool in `SettingsStore` (UserDefaults), default **off**:

- Key: `showLocationSubtitle`
- UI label: **Show location subtitle**
- Help: Extra row under each session: workspace, or repo · branch for cloud agents.

Toggle only controls visibility; enrichment always runs.

### 4. Dev install mode

Extend `scripts/package.sh` (and Makefile wrappers if present):

| Flag | Effect |
|------|--------|
| `--dev` | App name `Burnrate-dev`, bundle id `com.tomyweiss.burnrate.dev`, display name `Burnrate-dev` |

Also:

- Install destination `/Applications/Burnrate-dev.app` (does not touch `Burnrate.app`)
- Build output under `.build/App/Burnrate-dev.app`
- `--release` + `--dev` should be rejected (or ignored with error): release artifacts stay production-named
- Runtime: if bundle id ends with `.dev` (or Info.plist / compile flag), disable self-update checks so a -dev build never offers to replace itself from GitHub Releases

Document in README under a short “Local / contributor install” section:

```bash
bash scripts/package.sh --dev --install --open
```

### 5. Testing / verification

Manual:

1. With a known `bc-*` usage event that appears in `cloudAgentRepository`, Sessions tab shows real name + cloud icon.
2. Unknown / uncached `bc-*` still shows cloud icon and `Session bc-xxxx` fallback.
3. Local sessions unchanged except workspace no longer in the primary subtitle line; with setting on, workspace appears on the second line.
4. Setting off → no second line for anyone.
5. `package.sh --dev --install` yields `/Applications/Burnrate-dev.app` alongside production; both can launch (separate bundle ids).

Unit-testable pieces (preferred if the repo already has tests; otherwise add small pure helpers):

- `repoName` normalization from `repoUrl`
- Location string join rules
- Cloud id detection (`bc-` prefix / catalog hit)

## File touch list (expected)

- `Sources/Tokens/SessionCatalog.swift` — cloud agent repository lookup
- `Sources/Tokens/Models.swift` — `SessionUsage` / enrichment fields
- `Sources/Tokens/UI/SessionRow.swift` — icon + subtitle layout
- `Sources/Tokens/SettingsStore.swift` + `UI/SettingsPanel.swift` — toggle
- `Sources/Tokens/UpdateManager.swift` / `UpdateChecker.swift` — skip updates in -dev
- `scripts/package.sh`, `Makefile`, `README.md` — `--dev` path
- Optional: small helper tests if a test target exists

## Risks

- `cloudAgentRepository.agents.*` is a Cursor-internal cache shape; if Cursor renames the key, titles regress to fallback (icon still works via `bc-` prefix).
- Archived / other-user agents may still appear in usage events; if missing from the local list, name stays unresolved.
- Moving workspace out of the primary subtitle is a small UX change for existing users; the settings toggle restores it as a second line.

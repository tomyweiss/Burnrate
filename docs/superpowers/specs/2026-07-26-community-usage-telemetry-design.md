# Community usage telemetry — design

**Date:** 2026-07-26  
**Status:** Approved  
**Product:** Burnrate (macOS menu bar app)

## Problem

Burnrate is fully local today: no analytics, no third-party servers. Users want an optional way to compare their Cursor spend to an anonymous cohort (“what’s my rank?”) without exposing personal information.

## Goals

- Opt-in community ranking based on rolling **24h** spend.
- Show **rank + distribution** (count, median, percentiles, neighbors).
- Upload **spend + per-model cost breakdown** only — never session titles, prompts, workspaces, or Cursor account identity.
- **Share to view:** if you are not sharing, you cannot see others’ usage.
- Optional **fun nickname** (generator); blank = “Anonymous”.
- Backend on **Railway**.

## Non-goals (v1)

- User accounts, email, or OAuth
- Historical charts or multi-window ranking pickers
- Leaderboards by model as a primary view
- Strong anti-cheat / attestation beyond rate limits
- Sharing personal information of any kind

## Approach

**Snapshot upsert + aggregate read.**  
Each opted-in client periodically POSTs a 24h aggregate snapshot. The server upserts one row per participant and computes rank/distribution on read (with light stale-row filtering). Rejected alternatives: event-stream pipelines (too heavy) and client-only percentile math (weaker consistency / privacy controls).

## Privacy & consent

- **Default off.** Community content is locked until the user enables sharing.
- **Toggles:**
  - **Share usage** (required to view Community) — uploads anonymous aggregates.
  - **Nickname** (optional) — blank displays as “Anonymous”.
- **Identity:** random UUID (`participantId`) generated on first opt-in, stored only in local `UserDefaults`. Not derived from Cursor auth or machine name.
- **Never uploaded:** email, Cursor token/account, machine name, session names, prompts, workspace/repo/branch paths.
- **Opt-out:** turning Share off stops uploads and best-effort `DELETE`s the participant row on the server.

## Architecture

```
Burnrate (macOS)
  UsageStore refresh
       │
       ├─► (if sharing) CommunityClient.POST /v1/community/snapshot
       └─► (Community tab visible) CommunityClient.GET /v1/community/rank
                    │
                    ▼
         Railway: community-api + Postgres
```

### Upload payload

```json
{
  "participantId": "uuid",
  "nickname": "cobalt-fox",
  "windowHours": 24,
  "spendCents": 1240,
  "models": [
    { "name": "claude-4-sonnet", "spendCents": 800 }
  ]
}
```

`nickname` may be `null` or omitted.

### Rank response

```json
{
  "participantCount": 312,
  "rank": 47,
  "yourSpendCents": 1240,
  "medianSpendCents": 890,
  "p25SpendCents": 320,
  "p75SpendCents": 2100,
  "leaderboardNear": [
    { "rank": 45, "nickname": "pine-otter", "spendCents": 1310 },
    { "rank": 47, "nickname": "cobalt-fox", "spendCents": 1240, "isYou": true },
    { "rank": 49, "nickname": null, "spendCents": 1180 }
  ]
}
```

Other clients never receive another participant’s `participantId`. Null nicknames render as “Anonymous”.

### Backend (Railway)

- **Stack:** TypeScript HTTP API (Hono) + Postgres, in-repo as `community-api/`, deployed as its own Railway service.
- **Table `participants`:** `id` (UUID PK), `nickname` (nullable text), `spend_cents_24h` (int), `model_breakdown` (JSONB), `updated_at` (timestamptz).
- **Endpoints:**
  - `POST /v1/community/snapshot` — upsert by `participantId`
  - `GET /v1/community/rank?participantId=` — returns cohort stats only if that participant exists and is fresh (enforces share-to-view)
  - `DELETE /v1/community/me` — JSON body `{ "participantId": "…" }`; deletes that row
- **Auth (v1):** no accounts; client-generated UUID; rate-limit by IP + id.
- **Client config:** production API base URL as a build-time constant; no client secrets in v1.
- **Stale handling:** on read, ignore rows with `updated_at` older than **36 hours**. Optional later: scheduled cleanup job.

## UI

### Placement

New **Community** tab alongside Models / Sessions / Skills / Bench.

### Locked (not sharing)

- Short explanation of anonymous 24h share + mutual gate
- Primary CTA: **Enable sharing**
- Note that opt-out deletes server data

### Sharing (layout B)

- Nickname row: current name (or Anonymous), **Shuffle** (fun generator), **Clear**
- Hero: **24h spend** (left) + **rank / cohort size** (right)
- Distribution continuum: your position on a $0 → max (or high percentile) bar, with median labeled
- **Near you:** up to 2 above + you + 2 below (clamped at edges)
- Footer affordance to stop sharing

### Nickname generator

Local adjective + animal word lists (e.g. `cobalt-fox`, `amber-newt`). Shuffle replaces the current nickname; Clear sets null/Anonymous. Never treated as verified identity.

## Cohort rules

| Rule | Behavior |
|------|----------|
| Minimum cohort | If fewer than **5** fresh participants, show “Not enough sharers yet” — no ranks |
| Freshness | Only rows updated within **36h** |
| Ranking metric | Rolling **24h** spend (cents), descending |
| Ties | Competition ranking (1, 2, 2, 4) |
| $0 spend | Still participates; ranks with other zeros |
| Upload failure | Sharing remains on locally; soft error + retry; do not invent ranks |
| Client version | Send `clientVersion` header; no hard block in v1 |

## Client integration

- **SettingsStore:** `shareCommunityUsage`, `communityParticipantId`, `communityNickname`
- **CommunityClient:** snapshot / rank / delete
- **Upload cadence:** on Enable sharing, immediately POST a snapshot (so rank works right away); thereafter after successful usage refresh, throttled to at most ~every 5 minutes while sharing is on
- **Payload source:** always compute a **rolling last-24h** aggregate for Community, independent of the user’s timeline preset (Today / 7d / billing). Per-model costs only — strip anything session/prompt related
- **NicknameGenerator:** pure local helper

## Testing

- **Unit:** competition-rank / ties; nickname generator; payload builder excludes session/prompt fields
- **API:** upsert → rank → delete; min-cohort gate; stale exclusion; share-to-view rejection when id missing/stale
- **Manual:** opt-in → appear in near-you → shuffle nickname → opt-out removes server row and locks tab

## Open follow-ups (post-v1)

- Stronger participant attestation if the cohort grows
- Optional historical windows (today / 7d / billing)
- Cohort model-mix summary on the Community tab

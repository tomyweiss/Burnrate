# Community data collection & daily analytics — design

**Date:** 2026-08-04  
**Status:** Draft (awaiting approval)  
**Product:** Burnrate (macOS menu bar app) + `community-api` (Railway)

## Summary

Burnrate is local-first. The only data that leaves the device goes to our self-hosted `community-api` on Railway, and only under explicit rules below.

This document lists **everything we collect today**, **everything we never collect**, and **what we propose to add** for operator analytics — queryable via Postgres only, never via the public HTTP API.

The proposal is organised around the questions we cannot currently answer. The largest gap is not spend detail (we measure spend well enough to rank a cohort on it) but **lifecycle**: we have no way to tell whether the sharer base is growing, whether a new sharer returns on day 7, or how many people quietly opt back out. Retention, churn, and engagement are therefore Tier 1; deeper spend and token analytics ride along as Tier 2.

---

## Principles

| Principle | Rule |
|-----------|------|
| Opt-in spend sharing | Usage aggregates upload only when the user enables **Share usage** |
| Share to view | Cohort rank/near-you requires an active, fresh participant row |
| No PII | Never upload email, Cursor token, machine name, session titles, prompts, workspace/repo paths |
| Anonymous identity | `participantId` is a random UUID in local UserDefaults — not derived from Cursor auth |
| Operator analytics | Historical daily tables are **write-only from the API**; **never returned** by any public route |
| Failure telemetry | Error reports are separate from community sharing; no session/prompt content |
| **Counts, not content** | Every analytics field is a number, a bounded enum, or a count keyed by an **allow-listed** name. No free-text field originating from user data may be added — no skill names, workspace names, file paths, or error strings in the analytics path |
| **Low cardinality** | Each new dimension makes a participant row more distinctive. Prefer buckets over raw values (e.g. hour-of-day bucket, not a precise local timestamp); reject any field whose value space is effectively unbounded |
| **Untrusted input** | The snapshot endpoint is unauthenticated. Every number in an analytics row is client-asserted and unverified. Values are bounded on write and treated as untrusted on read |

---

## What we currently collect

### 1. Community snapshot (`POST /v1/community/snapshot`)

**When:** User has **Share usage** on. On enable-sharing, then after each successful usage refresh (throttled ~5 min).

**Upload payload (client → server):**

| Field | Type | Description |
|-------|------|-------------|
| `participantId` | UUID | Anonymous client-generated id |
| `nickname` | string \| null | Display name: Cursor profile name, random adjective-animal, or null (Anonymous) |
| `previousNickname` | string \| null | Sent during renames; server reconciles old → new on same participant row |
| `windowHours` | int | Always `24` |
| `spendCents` | int | **Rolling last 24 hours** total spend (cents) |
| `models` | array | Per-model spend for the **same rolling 24h window**: `[{ name, spendCents }]` |
| `interactionStats` | object \| null | **Lifetime cumulative** counts since last reset (see below) |
| `interactionStats.panelOpens` | int | Panel opens while sharing was enabled |
| `interactionStats.tabChanges` | map | Tab/route keys → count (e.g. `models`, `sessions`, `skills`, `feed`, `bench`, `settings`, `community`, `usage`, `changelog`) |
| `clientVersion` | string | App version, e.g. `0.0.25` or `0.0.25-dev` |

**HTTP headers:** `clientVersion` (short form) on all community requests.

**Source on client:** Computed from Cursor usage events in the last 24h only. Stripped to `{ timestamp, model, costCents }` — no session ids, prompts, or titles in the upload path.

---

### 2. Server table: `participants` (current snapshot)

Updated on every snapshot POST. Used by **`GET /v1/community/rank`** for cohort ranking.

| Column | Type | Description |
|--------|------|-------------|
| `id` | UUID PK | Same as `participantId` |
| `nickname` | text | Current display name |
| `nickname_history` | JSONB | Prior nicknames after reconciled renames, e.g. `["cobalt-fox"]` |
| `spend_cents_24h` | int | Rolling 24h total (replaced each upload) |
| `model_breakdown` | JSONB | Rolling 24h per-model spend (replaced each upload — **not accumulated over time**) |
| `interaction_stats` | JSONB | Latest lifetime cumulative `panelOpens` + `tabChanges` |
| `client_version` | text | Last seen app version |
| `updated_at` | timestamptz | Last snapshot time; rows older than **36h** excluded from rank |

**Important:** `model_breakdown` and `spend_cents_24h` reflect only the **current rolling 24h window**, not calendar-day history and not cumulative lifetime spend.

---

### 3. Rank response (`GET /v1/community/rank?participantId=`)

**When:** User has sharing on and requests community rank (Community tab).

**Returned to client (public API — this is all end users ever see from others):**

| Field | Description |
|-------|-------------|
| `participantCount` | Fresh participants in cohort |
| `rank` | Requester's competition rank by 24h spend |
| `yourSpendCents` | Requester's rolling 24h spend |
| `medianSpendCents`, `p25SpendCents`, `p75SpendCents`, `maxSpendCents` | Cohort distribution |
| `leaderboardNear[]` | Up to 2 above + you + 2 below: `{ rank, nickname, spendCents, isYou? }` |
| `notEnoughParticipants` | Legacy flag (min cohort removed; usually false) |

**Not returned:** `participantId` of other users, `model_breakdown`, `interaction_stats`, `nickname_history`, daily history, failure logs.

---

### 4. Failure reports (`POST /v1/client/failures`)

**When:** Fire-and-forget on errors (usage fetch, community, updates). **Does not require Share usage to be on.**

| Field | Type | Description |
|-------|------|-------------|
| `source` | string | `usage` \| `community` \| `updates` \| `app` |
| `category` | string | `network` \| `api` \| `auth` \| `decode` \| `validation` \| `unknown` |
| `message` | string | Error description (max 2000 chars); **no stack traces with local paths by default** |
| `clientVersion` | string | App version |
| `participantId` | UUID \| omitted | Included when community context is known |
| `context` | map \| omitted | Optional key/value strings (max 20 keys, 500 chars/value) |

**Server table: `failure_logs`**

| Column | Description |
|--------|-------------|
| `id`, `created_at` | Auto |
| `source`, `category`, `message` | From payload |
| `client_version`, `participant_id` | From payload |
| `context` | JSONB |

**Not exposed** via any GET endpoint today.

---

### 5. Delete on opt-out (`DELETE /v1/community/me`)

**When:** User turns off sharing.

Removes the `participants` row for that `participantId`. Does **not** currently delete `failure_logs` or (proposed) daily history rows.

---

### 6. Local-only data (never uploaded)

These stay on the Mac:

| Data | Used for |
|------|----------|
| Cursor access token | API auth (read from Cursor DB each refresh, never stored by Burnrate) |
| Session titles / chat names | Sessions tab display |
| Prompt text | Feed / session detail |
| Workspace / repo / branch paths | Session subtitles |
| Skill names (full list) | Skills tab |
| Billing cycle totals (`SpendSummary`) | Settings / header caption only |
| Menu bar preferences, timeline preset, spike settings | Local UX |
| Community rank cache | Offline display |

---

## What we never collect

- Email, name, or Cursor account id (unless user opts to use **Cursor display name** as nickname — that string only, not account id)
- Machine hostname or hardware ids
- Session / conversation UUIDs in community uploads
- Prompt content or session titles in community uploads
- File paths, git remotes, project names
- Raw usage event stream (only aggregates are uploaded)
- IP addresses stored in Postgres (rate limiting uses IP in memory only)

---

## Proposed additions: operator analytics

### Framing: start from the questions, not the columns

The v1 draft of this section was spend-heavy — daily totals, model mix, token volumes. That is the data we already understand best: `spend_cents_24h` is accurate enough to rank a cohort on it today.

What we have **zero** visibility into is whether Burnrate is actually used:

- We cannot tell how many people are sharing this week vs last week.
- We cannot tell whether a new sharer is still there on day 7.
- We cannot tell whether anyone who opted in ever opted back out, because opt-out is a hard `DELETE` and leaves no trace.
- We cannot compute a failure *rate*, because `failure_logs` records numerators with no denominator.

So the priority order below is lifecycle first, engagement second, spend depth third. Spend columns stay in the design, but they are not the reason to build this.

### Questions this design must answer

| # | Question | Category | Needs |
|---|----------|----------|-------|
| Q1 | How many participants are active per day / week? | Growth | Daily row existence |
| Q2 | Is the sharer base growing or flat? | Growth | `first_seen_at` per participant |
| Q3 | Of people who start sharing, how many are still sharing on day 1 / 7 / 30? | Retention | Install cohort + daily rows |
| Q4 | How many people opt back out, and how long do they last first? | Churn | Anonymous opt-out event |
| Q5 | Do people open the panel daily, or install it and forget it? | Engagement | Daily `panel_opens` |
| Q6 | Which tabs earn their existence? Which should be cut? | Engagement | Daily `tab_changes` |
| Q7 | How fast do users move to a new release, and how long do old versions linger? | Adoption | `client_version` per day |
| Q8 | Which settings do people actually change from defaults? | Adoption | Allow-listed `client_config` |
| Q9 | What fraction of usage refreshes fail, and did that get worse in a release? | Reliability | Attempt + failure counters |
| Q10 | How does spend evolve per user and per cohort over calendar days? | Spend | Daily spend + model mix |
| Q11 | Which models are gaining or losing share over time? | Spend | Daily model breakdown |
| Q12 | Are users benefiting from prompt caching? | Spend | Token counters |

### Priority tiers

| Tier | Scope | Rationale |
|------|-------|-----------|
| **Tier 1** | Daily row existence, `first_seen_at`, panel opens, tab changes, `client_version`, opt-out events | Answers Q1–Q7. This is the "is the app alive" tier and is the reason to ship |
| **Tier 2** | Daily spend, model breakdown, event/errored counts, billing-kind split, token counters | Answers Q10–Q12. Cheap to add once the row exists |
| **Tier 3** | Allow-listed `client_config`, refresh attempt/failure counters, hour-of-day activity buckets | Answers Q8–Q9. Useful, but each needs new client plumbing |
| **Deferred** | Per-session or per-prompt counts, skill invocation counts, dwell time per tab | Higher privacy cost or higher client complexity than current value justifies. See [Deferred signals](#deferred-signals-and-why) |

### Goals

1. **Server-side daily aggregation** — calendar-day history, not overwritten each upload  
2. **Lifecycle & retention** — install cohorts, active days, and a churn signal that survives opt-out deletion  
3. **Product engagement** — daily panel opens, tab usage, upload cadence, version adoption  
4. **Spend patterns** — daily totals, model mix, token volumes, billing-kind split  
5. **Reliability rates** — failures with a denominator  
6. **Operator access only** — direct Postgres queries; **zero public API exposure**

### Non-goals

- End-user history UI in the app  
- New HTTP GET routes for analytics  
- Any admin/read HTTP route, authenticated or otherwise (see [Why no admin API](#why-no-admin-api))  
- Cohort rank-over-time dashboards (can be derived later from daily spend if needed)  
- Backfilling days before deploy date  
- Cross-device identity resolution (see [Multi-device double counting](#data-quality-caveats))  

---

### New upload field: `dailyReports`

Appended to existing snapshot POST (same opt-in gate). Ranking fields unchanged.

### Two different windows coexist in one payload

This is the easiest thing to misread in this design, so it is stated explicitly:

| Fields | Window | Shape | Purpose |
|--------|--------|-------|---------|
| `spendCents`, `models`, `windowHours: 24` | **Rolling** — `[now − 24h, now]` | Overlapping | Cohort ranking (existing, unchanged) |
| `dailyReports[].*` | **Calendar day** — `[day 00:00 UTC, min(now, day end)]` | Partitioning | Analytics history (new) |

The new telemetry is **not** a 24-hour aggregation. It is midnight-to-now on a UTC calendar day, and that is the whole reason for a separate table.

A rolling window cannot be assembled into history. Samples taken at 10:00 and 14:00 each cover 24 hours that overlap by 20, so summing them double-counts, differencing them is meaningless, and there is no sequence of rolling samples that reconstructs "what happened on Tuesday". Calendar days partition time exactly once, which is what makes `SUM`, retention curves, and day-over-day comparison valid.

Both windows are computed from the same locally fetched events; the rolling one is kept verbatim so ranking behaviour does not change.

### Cadence

**This is not a once-a-day upload.** "Daily" describes the *aggregation window*, not the send frequency. `dailyReports` rides along on the existing snapshot, which fires after a successful usage refresh subject to the existing 5-minute upload throttle (`CommunityStore.uploadThrottle`). Each upload restates the totals **so far**, and the server replaces the affected rows.

| | |
|---|---|
| Send trigger | Successful usage refresh, then throttled |
| Effective interval | ~5 min while the app runs and sharing is on |
| Uploads per device per day | Up to ~288 (24h); ~96 for an 8-hour day |
| Rows written per device per day | **One** — every upload rewrites the same row |

This trades write amplification for self-healing: because each upload is a full restatement rather than a delta, dropped requests, crashes, and late-arriving usage events all correct themselves on the next upload, and no more than five minutes of data is ever at risk. The only field that accumulates instead of being replaced is `upload_count`, which consequently doubles as a proxy for **how long the app was actually running** that day — a stronger liveness signal than `panel_opens`, since it does not require the user to interact.

Decoupling the `dailyReports` cadence from the snapshot cadence (e.g. every 15–30 min plus a flush at UTC day rollover) would cut writes by ~5× and lose nothing but freshness, since intermediate writes are discarded anyway. Not worth doing at current scale — it is a throttle constant, changeable later with no schema impact.

```json
{
  "participantId": "…",
  "windowHours": 24,
  "spendCents": 1240,
  "models": [ … ],

  "dailyReports": [{
    "day": "2026-08-04",
    "spendCents": 890,
    "models": [
      { "name": "claude-4-sonnet", "spendCents": 600 },
      { "name": "gpt-4.1", "spendCents": 290 }
    ],

    "eventCount": 42,
    "onDemandCents": 600,
    "includedCents": 290,
    "erroredEventCount": 3,

    "tokenInput": 1200000,
    "tokenOutput": 450000,
    "tokenCacheRead": 800000,
    "tokenCacheWrite": 120000,

    "uniqueModels": 3,
    "topModel": "claude-4-sonnet",

    "peakHourUtc": 14,
    "activeHourCount": 6,
    "regionBucket": "americas",

    "panelOpens": 8,
    "tabChanges": {
      "models": 3,
      "sessions": 1,
      "skills": 0,
      "feed": 2,
      "bench": 0,
      "community": 2,
      "settings": 1,
      "usage": 0,
      "changelog": 0
    },

    "refreshAttempts": 210,
    "refreshFailures": 4,

    "nicknameSource": "cursor",

    "clientConfig": {
      "timelinePreset": "today",
      "refreshIntervalSeconds": 60,
      "anomalyThresholdDollars": 10,
      "anomalyWindowMinutes": 10,
      "hideAmountInMenuBar": false,
      "autoCheckForUpdates": true,
      "launchAtLogin": true,
      "hiddenTabs": ["bench"],
      "customTimezone": false,
      "billingDayOfMonth": 1
    }
  }],

  "interactionStats": { … },
  "clientVersion": "0.0.26"
}
```

**`day`:** UTC calendar date (`YYYY-MM-DD`). Client aggregates events with `timestamp` in `[day 00:00 UTC, min(now, day end)]`.

### Why an array: closing out finished days

`dailyReports` is an array of **1–2 entries** — the current UTC day, and yesterday when yesterday is still within the local event window. A single-object payload would have made every day's totals permanently truncated, for the following reason.

The client fetches `min(displayWindowStart, now − 24h)` worth of events (`CommunityPayloadBuilder.eventFetchStart`). Since "midnight UTC → now" is always ≤ 24 hours elapsed, a 24-hour fetch covers the current day **exactly, with zero margin**. That is sufficient to keep restating today, but it means a day is frozen at whatever was uploaded last before the UTC rollover — the client never revisits it, even though the events are still in the fetch window the next morning.

This is not a rare edge case. UTC midnight is 5pm US Pacific and 8pm US Eastern, squarely inside the working day for a large share of users. A user who stops working at 5:30pm Pacific permanently loses everything between their last upload and 5pm from that day's row, and the loss is invisible in the data.

**Resolution:**

| Change | Detail |
|--------|--------|
| Event fetch floor | Raise from 24h to **48h** so a full previous day is always available locally |
| Payload | Send `dailyReports` for today **and** yesterday |
| Server | Upsert each entry independently; replacement semantics make the restatement idempotent |
| Bound | Max 2 entries; each `day` must be today or yesterday UTC; duplicate days in one payload rejected |

The cost is one larger usage fetch. Because the upsert replaces rather than accumulates, the next morning's first upload simply overwrites yesterday's row with its true final total, and every day converges to a correct, closed value within 24 hours of ending.

**Residual gap:** a device offline for more than 48 hours still loses the tail of the day it stopped on. Extending the fetch further trades client cost for an increasingly rare correction; 48h is the point where the common case — laptop closed overnight — is fully covered.

**Engagement shift:** `interactionStats` on the snapshot remains **lifetime cumulative** on `participants` for backward compatibility. **`dailyReports[].panelOpens` / `tabChanges`** are **per UTC day**, which requires the client to retain the previous day's engagement counters until that day is closed out — a two-slot buffer, not a single counter.

### Notes on the new Tier 3 fields

**`peakHourUtc` / `activeHourCount`** answer "when do people burn tokens, and is it a burst or an all-day grind" — useful for interpreting spend, and for deciding whether a spike alert window of 10 minutes is sensible. Deliberately **not** a 24-slot histogram: a per-hour activity bitmap is ~16M distinct values and would make rows highly fingerprintable, which conflicts with the low-cardinality principle. Two small integers give most of the signal at a fraction of the entropy.

**`regionBucket`** is a **3-value enum** — `americas` | `emea` | `apac` — derived on the client from the system UTC offset and then discarded. It exists to make engagement metrics readable: a UTC day boundary cuts a US-evening working session in half, so without any regional signal, `activeHourCount` and per-day engagement read systematically lower for users west of UTC and there is no way to tell that apart from genuinely lighter usage.

Chosen over sending `utcOffsetMinutes` deliberately. The raw offset has ~30 distinct values and pins a user to a narrow band of longitude; three buckets carry nearly all of the interpretive value at roughly log₂(3) ≈ 1.6 bits, and cannot be sharpened later by combining it with other fields. The client must send the bucket, never the offset or the timezone identifier, so the coarsening happens before the data leaves the device rather than in the database.

**`refreshAttempts` / `refreshFailures`** are the denominator that `failure_logs` has always lacked. Today a spike in failure rows is unreadable — it could mean the app broke, or it could mean more people installed it. With attempts recorded per day, "0.4% of refreshes failed on 0.0.26 vs 0.1% on 0.0.25" becomes a one-line query and a release gate.

**`clientConfig`** is an **allow-listed, fixed-key** object. Every key is a boolean, a small integer, or a value from a closed enum; `hiddenTabs` is constrained to the known tab keys. The server rejects unknown keys rather than storing them, so a future client cannot silently widen what we collect. This answers "which settings do people change" — e.g. if nobody ever unhides `bench`, that is a signal to cut it, and if most users drop the refresh interval to 15s we have a load problem to plan for.

**Not sent by the client:** install date and active-day counts. The server derives those (see `first_seen_at` below) so they cannot be forged by a client and do not need to be maintained across reinstalls.

---

### New server table: `participant_daily_stats`

**Primary key:** `(participant_id, day)`  
**Retention:** No automatic purge, but **deleted on opt-out** — so this table is not a durable record of history. Aggregates that must survive deletion live in `daily_cohort_rollup`.  
**API access:** INSERT/UPDATE on snapshot only — **no SELECT in any HTTP handler**

| Column | Type | Category | Description |
|--------|------|----------|-------------|
| `participant_id` | UUID | — | FK to participants |
| `day` | DATE | — | UTC calendar day |
| `spend_cents` | INT | Spend | Total spend that day |
| `model_breakdown` | JSONB | Spend | `[{ name, spendCents }]` for the day |
| `event_count` | INT | Spend | Billable usage events that day |
| `on_demand_cents` | INT | Spend | Spend from usage-based events |
| `included_cents` | INT | Spend | Spend from included-allowance events |
| `errored_event_count` | INT | Spend | Non-charged error events that day |
| `token_input` | BIGINT | Spend | Sum input tokens |
| `token_output` | BIGINT | Spend | Sum output tokens |
| `token_cache_read` | BIGINT | Spend | Sum cache read tokens |
| `token_cache_write` | BIGINT | Spend | Sum cache write tokens |
| `unique_models` | INT | Spend | Distinct models used |
| `top_model` | TEXT | Spend | Highest-spend model name |
| `peak_hour_utc` | SMALLINT | Spend | UTC hour (0–23) with highest spend that day |
| `active_hour_count` | SMALLINT | Spend | Distinct UTC hours with any billable event |
| `region_bucket` | TEXT | Engagement | `americas` \| `emea` \| `apac` — coarse offset bucket for reading day-boundary skew |
| `panel_opens` | INT | Engagement | Panel opens that UTC day |
| `tab_changes` | JSONB | Engagement | Tab key → count for that day |
| `upload_count` | INT | Engagement | Server increments each snapshot touching this day |
| `client_version` | TEXT | Engagement | Last app version seen that day |
| `nickname_source` | TEXT | Engagement | `cursor` \| `random` \| `anonymous` at last upload |
| `refresh_attempts` | INT | Reliability | Usage refreshes attempted that day |
| `refresh_failures` | INT | Reliability | Usage refreshes that errored that day |
| `client_config` | JSONB | Adoption | Allow-listed settings snapshot at last upload |
| `updated_at` | TIMESTAMPTZ | — | Last upsert time |

**Upsert rule:** Each snapshot **replaces** that day's row with the latest client-computed day totals (idempotent — not additive), except `upload_count`, which the server increments. Replacement handles late events and re-uploads correctly; see [Data quality caveats](#data-quality-caveats) for what it does *not* handle.

**Write-side bounds (untrusted input):** the snapshot handler must reject or clamp out-of-range values rather than storing them, because this endpoint is unauthenticated:

| Field | Bound |
|-------|-------|
| `dailyReports` | Max **2** entries; duplicate `day` values in one payload rejected |
| `day` | Valid `YYYY-MM-DD`, within `[today − 2, today]` UTC — no backdating history |
| `models` | Max 50 entries, each `name` ≤ 64 chars (**currently unbounded — existing bug, see below**) |
| `spendCents`, `onDemandCents`, `includedCents` | Integer, `0 ≤ v ≤ 10_000_000` |
| token counters | Integer, `0 ≤ v ≤ 10_000_000_000` |
| `eventCount`, `erroredEventCount`, `panelOpens`, `refreshAttempts`, `refreshFailures` | Integer, `0 ≤ v ≤ 1_000_000` |
| `peakHourUtc` | Integer `0–23`; `activeHourCount` integer `0–24` |
| `regionBucket` | Exactly one of `americas`, `emea`, `apac` — any other value is dropped, **never** stored as free text |
| `tabChanges` | Max 32 keys, keys from the known tab set, values `0 ≤ v ≤ 1_000_000` |
| `clientConfig` | Fixed allow-list of keys; unknown keys dropped; enum values validated |

> **Pre-existing gap worth fixing alongside this work:** `validateSnapshot` currently accepts an **unbounded `models` array** (`community-api/src/routes.ts:70-77`), so a single POST can write an arbitrarily large JSONB blob, and there is no HTTP body-size limit configured on the Hono app. Adding a body limit plus the caps above is a prerequisite for storing this data forever.

**Indexes (suggested):**

- `(day)` — cohort-wide day queries  
- `(day, spend_cents DESC)` — top spenders per day  
- `(participant_id, day DESC)` — user timeline  
- `(day, client_version)` — version adoption per day  

---

### New column on `participants`: `first_seen_at`

| Column | Type | Description |
|--------|------|-------------|
| `first_seen_at` | TIMESTAMPTZ NOT NULL DEFAULT NOW() | Set on **INSERT only**, never updated |

One column, set server-side in the `ON CONFLICT` upsert's insert branch and deliberately excluded from the update branch. This is what makes install cohorts and retention curves possible (Q2, Q3), and it costs nothing.

Because it is server-assigned, it cannot be forged by a client. Note that it means "first seen sharing", not "installed" — we have no visibility into users who never opt in.

---

### New table: `optout_events` (anonymous churn signal)

**Purpose:** answer Q4 without retaining anything about the person who left.

Opt-out currently does a hard `DELETE` of the `participants` row, which is the right privacy behaviour and will stay. But it means churn is completely invisible: a participant who leaves is indistinguishable from one who never existed. That makes every retention number we compute optimistic by an unknown amount.

The fix is to record that *a* churn happened, with no way back to *who*:

| Column | Type | Description |
|--------|------|-------------|
| `id` | BIGSERIAL PK | Auto |
| `day` | DATE | UTC day of opt-out |
| `client_version` | TEXT | Version at opt-out |
| `days_active_bucket` | TEXT | `1`, `2-6`, `7-29`, `30+` — bucketed, not exact |
| `lifetime_days_shared_bucket` | TEXT | Same buckets, counted from daily rows before deletion |

**Deliberately absent:** `participant_id`, nickname, spend, timestamps finer than a day. The row is a tally mark, not a record. Bucketing tenure prevents re-joining a churn event to a deleted participant by matching an unusual exact lifetime.

Written inside the same transaction as `DELETE /v1/community/me`, before the participant and daily rows are removed.

---

### New table: `daily_cohort_rollup` (deletion-durable history)

**Purpose:** keep aggregate history correct even though per-participant rows get deleted on opt-out.

This is the tension the v1 draft did not resolve. It proposed both "retention: forever" and "delete daily rows on opt-out". Those are both right, but together they mean **history silently rewrites itself**: a chart of cohort spend for March, rendered in June, will be missing everyone who opted out in between, and it will not be obvious that the numbers moved.

A pre-aggregated, non-identifying rollup fixes this. Once a day is closed, its totals are frozen and no longer depend on rows that may later be deleted:

| Column | Type | Description |
|--------|------|-------------|
| `day` | DATE PK | UTC day |
| `active_participants` | INT | Participants with a daily row |
| `new_participants` | INT | Participants whose `first_seen_at` fell on this day |
| `total_spend_cents` | BIGINT | Cohort spend |
| `median_spend_cents` | INT | Cohort median |
| `total_events` | BIGINT | Billable events |
| `total_panel_opens` | BIGINT | Engagement |
| `version_mix` | JSONB | `{ "0.0.25": 12, "0.0.26": 40 }` |
| `model_mix` | JSONB | `{ "claude-4-sonnet": 91200, … }` cents per model |
| `optouts` | INT | From `optout_events` |
| `computed_at` | TIMESTAMPTZ | When the rollup ran |

**How it is written:** a lazy trigger, since there is no scheduler in `community-api` today. On the first snapshot of a new UTC day, close out any day older than the restatement window whose rollup row is missing. That is idempotent, needs no new infrastructure, and self-heals whenever any user uploads.

**It must lag the restatement window.** The obvious version — roll up *yesterday* — would freeze totals while devices are still restating that day, permanently baking in the truncation the two-day payload exists to fix. The rollup therefore closes out **day − 2**, one full day after the last legitimate restatement. Days more recent than that are computed on demand from `participant_daily_stats` and flagged as provisional.

This is the one place where the restatement window and the durable-history table interact, and getting it backwards would be silent: the rollup numbers would look plausible and simply be low.

**Retention:** forever. This table contains no participant identifiers at all, so keeping it indefinitely is compatible with the opt-out promise.

---

### What stays on `participants` (unchanged role)

| Column | Window | Public API |
|--------|--------|------------|
| `spend_cents_24h` | Rolling 24h | Exposed via rank (your spend + near-you totals) |
| `model_breakdown` | Rolling 24h | **Not** exposed via API |
| `interaction_stats` | Lifetime cumulative | **Not** exposed via API |
| `nickname`, `nickname_history` | Current | Nickname only in near-you list |

Daily history lives **only** in `participant_daily_stats`.

---

## Public API exposure matrix

| Data | Stored | Returned by `GET /rank` | Operator Postgres |
|------|--------|-------------------------|-------------------|
| Rolling 24h spend | `participants` | Yes (yours + near-you) | Yes |
| Near-you nicknames | `participants` | Yes | Yes |
| Rolling 24h model mix | `participants` | **No** | Yes |
| Lifetime interaction stats | `participants` | **No** | Yes |
| Nickname history | `participants` | **No** | Yes |
| Daily spend history | `participant_daily_stats` | **No** | Yes |
| Daily model mix | `participant_daily_stats` | **No** | Yes |
| Daily engagement | `participant_daily_stats` | **No** | Yes |
| Token aggregates | `participant_daily_stats` | **No** | Yes |
| Activity hour buckets | `participant_daily_stats` | **No** | Yes |
| Coarse region bucket | `participant_daily_stats` | **No** | Yes |
| Refresh reliability counters | `participant_daily_stats` | **No** | Yes |
| Client config adoption | `participant_daily_stats` | **No** | Yes |
| First-seen / install cohort | `participants.first_seen_at` | **No** | Yes |
| Opt-out tallies | `optout_events` | **No** | Yes |
| Cohort rollups | `daily_cohort_rollup` | **No** | Yes |
| Failure logs | `failure_logs` | **No** | Yes |

**Security rule:** No new GET routes. Rank handler must not JOIN or read `participant_daily_stats`, `optout_events`, `daily_cohort_rollup`, or `failure_logs`.

### Why no admin API

It is tempting to expose a `/v1/admin/stats` route once this data exists. Do not, at least not in this change.

`community-api` has **no authentication of any kind today** — no API key, no bearer token, no shared secret (`community-api/src/routes.ts`). Its only access control is "share to view": you must have a fresh participant row to read rank. Adding a read route over analytics data would mean building an auth story from scratch, and getting that wrong exposes every participant's daily history at once.

Postgres access via the Railway connection string is already authenticated, already restricted to the operator, and already sufficient. The cost of `psql` over a browser dashboard is a few minutes per query; the cost of a leaked admin route is the entire privacy promise. If a dashboard is wanted later, it should read the replica directly rather than via the public API service.

**Enforcement:** a test asserts that no route handler references the analytics tables, so a future route cannot quietly regress this.

---

## Data quality caveats

These do not block the design, but every query written against these tables must account for them, and they belong in the README next to the schema.

### Missing days are not zero days

If a user does not upload on a given day — laptop closed, sharing paused, app not running — there is **no row**, not a zero row. `AVG(spend_cents)` over the table therefore silently averages only active days and overstates typical spend. Any per-user time series must `LEFT JOIN` against a generated date series (see queries below).

### Today's row is always partial; older rows close within 48h

A day's row reflects state **as of the last upload that touched it**. Today's row is therefore always incomplete, and trend queries should exclude `CURRENT_DATE`.

Days before today are *usually* final but not immediately: the two-day restatement window (see [Why an array](#why-an-array-closing-out-finished-days)) means yesterday's row can still be corrected upward by a device that comes back online. Treat a day as settled once it is **two days old**; a report generated at 09:00 UTC covering "yesterday" may still grow.

Any device offline for more than 48 hours never closes out its final day, so a small downward bias remains on the last day each device was active. This is bounded and rare, but it means device-level totals are a lower bound rather than an exact figure.

### Daily counters must roll over lazily, not on a timer

The v1 draft said the client "resets local daily counters at midnight UTC". A scheduled reset is the wrong mechanism: a Mac asleep at midnight fires nothing, and the counter then leaks into the following day. Instead, persist counters **keyed by day string** and roll over on read — if the stored key is not today's UTC date, treat the counter as zero and overwrite. This is correct across sleep, quit, timezone change, and clock adjustment.

### Multi-device double counting

`participantId` is a per-device UUID in local UserDefaults, but usage events are fetched from the **Cursor account**, not the device. One person with a laptop and a desktop signed into the same Cursor account therefore appears as **two participants reporting the same spend**.

This already inflates cohort totals and distorts the leaderboard today — it is not introduced by this change — but analytics will make it visible, and "active participants" will read high relative to actual humans. Deduplicating would require a stable account-derived identifier, which directly contradicts the anonymous-identity principle. **Recommendation: accept it, document it, and treat participant counts as device counts.** Naming the columns and dashboards "devices" rather than "users" keeps the error from being forgotten.

### Every number is client-asserted

The snapshot endpoint is unauthenticated and the values are computed on the client. Nothing stops a crafted POST from writing whatever it likes for a self-chosen UUID. The write-side bounds above limit the blast radius to plausible-looking values; they do not make the data trustworthy. For operator analytics this is fine — outliers are visible and rare — but any decision that depends on precision should be sanity-checked against medians rather than sums.

### Timezone skew in engagement metrics

UTC days split a US-evening working session across two calendar days, which flattens per-day engagement for users west of UTC and makes "days active" read higher than a human would count.

`region_bucket` makes this **readable but not corrected**: the canonical `day` stays UTC, so a US user's Tuesday-evening session still lands partly in Wednesday. Segmenting or controlling by bucket is what turns "engagement looks lower in the Americas" into a known artifact instead of a false finding. Do not compare raw per-day engagement across buckets without accounting for it.

---

## Deferred signals (and why)

Signals that were considered and are deliberately **not** in this design:

| Signal | Available locally? | Why deferred |
|--------|--------------------|--------------|
| Skill / slash-command invocation counts | Yes (`UsageSnapshot.skills`) | Skill names can be user-authored and are effectively free text — a direct violation of the counts-not-content principle. Could return later as a count of *built-in* skills only, against a fixed allow-list |
| Session and prompt counts per day | Yes (`sessionsAcrossModels`, `prompts`) | Low cardinality and genuinely interesting ("how many concurrent agents do heavy users run"), but derived from the local prompt/session catalog, which is the most PII-adjacent code path in the app. Not worth touching until the Tier 1 questions are answered |
| Subagent usage ratio | Yes | Same reasoning as above; revisit once session counts are cleared |
| Dwell time per tab | No — would need new instrumentation | Requires timers and foreground/background tracking; meaningfully more client complexity than counting tab changes, for a marginal gain over Q6 |
| Spike/anomaly trigger counts | Partially (`isSpikeActive` is in-memory) | Would tell us whether the alerting feature works at all. Cheap once a daily counter exists — a good Tier 3 follow-up, not part of the first cut |
| Full 24-slot hour histogram | Yes | Rejected on fingerprinting grounds; replaced by `peakHourUtc` + `activeHourCount` |
| Raw usage-event stream | Yes | Never. Violates the aggregates-only principle outright |

---

## Example operator queries

### Tier 1: lifecycle and engagement

```sql
-- Q1: daily and rolling 7-day actives
-- Remember: "participants" means devices, not humans (see Data quality caveats).
SELECT d.day,
       COUNT(*) AS dau,
       (SELECT COUNT(DISTINCT w.participant_id)
          FROM participant_daily_stats w
         WHERE w.day BETWEEN d.day - 6 AND d.day) AS wau
FROM participant_daily_stats d
WHERE d.day < CURRENT_DATE          -- exclude today: partial
GROUP BY d.day
ORDER BY d.day DESC
LIMIT 30;

-- Q2 + Q3: day-N retention by install cohort
WITH cohort AS (
  SELECT id, first_seen_at::date AS cohort_day
  FROM participants
)
SELECT c.cohort_day,
       COUNT(DISTINCT c.id) AS cohort_size,
       COUNT(DISTINCT c.id) FILTER (WHERE d.day = c.cohort_day + 1) AS day_1,
       COUNT(DISTINCT c.id) FILTER (WHERE d.day = c.cohort_day + 7) AS day_7,
       COUNT(DISTINCT c.id) FILTER (WHERE d.day = c.cohort_day + 30) AS day_30
FROM cohort c
LEFT JOIN participant_daily_stats d ON d.participant_id = c.id
GROUP BY c.cohort_day
ORDER BY c.cohort_day DESC;

-- Q4: churn volume and how long people lasted before leaving
SELECT day, days_active_bucket, COUNT(*) AS optouts
FROM optout_events
WHERE day >= CURRENT_DATE - 90
GROUP BY day, days_active_bucket
ORDER BY day DESC;

-- Q5: install-and-forget detection — sharing but never opening the panel
SELECT participant_id,
       COUNT(*) AS days_with_data,
       SUM(panel_opens) AS total_opens
FROM participant_daily_stats
WHERE day >= CURRENT_DATE - 30
GROUP BY participant_id
HAVING SUM(panel_opens) = 0
ORDER BY days_with_data DESC;

-- Q6: which tabs earn their existence
SELECT key AS tab,
       SUM(value::int) AS changes,
       COUNT(DISTINCT participant_id) AS users_touching
FROM participant_daily_stats,
     jsonb_each_text(tab_changes)
WHERE day >= CURRENT_DATE - 30
GROUP BY key
ORDER BY changes DESC;

-- Q7: version adoption curve
SELECT day, client_version, COUNT(*) AS devices
FROM participant_daily_stats
WHERE day >= CURRENT_DATE - 21
GROUP BY day, client_version
ORDER BY day DESC, devices DESC;
```

### Tier 3: adoption and reliability

```sql
-- Q8: which settings people change from defaults
SELECT client_config->>'timelinePreset' AS preset,
       COUNT(DISTINCT participant_id) AS devices
FROM participant_daily_stats
WHERE day >= CURRENT_DATE - 7
GROUP BY 1
ORDER BY 2 DESC;

-- Q8: is anyone actually using the Bench tab?
SELECT COUNT(DISTINCT participant_id) FILTER
         (WHERE NOT (client_config->'hiddenTabs' ? 'bench')) AS bench_visible,
       COUNT(DISTINCT participant_id) AS total
FROM participant_daily_stats
WHERE day >= CURRENT_DATE - 7;

-- Q9: refresh failure rate by version — the release gate
SELECT client_version,
       SUM(refresh_attempts) AS attempts,
       SUM(refresh_failures) AS failures,
       ROUND(100.0 * SUM(refresh_failures)
             / NULLIF(SUM(refresh_attempts), 0), 3) AS failure_pct
FROM participant_daily_stats
WHERE day >= CURRENT_DATE - 14
GROUP BY client_version
ORDER BY failure_pct DESC;
```

### Tier 2: spend

```sql
-- Q10: one device's daily spend trend, gap-aware (missing days render as 0)
SELECT s.day,
       COALESCE(d.spend_cents, 0) AS spend_cents,
       COALESCE(d.event_count, 0) AS events,
       d.top_model
FROM generate_series(CURRENT_DATE - 30, CURRENT_DATE, '1 day') AS s(day)
LEFT JOIN participant_daily_stats d
       ON d.day = s.day AND d.participant_id = '…'
ORDER BY s.day;

-- Q10: cohort spend by day — prefer the rollup, which survives opt-out deletion
SELECT day, active_participants, total_spend_cents, median_spend_cents, optouts
FROM daily_cohort_rollup
ORDER BY day DESC
LIMIT 90;

-- Q11: model share over time
SELECT day,
       elem->>'name' AS model,
       SUM((elem->>'spendCents')::int) AS cents
FROM participant_daily_stats,
     jsonb_array_elements(model_breakdown) AS elem
WHERE day >= CURRENT_DATE - 30
GROUP BY day, model
ORDER BY day, cents DESC;

-- Q12: prompt cache effectiveness
SELECT day,
       SUM(token_cache_read) AS cache_read,
       SUM(token_input) AS fresh_input,
       ROUND(SUM(token_cache_read)::numeric
             / NULLIF(SUM(token_input + token_cache_read), 0), 3) AS cache_hit_ratio
FROM participant_daily_stats
WHERE day >= CURRENT_DATE - 30
GROUP BY day
ORDER BY day DESC;

-- Heavy vs light usage days
SELECT participant_id,
       COUNT(*) FILTER (WHERE spend_cents = 0) AS zero_days,
       COUNT(*) FILTER (WHERE spend_cents > 1000) AS heavy_days
FROM participant_daily_stats
GROUP BY participant_id;
```

---

## Client changes (implementation summary)

`CommunityCostEvent` currently strips events down to `{ timestampMs, model, costCents }` (`Sources/TokensCore/CommunityModels.swift:120-130`), so most Tier 2 fields need a wider — but still session-free — event struct.

| # | Change | Tier | Where |
|---|--------|------|-------|
| 1 | `CommunityDailyReport` model matching one `dailyReports` entry | 1 | `TokensCore/CommunityModels.swift` |
| 2 | Widen the upload event struct to carry `billingKind`, token counts, and hour-of-day — still **no** `conversationId`, prompt, or title | 2 | `TokensCore/CommunityModels.swift` |
| 3 | UTC-day aggregation in `CommunityPayloadBuilder` for **today and yesterday**, alongside the existing rolling 24h build | 1 | `TokensCore/CommunityPayloadBuilder.swift` |
| 3b | Raise the event fetch floor in `eventFetchStart` from 24h to **48h** so yesterday is always locally available to restate | 1 | `TokensCore/CommunityPayloadBuilder.swift` |
| 4 | `InteractionTracker`: persist counters **keyed by UTC day string**, retaining **two days** (today + yesterday) and rolling over lazily on read — not on a midnight timer (see caveats). Keep lifetime stats for `interactionStats` until deprecated | 1 | `Tokens/InteractionTracker.swift` |
| 5 | Refresh attempt/failure counters, same day-keyed storage | 3 | `Tokens/UsageStore.swift` |
| 6 | Allow-listed `clientConfig` builder reading from `SettingsStore` — explicit field list, never a dictionary dump of UserDefaults | 3 | `Tokens/SettingsStore.swift` |
| 6b | `regionBucket` derived from the system UTC offset and coarsened **before** upload; the offset itself is never included in a payload | 3 | `TokensCore/CommunityPayloadBuilder.swift` |
| 7 | Include `dailyReports` in the snapshot when sharing is on | 1 | `Tokens/CommunityStore.swift` |

`billingKind` already exists as `BillingKind` (`included` / `usageBased` / `errored` / `unknown`) and token counts already exist on `TokenUsage`, so items 2 and 3 are aggregation work rather than new parsing.

---

## Server changes (implementation summary)

| # | Change | Tier |
|---|--------|------|
| 1 | Migration: `participant_daily_stats` + indexes | 1 |
| 2 | Migration: `participants.first_seen_at`, set on insert only and excluded from the update branch of the upsert | 1 |
| 3 | Migration: `optout_events`, `daily_cohort_rollup` | 1 |
| 4 | Snapshot handler: validate each `dailyReports` entry against the bounds table, upsert each day's row in one transaction, increment `upload_count` per row | 1 |
| 5 | Add caps to existing snapshot validation — bound the `models` array and add a Hono body-size limit (pre-existing gap) | 1 |
| 6 | `DELETE /v1/community/me`: in one transaction, write the bucketed `optout_events` row, then delete daily rows and the participant | 1 |
| 7 | Lazy rollup: on the first snapshot of a new UTC day, close out the previous day into `daily_cohort_rollup` if absent | 1 |
| 8 | Confirm rank route unchanged; add a test asserting no handler reads the analytics tables | 1 |
| 9 | Document all tables, the caveats section, and the operator queries in `community-api/README.md`; also document the currently-undocumented `POST /v1/client/failures` | — |

Schema is applied by idempotent `CREATE TABLE IF NOT EXISTS` / `ADD COLUMN IF NOT EXISTS` in `migrate()` at boot, matching the existing pattern — no migration runner is being introduced.

---

## Open decisions

| Topic | Proposal | Notes |
|-------|----------|-------|
| Delete daily rows on opt-out | **Yes** — keep the privacy promise | Now safe for history, because `daily_cohort_rollup` preserves aggregates |
| Record anonymous opt-out events | **Yes** — bucketed tenure, no participant id | Without it, every retention number is optimistic by an unknown amount. Needs a sanity check that bucketing is coarse enough to prevent re-linking |
| Timezone signal | **Decided: 3-way `regionBucket`** (`americas` / `emea` / `apac`) | UTC-only days distort engagement for users far from UTC. A raw `utcOffsetMinutes` was rejected as unnecessarily precise for the question being asked; three buckets carry ~1.6 bits and still explain the skew. Bucketing happens **on the client** — the offset never leaves the device |
| `interactionStats` lifetime field | Keep for now | Daily engagement is the analytics source going forward; remove once a few releases have daily data |
| UTC vs user timezone for `day` | UTC for the canonical `day` | Consistent cohort comparisons; document in README regardless of the offset decision |
| Backfill | None — history starts at deploy date | Retention curves are unavailable until 30 days after deploy; `first_seen_at` defaults to `NOW()` for existing rows, so the first cohort is artificially large and should be excluded |
| Participant vs device naming | Name everything "devices" | Multi-device double counting is unfixable without breaking anonymity; naming keeps it from being forgotten |
| Rollup trigger mechanism | Lazy, on first snapshot of a new day | No scheduler exists in `community-api`; a cron/worker can replace it later without a schema change |

---

## Testing

The server currently has **no route-level or database tests at all** — `db.test.ts` only covers `buildPoolConfig`, and every other suite is pure unit logic. Landing analytics on top of that is how the "no public exposure" rule quietly breaks.

**Unit (client)**

- UTC day boundary aggregation, including events exactly on the boundary
- Yesterday's report is emitted and correct when the app starts after a UTC rollover, and matches what a device online at midnight would have reported — the truncation case this array exists to fix
- Engagement counters retain two days; the day-before-yesterday slot is discarded rather than merged into either day
- Day-keyed counter rollover: stale day key reads as zero; survives a simulated sleep across midnight and a timezone change
- Billing-kind split and token sums match the source events
- `clientConfig` contains exactly the allow-listed keys, and no unexpected key appears when a new setting is added
- `regionBucket` maps offsets to the correct bucket at each boundary, and no payload ever contains a raw offset or timezone identifier
- Payload includes `dailyReports` only when sharing is on, with at most two entries

**Unit (server)**

- Daily upsert idempotency: same payload twice yields one row per day with identical values and `upload_count` = 2
- A two-entry payload writes both days; a later restatement of yesterday **overwrites** rather than adding to it
- Payloads with 3+ entries, duplicate days, or a `day` outside the allowed range are rejected
- Bounds validation rejects or clamps each out-of-range field; oversized `models` array is rejected
- `clientConfig` with unknown keys stores only allow-listed keys
- Opt-out writes exactly one bucketed `optout_events` row and leaves no participant or daily rows
- Rollup computation is idempotent and matches a direct aggregate over the same day
- `first_seen_at` is unchanged by a second upsert

**Guard test (new)**

- Static assertion that no HTTP handler references `participant_daily_stats`, `optout_events`, `daily_cohort_rollup`, or `failure_logs` in a read path — the enforcement behind the security rule

**Integration**

- Snapshot with `dailyReports` → rows in `participant_daily_stats`; rank response byte-identical to before
- Rollup for a day is recomputed if that day is restated after the rollup already ran, so a late close-out is not silently lost
- Full lifecycle: first snapshot sets `first_seen_at` → several days of rows → opt-out → rollup totals for those days remain correct

---

## Related docs

- [Community usage telemetry (v1)](2026-07-26-community-usage-telemetry-design.md)

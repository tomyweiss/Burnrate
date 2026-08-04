# community-api

Anonymous community usage ranking API for Burnrate.

## Environment

- `DATABASE_URL` — Postgres connection string (required)
- `PORT` — set automatically by Railway for HTTP (do **not** copy from Postgres)
- `HTTP_PORT` — optional override if `PORT` is wrong (e.g. leaked `5432`)

## Endpoints (public)

- `POST /v1/community/snapshot` — upsert participant rolling-24h aggregate + optional `dailyReports` (operator analytics, write-only)
- `GET /v1/community/rank?participantId=` — cohort rank (share-to-view); **never reads analytics tables**
- `DELETE /v1/community/me` — opt-out: records anonymous churn tally, deletes participant + daily rows
- `POST /v1/client/failures` — client error telemetry (no session/prompt content)

Snapshot bodies are capped at 64 KiB. Rolling `models` arrays are capped at 50 entries.

## Operator analytics (Postgres only)

These tables are **never returned by any HTTP route**. Query via Railway Postgres / `psql` only.

| Table | Purpose |
|-------|---------|
| `participants` | Current rolling-24h snapshot + `first_seen_at` (install cohort) |
| `participant_daily_stats` | UTC calendar-day aggregates per device; replaced each upload, `upload_count` increments |
| `optout_events` | Anonymous churn tallies (no participant id) |
| `daily_cohort_rollup` | Durable cohort totals (survives opt-out deletion); closes **day − 2 UTC** |
| `failure_logs` | Client error reports |

See `docs/superpowers/specs/2026-08-04-community-daily-analytics-design.md` for field lists, caveats, and example SQL.

**Caveats (read before querying):**

- Missing upload days = no row (not zero spend)
- Today's row is partial; treat days `< 2 days old` as provisional
- `participant_id` means **device**, not human (multi-device double counting)
- All snapshot numbers are client-asserted and bounded on write, not cryptographically verified

## Development

```bash
npm install
npm run migrate
npm run dev
npm test
```

## Deploy (Railway)

1. Create a Railway project and add **Postgres** (`railway add -d postgres` or dashboard).
2. Deploy this service (`railway up`) with root directory `community-api`.
3. On the **API service** → Variables → add references from Postgres:
   - `DATABASE_URL` (private network), **or**
   - `DATABASE_PUBLIC_URL` (public proxy with SSL — use if internal fails)
4. Generate a public domain (Settings → Networking) on port **8080** (match Railway `PORT`).
5. Redeploy after linking `DATABASE_URL`.

Railway sets `PORT` automatically. The server binds `0.0.0.0` so healthchecks can reach `/health`.

### Port mismatch (502)

Railway sets `PORT` (often `8080`). Your public domain must route to **the same port** the app logs on:

```
community-api listening on http://0.0.0.0:8080
```

Dashboard → **community-api** → **Networking** → edit domain → set port to **8080** (not 3000).

| Symptom | Fix |
|---------|-----|
| `DATABASE_URL is required` in deploy logs | Reference Postgres `DATABASE_URL` on the API service |
| `Connection terminated unexpectedly` / SSL negotiate returns `H` | Postgres service was overwritten by the API image — redeploy Postgres from `postgres-ssl` source |
| SSL / connection errors | Railway `postgres-ssl` requires TLS on private + public URLs (`rejectUnauthorized: false`) |
| Build OK, healthcheck 503 | Check **Deploy Logs** (not build logs) for startup crash |

```bash
railway logs
curl https://YOUR-DOMAIN.up.railway.app/health
```

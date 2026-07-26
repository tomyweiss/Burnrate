# community-api

Anonymous community usage ranking API for Burnrate.

## Environment

- `DATABASE_URL` — Postgres connection string (required)
- `PORT` — set automatically by Railway for HTTP (do **not** copy from Postgres)
- `HTTP_PORT` — optional override if `PORT` is wrong (e.g. leaked `5432`)

## Endpoints

- `POST /v1/community/snapshot` — upsert participant 24h aggregate
- `GET /v1/community/rank?participantId=` — cohort rank (share-to-view)
- `DELETE /v1/community/me` — delete participant row

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

# Railway Postgres password rotation (F-04a)

The test fixture host was scrubbed from `community-api/src/db.test.ts`. If the old
`*.proxy.rlwy.net` hostname was ever committed to the public repo, rotate the
database password even though the committed password was the placeholder `secret`.

## Steps

1. Open the Railway project → Postgres service → **Variables** or **Connect**.
2. **Reset password** (or create a new user) and update `DATABASE_URL` on the
   community-api service.
3. Redeploy the API so it picks up the new connection string.
4. Optionally run `scripts/purge-community-api-history.sh` to remove
   `community-api/` from git history (rewrites all SHAs; coordinate before force-push).

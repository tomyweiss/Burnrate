import { Hono } from "hono";
import { bodyLimit } from "hono/body-limit";
import {
  deleteParticipantWithOptOut,
  fetchFreshParticipants,
  insertFailureLog,
  maybeCloseCohortRollups,
  participantExistsFresh,
  upsertDailyReport,
  upsertParticipant,
  type ParticipantRow,
} from "./db.js";
import { validateAndNormalizeSnapshot } from "./snapshot-validation.js";
import { normalizeFailure, validateFailure, type FailureBody } from "./failure-log.js";
import {
  MIN_COHORT,
  STALE_HOURS,
  buildRankResponse,
  isValidUUID,
  type SnapshotBody,
} from "./rank.js";

type RateKey = string;

const rateLimits = new Map<RateKey, { count: number; resetAt: number }>();
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 60;
const SNAPSHOT_BODY_LIMIT = 64 * 1024;

function rateLimitKey(ip: string, participantId?: string): RateKey {
  return participantId ? `${ip}:${participantId}` : ip;
}

function checkRateLimit(key: RateKey): boolean {
  const now = Date.now();
  const entry = rateLimits.get(key);
  if (!entry || now >= entry.resetAt) {
    rateLimits.set(key, { count: 1, resetAt: now + RATE_LIMIT_WINDOW_MS });
    return true;
  }
  if (entry.count >= RATE_LIMIT_MAX) return false;
  entry.count += 1;
  return true;
}

function clientIP(c: { req: { header: (name: string) => string | undefined } }): string {
  return (
    c.req.header("x-forwarded-for")?.split(",")[0]?.trim() ||
    c.req.header("x-real-ip") ||
    "unknown"
  );
}

function toParticipants(rows: ParticipantRow[]) {
  return rows.map((row) => ({
    id: row.id,
    nickname: row.nickname,
    spendCents: row.spend_cents_24h,
  }));
}

export function createApp() {
  const app = new Hono();

  app.use(
    "/v1/community/snapshot",
    bodyLimit({
      maxSize: SNAPSHOT_BODY_LIMIT,
      onError: (c) => c.json({ error: "Request body too large" }, 413),
    })
  );

  app.get("/health", (c) => c.json({ ok: true, v: 5 }));

  app.get("/ready", async (c) => {
    if (!process.env.DATABASE_URL) {
      return c.json({ ok: false, db: false, error: "DATABASE_URL not set" }, 503);
    }
    try {
      const { getPool } = await import("./db.js");
      await getPool().query("SELECT 1");
      return c.json({ ok: true, db: true });
    } catch (err) {
      console.error("ready check failed:", err);
      return c.json({ ok: false, db: false }, 503);
    }
  });

  app.post("/v1/community/snapshot", async (c) => {
    const ip = clientIP(c);
    let body: SnapshotBody;
    try {
      body = await c.req.json<SnapshotBody>();
    } catch {
      return c.json({ error: "Invalid JSON" }, 400);
    }

    const normalized = validateAndNormalizeSnapshot(body);
    if ("error" in normalized) {
      return c.json({ error: normalized.error }, 400);
    }

    if (!checkRateLimit(rateLimitKey(ip, normalized.snapshot.participantId))) {
      return c.json({ error: "Rate limit exceeded" }, 429);
    }

    const { snapshot } = normalized;

    await upsertParticipant(
      snapshot.participantId,
      snapshot.nickname,
      snapshot.spendCents,
      snapshot.models,
      {
        interactionStats: snapshot.interactionStats,
        clientVersion: snapshot.clientVersion,
        previousNickname: snapshot.previousNickname,
      }
    );

    for (const report of snapshot.dailyReports) {
      await upsertDailyReport(snapshot.participantId, report, snapshot.clientVersion);
    }

    await maybeCloseCohortRollups();

    return c.json({ ok: true });
  });

  app.get("/v1/community/rank", async (c) => {
    const ip = clientIP(c);
    const participantId = c.req.query("participantId");
    if (!participantId || !isValidUUID(participantId)) {
      return c.json({ error: "Invalid participantId" }, 400);
    }

    if (!checkRateLimit(rateLimitKey(ip, participantId))) {
      return c.json({ error: "Rate limit exceeded" }, 429);
    }

    const exists = await participantExistsFresh(participantId, STALE_HOURS);
    if (!exists) {
      return c.json({ error: "Share to view: participant not found or stale" }, 403);
    }

    const rows = await fetchFreshParticipants(STALE_HOURS);
    const response = buildRankResponse(toParticipants(rows), participantId);
    if (!response) {
      return c.json({ error: "Participant not found" }, 404);
    }

    return c.json(response);
  });

  app.delete("/v1/community/me", async (c) => {
    const ip = clientIP(c);
    let body: { participantId?: string };
    try {
      body = await c.req.json<{ participantId?: string }>();
    } catch {
      return c.json({ error: "Invalid JSON" }, 400);
    }

    if (!body.participantId || !isValidUUID(body.participantId)) {
      return c.json({ error: "Invalid participantId" }, 400);
    }

    if (!checkRateLimit(rateLimitKey(ip, body.participantId))) {
      return c.json({ error: "Rate limit exceeded" }, 429);
    }

    const deleted = await deleteParticipantWithOptOut(body.participantId);
    return c.json({ ok: true, deleted });
  });

  app.post("/v1/client/failures", async (c) => {
    const ip = clientIP(c);
    let body: FailureBody;
    try {
      body = await c.req.json<FailureBody>();
    } catch {
      return c.json({ error: "Invalid JSON" }, 400);
    }

    const validationError = validateFailure(body);
    if (validationError) {
      return c.json({ error: validationError }, 400);
    }

    if (!checkRateLimit(rateLimitKey(ip))) {
      return c.json({ error: "Rate limit exceeded" }, 429);
    }

    const normalized = normalizeFailure(body);
    await insertFailureLog({
      source: normalized.source,
      category: normalized.category,
      message: normalized.message,
      clientVersion: normalized.clientVersion,
      participantId: normalized.participantId,
      context: normalized.context,
    });

    return c.json({ ok: true });
  });

  return app;
}

export { MIN_COHORT, STALE_HOURS };

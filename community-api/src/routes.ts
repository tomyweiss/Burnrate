import { Hono } from "hono";
import {
  deleteParticipant,
  fetchFreshParticipants,
  participantExistsFresh,
  upsertParticipant,
  type ParticipantRow,
} from "./db.js";
import {
  MIN_COHORT,
  STALE_HOURS,
  WINDOW_HOURS,
  buildRankResponse,
  isValidUUID,
  type SnapshotBody,
} from "./rank.js";

type RateKey = string;

const rateLimits = new Map<RateKey, { count: number; resetAt: number }>();
const RATE_LIMIT_WINDOW_MS = 60_000;
const RATE_LIMIT_MAX = 60;

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

function validateSnapshot(body: SnapshotBody): string | null {
  if (!body.participantId || !isValidUUID(body.participantId)) {
    return "Invalid participantId";
  }
  if (typeof body.spendCents !== "number" || body.spendCents < 0) {
    return "Invalid spendCents";
  }
  if (body.windowHours !== undefined && body.windowHours !== WINDOW_HOURS) {
    return "windowHours must be 24";
  }
  if (!Array.isArray(body.models)) {
    return "models must be an array";
  }
  for (const model of body.models) {
    if (!model.name || typeof model.spendCents !== "number" || model.spendCents < 0) {
      return "Invalid model entry";
    }
  }
  if (body.nickname != null && typeof body.nickname !== "string") {
    return "Invalid nickname";
  }
  if (body.nickname && body.nickname.length > 64) {
    return "nickname too long";
  }
  return null;
}

export function createApp() {
  const app = new Hono();

  app.get("/health", (c) => c.json({ ok: true, v: 3 }));

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

    const validationError = validateSnapshot(body);
    if (validationError) {
      return c.json({ error: validationError }, 400);
    }

    if (!checkRateLimit(rateLimitKey(ip, body.participantId))) {
      return c.json({ error: "Rate limit exceeded" }, 429);
    }

    const nickname = body.nickname?.trim() || null;
    await upsertParticipant(
      body.participantId,
      nickname,
      Math.round(body.spendCents),
      body.models.map((m) => ({ name: m.name, spendCents: Math.round(m.spendCents) }))
    );

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

    const deleted = await deleteParticipant(body.participantId);
    return c.json({ ok: true, deleted });
  });

  return app;
}

export { MIN_COHORT, STALE_HOURS };

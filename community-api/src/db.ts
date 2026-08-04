import pg from "pg";
import {
  appendNicknameHistory,
  normalizeNickname,
  reconcileNickname,
} from "./nickname-reconcile.js";
import type { NormalizedDailyReport } from "./daily-analytics.js";
import { tenureBucket, utcDayString } from "./daily-analytics.js";
import { computeCohortRollup, dayToClose } from "./cohort-rollup.js";

const { Pool } = pg;

let pool: pg.Pool | null = null;

/**
 * Railway's postgres-ssl image requires TLS on all connections (including
 * `*.railway.internal`). Public proxy hosts also need TLS. Local Postgres does not.
 */
export function buildPoolConfig(connectionString: string): pg.PoolConfig {
  const isLocal = /localhost|127\.0\.0\.1/.test(connectionString);

  if (isLocal) {
    return {
      connectionString,
      connectionTimeoutMillis: 20_000,
      max: 10,
    };
  }

  return {
    connectionString,
    ssl: { rejectUnauthorized: false },
    connectionTimeoutMillis: 20_000,
    max: 10,
  };
}

export function getPool(): pg.Pool {
  if (!pool) {
    const url = process.env.DATABASE_URL ?? process.env.DATABASE_PUBLIC_URL ?? "";
    if (!url) {
      throw new Error("DATABASE_URL is required");
    }
    const host = url.match(/@([^/?]+)/)?.[1] ?? "unknown";
    console.log(`database host: ${host}`);
    pool = new Pool(buildPoolConfig(url));
  }
  return pool;
}

export async function migrate(): Promise<void> {
  const db = getPool();
  await db.query(`
    CREATE TABLE IF NOT EXISTS participants (
      id UUID PRIMARY KEY,
      nickname TEXT,
      spend_cents_24h INTEGER NOT NULL DEFAULT 0,
      model_breakdown JSONB NOT NULL DEFAULT '[]',
      interaction_stats JSONB NOT NULL DEFAULT '{"panelOpens":0,"tabChanges":{}}',
      client_version TEXT,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
    CREATE INDEX IF NOT EXISTS participants_updated_at_idx ON participants (updated_at);
    ALTER TABLE participants
      ADD COLUMN IF NOT EXISTS interaction_stats JSONB NOT NULL DEFAULT '{"panelOpens":0,"tabChanges":{}}';
    ALTER TABLE participants
      ADD COLUMN IF NOT EXISTS client_version TEXT;
    ALTER TABLE participants
      ADD COLUMN IF NOT EXISTS nickname_history JSONB NOT NULL DEFAULT '[]';
    ALTER TABLE participants
      ADD COLUMN IF NOT EXISTS first_seen_at TIMESTAMPTZ NOT NULL DEFAULT NOW();

    CREATE TABLE IF NOT EXISTS participant_daily_stats (
      participant_id UUID NOT NULL REFERENCES participants(id) ON DELETE CASCADE,
      day DATE NOT NULL,
      spend_cents INTEGER NOT NULL DEFAULT 0,
      model_breakdown JSONB NOT NULL DEFAULT '[]',
      event_count INTEGER NOT NULL DEFAULT 0,
      on_demand_cents INTEGER NOT NULL DEFAULT 0,
      included_cents INTEGER NOT NULL DEFAULT 0,
      errored_event_count INTEGER NOT NULL DEFAULT 0,
      token_input BIGINT NOT NULL DEFAULT 0,
      token_output BIGINT NOT NULL DEFAULT 0,
      token_cache_read BIGINT NOT NULL DEFAULT 0,
      token_cache_write BIGINT NOT NULL DEFAULT 0,
      unique_models INTEGER NOT NULL DEFAULT 0,
      top_model TEXT,
      peak_hour_utc SMALLINT NOT NULL DEFAULT 0,
      active_hour_count SMALLINT NOT NULL DEFAULT 0,
      region_bucket TEXT,
      panel_opens INTEGER NOT NULL DEFAULT 0,
      tab_changes JSONB NOT NULL DEFAULT '{}',
      upload_count INTEGER NOT NULL DEFAULT 0,
      client_version TEXT,
      nickname_source TEXT,
      refresh_attempts INTEGER NOT NULL DEFAULT 0,
      refresh_failures INTEGER NOT NULL DEFAULT 0,
      client_config JSONB NOT NULL DEFAULT '{}',
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      PRIMARY KEY (participant_id, day)
    );
    CREATE INDEX IF NOT EXISTS participant_daily_stats_day_idx ON participant_daily_stats (day);
    CREATE INDEX IF NOT EXISTS participant_daily_stats_day_spend_idx ON participant_daily_stats (day, spend_cents DESC);
    CREATE INDEX IF NOT EXISTS participant_daily_stats_participant_day_idx ON participant_daily_stats (participant_id, day DESC);
    CREATE INDEX IF NOT EXISTS participant_daily_stats_day_version_idx ON participant_daily_stats (day, client_version);

    CREATE TABLE IF NOT EXISTS optout_events (
      id BIGSERIAL PRIMARY KEY,
      day DATE NOT NULL,
      client_version TEXT,
      days_active_bucket TEXT NOT NULL,
      lifetime_days_shared_bucket TEXT NOT NULL
    );
    CREATE INDEX IF NOT EXISTS optout_events_day_idx ON optout_events (day);

    CREATE TABLE IF NOT EXISTS daily_cohort_rollup (
      day DATE PRIMARY KEY,
      active_participants INTEGER NOT NULL DEFAULT 0,
      new_participants INTEGER NOT NULL DEFAULT 0,
      total_spend_cents BIGINT NOT NULL DEFAULT 0,
      median_spend_cents INTEGER NOT NULL DEFAULT 0,
      total_events BIGINT NOT NULL DEFAULT 0,
      total_panel_opens BIGINT NOT NULL DEFAULT 0,
      version_mix JSONB NOT NULL DEFAULT '{}',
      model_mix JSONB NOT NULL DEFAULT '{}',
      optouts INTEGER NOT NULL DEFAULT 0,
      computed_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );

    CREATE TABLE IF NOT EXISTS failure_logs (
      id BIGSERIAL PRIMARY KEY,
      created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
      source TEXT NOT NULL,
      category TEXT NOT NULL,
      message TEXT NOT NULL,
      client_version TEXT,
      participant_id UUID,
      context JSONB NOT NULL DEFAULT '{}'
    );
    CREATE INDEX IF NOT EXISTS failure_logs_created_at_idx ON failure_logs (created_at DESC);
    CREATE INDEX IF NOT EXISTS failure_logs_source_idx ON failure_logs (source, created_at DESC);
  `);
}

export interface FailureLogInsert {
  source: string;
  category: string;
  message: string;
  clientVersion?: string | null;
  participantId?: string | null;
  context?: Record<string, string>;
}

export async function insertFailureLog(entry: FailureLogInsert): Promise<void> {
  const db = getPool();
  await db.query(
    `INSERT INTO failure_logs (
       source, category, message, client_version, participant_id, context
     )
     VALUES ($1, $2, $3, $4, $5, $6::jsonb)`,
    [
      entry.source,
      entry.category,
      entry.message,
      entry.clientVersion ?? null,
      entry.participantId ?? null,
      JSON.stringify(entry.context ?? {}),
    ]
  );
}

export interface ParticipantRow {
  id: string;
  nickname: string | null;
  nickname_history: string[];
  spend_cents_24h: number;
  model_breakdown: { name: string; spendCents: number }[];
  interaction_stats: { panelOpens: number; tabChanges: Record<string, number> };
  client_version: string | null;
  updated_at: Date;
}

export interface ParticipantUpsertExtras {
  interactionStats?: { panelOpens: number; tabChanges: Record<string, number> } | null;
  clientVersion?: string | null;
  previousNickname?: string | null;
}

export async function fetchParticipantById(id: string): Promise<ParticipantRow | null> {
  const db = getPool();
  const result = await db.query<ParticipantRow>(
    `SELECT id, nickname, nickname_history, spend_cents_24h, model_breakdown, interaction_stats, client_version, updated_at
     FROM participants
     WHERE id = $1`,
    [id]
  );
  return result.rows[0] ?? null;
}

export async function upsertParticipant(
  id: string,
  nickname: string | null,
  spendCents: number,
  modelBreakdown: { name: string; spendCents: number }[],
  extras: ParticipantUpsertExtras = {}
): Promise<void> {
  const db = getPool();
  const interactionStats = extras.interactionStats ?? null;
  const clientVersion = extras.clientVersion ?? null;
  const previousNickname = extras.previousNickname ?? null;

  const existing = await fetchParticipantById(id);
  let nicknameHistory = existing?.nickname_history ?? [];

  if (existing && previousNickname != null) {
    const reconciliation = reconcileNickname({
      currentNickname: existing.nickname,
      nextNickname: nickname,
      previousNickname,
    });

    if (reconciliation.mismatch) {
      console.warn(
        `nickname reconciliation mismatch for ${id}: expected ${normalizeNickname(previousNickname)}, found ${normalizeNickname(existing.nickname)}, applying ${normalizeNickname(nickname)}`
      );
    }

    if (reconciliation.historyEntry) {
      nicknameHistory = appendNicknameHistory(nicknameHistory, reconciliation.historyEntry);
    }
  }

  if (interactionStats || clientVersion) {
    await db.query(
      `INSERT INTO participants (
         id, nickname, nickname_history, spend_cents_24h, model_breakdown, interaction_stats, client_version, first_seen_at, updated_at
       )
       VALUES ($1, $2, $3::jsonb, $4, $5::jsonb, $6::jsonb, $7, NOW(), NOW())
       ON CONFLICT (id) DO UPDATE SET
         nickname = EXCLUDED.nickname,
         nickname_history = EXCLUDED.nickname_history,
         spend_cents_24h = EXCLUDED.spend_cents_24h,
         model_breakdown = EXCLUDED.model_breakdown,
         interaction_stats = COALESCE(EXCLUDED.interaction_stats, participants.interaction_stats),
         client_version = COALESCE(EXCLUDED.client_version, participants.client_version),
         updated_at = NOW()`,
      [
        id,
        nickname,
        JSON.stringify(nicknameHistory),
        spendCents,
        JSON.stringify(modelBreakdown),
        JSON.stringify(interactionStats ?? { panelOpens: 0, tabChanges: {} }),
        clientVersion,
      ]
    );
    return;
  }

  await db.query(
    `INSERT INTO participants (id, nickname, nickname_history, spend_cents_24h, model_breakdown, first_seen_at, updated_at)
     VALUES ($1, $2, $3::jsonb, $4, $5::jsonb, NOW(), NOW())
     ON CONFLICT (id) DO UPDATE SET
       nickname = EXCLUDED.nickname,
       nickname_history = EXCLUDED.nickname_history,
       spend_cents_24h = EXCLUDED.spend_cents_24h,
       model_breakdown = EXCLUDED.model_breakdown,
       updated_at = NOW()`,
    [id, nickname, JSON.stringify(nicknameHistory), spendCents, JSON.stringify(modelBreakdown)]
  );
}

export async function upsertDailyReport(
  participantId: string,
  report: NormalizedDailyReport,
  clientVersion: string | null
): Promise<void> {
  const db = getPool();
  await db.query(
    `INSERT INTO participant_daily_stats (
       participant_id, day, spend_cents, model_breakdown, event_count,
       on_demand_cents, included_cents, errored_event_count,
       token_input, token_output, token_cache_read, token_cache_write,
       unique_models, top_model, peak_hour_utc, active_hour_count, region_bucket,
       panel_opens, tab_changes, upload_count, client_version, nickname_source,
       refresh_attempts, refresh_failures, client_config, updated_at
     )
     VALUES (
       $1, $2::date, $3, $4::jsonb, $5,
       $6, $7, $8,
       $9, $10, $11, $12,
       $13, $14, $15, $16, $17,
       $18, $19::jsonb, 1, $20, $21,
       $22, $23, $24::jsonb, NOW()
     )
     ON CONFLICT (participant_id, day) DO UPDATE SET
       spend_cents = EXCLUDED.spend_cents,
       model_breakdown = EXCLUDED.model_breakdown,
       event_count = EXCLUDED.event_count,
       on_demand_cents = EXCLUDED.on_demand_cents,
       included_cents = EXCLUDED.included_cents,
       errored_event_count = EXCLUDED.errored_event_count,
       token_input = EXCLUDED.token_input,
       token_output = EXCLUDED.token_output,
       token_cache_read = EXCLUDED.token_cache_read,
       token_cache_write = EXCLUDED.token_cache_write,
       unique_models = EXCLUDED.unique_models,
       top_model = EXCLUDED.top_model,
       peak_hour_utc = EXCLUDED.peak_hour_utc,
       active_hour_count = EXCLUDED.active_hour_count,
       region_bucket = EXCLUDED.region_bucket,
       panel_opens = EXCLUDED.panel_opens,
       tab_changes = EXCLUDED.tab_changes,
       upload_count = participant_daily_stats.upload_count + 1,
       client_version = EXCLUDED.client_version,
       nickname_source = EXCLUDED.nickname_source,
       refresh_attempts = EXCLUDED.refresh_attempts,
       refresh_failures = EXCLUDED.refresh_failures,
       client_config = EXCLUDED.client_config,
       updated_at = NOW()`,
    [
      participantId,
      report.day,
      report.spendCents,
      JSON.stringify(report.models),
      report.eventCount,
      report.onDemandCents,
      report.includedCents,
      report.erroredEventCount,
      report.tokenInput,
      report.tokenOutput,
      report.tokenCacheRead,
      report.tokenCacheWrite,
      report.uniqueModels,
      report.topModel,
      report.peakHourUtc,
      report.activeHourCount,
      report.regionBucket,
      report.panelOpens,
      JSON.stringify(report.tabChanges),
      clientVersion,
      report.nicknameSource,
      report.refreshAttempts,
      report.refreshFailures,
      JSON.stringify(report.clientConfig),
    ]
  );
}

export async function maybeCloseCohortRollups(now = new Date()): Promise<void> {
  const db = getPool();
  const closeDay = dayToClose(now);

  const dailyRows = await db.query<{
    participant_id: string;
    spend_cents: number;
    event_count: number;
    panel_opens: number;
    model_breakdown: { name: string; spendCents: number }[];
    client_version: string | null;
  }>(
    `SELECT participant_id, spend_cents, event_count, panel_opens, model_breakdown, client_version
     FROM participant_daily_stats
     WHERE day = $1::date`,
    [closeDay]
  );

  const newParticipants = await db.query<{ count: string }>(
    `SELECT COUNT(*)::text AS count
     FROM participants
     WHERE first_seen_at::date = $1::date`,
    [closeDay]
  );

  const optouts = await db.query<{ count: string }>(
    `SELECT COUNT(*)::text AS count FROM optout_events WHERE day = $1::date`,
    [closeDay]
  );

  const rollup = computeCohortRollup({
    day: closeDay,
    dailyRows: dailyRows.rows,
    newParticipants: Number(newParticipants.rows[0]?.count ?? 0),
    optouts: Number(optouts.rows[0]?.count ?? 0),
    now,
  });

  await db.query(
    `INSERT INTO daily_cohort_rollup (
       day, active_participants, new_participants, total_spend_cents, median_spend_cents,
       total_events, total_panel_opens, version_mix, model_mix, optouts, computed_at
     )
     VALUES ($1::date, $2, $3, $4, $5, $6, $7, $8::jsonb, $9::jsonb, $10, $11)
     ON CONFLICT (day) DO UPDATE SET
       active_participants = EXCLUDED.active_participants,
       new_participants = EXCLUDED.new_participants,
       total_spend_cents = EXCLUDED.total_spend_cents,
       median_spend_cents = EXCLUDED.median_spend_cents,
       total_events = EXCLUDED.total_events,
       total_panel_opens = EXCLUDED.total_panel_opens,
       version_mix = EXCLUDED.version_mix,
       model_mix = EXCLUDED.model_mix,
       optouts = EXCLUDED.optouts,
       computed_at = EXCLUDED.computed_at`,
    [
      rollup.day,
      rollup.active_participants,
      rollup.new_participants,
      rollup.total_spend_cents,
      rollup.median_spend_cents,
      rollup.total_events,
      rollup.total_panel_opens,
      JSON.stringify(rollup.version_mix),
      JSON.stringify(rollup.model_mix),
      rollup.optouts,
      rollup.computed_at,
    ]
  );
}

export async function deleteParticipantWithOptOut(id: string): Promise<boolean> {
  const db = getPool();
  const client = await db.connect();
  try {
    await client.query("BEGIN");
    const participant = await client.query<{ client_version: string | null; first_seen_at: Date }>(
      `SELECT client_version, first_seen_at FROM participants WHERE id = $1`,
      [id]
    );
    if ((participant.rowCount ?? 0) === 0) {
      await client.query("ROLLBACK");
      return false;
    }

    const dailyCount = await client.query<{ count: string }>(
      `SELECT COUNT(DISTINCT day)::text AS count FROM participant_daily_stats WHERE participant_id = $1`,
      [id]
    );
    const daysActive = Number(dailyCount.rows[0]?.count ?? 0);
    const firstSeen = participant.rows[0].first_seen_at;
    const lifetimeDays = Math.max(
      daysActive,
      Math.floor((Date.now() - firstSeen.getTime()) / 86_400_000) + 1
    );

    await client.query(
      `INSERT INTO optout_events (day, client_version, days_active_bucket, lifetime_days_shared_bucket)
       VALUES ($1::date, $2, $3, $4)`,
      [
        utcDayString(new Date()),
        participant.rows[0].client_version,
        tenureBucket(daysActive),
        tenureBucket(lifetimeDays),
      ]
    );

    await client.query(`DELETE FROM participant_daily_stats WHERE participant_id = $1`, [id]);
    const deleted = await client.query(`DELETE FROM participants WHERE id = $1`, [id]);
    await client.query("COMMIT");
    return (deleted.rowCount ?? 0) > 0;
  } catch (error) {
    await client.query("ROLLBACK");
    throw error;
  } finally {
    client.release();
  }
}

export async function deleteParticipant(id: string): Promise<boolean> {
  return deleteParticipantWithOptOut(id);
}

export async function fetchFreshParticipants(staleHours = 36): Promise<ParticipantRow[]> {
  const db = getPool();
  const result = await db.query<ParticipantRow>(
    `SELECT id, nickname, nickname_history, spend_cents_24h, model_breakdown, interaction_stats, client_version, updated_at
     FROM participants
     WHERE updated_at >= NOW() - ($1::text || ' hours')::interval
     ORDER BY spend_cents_24h DESC, updated_at ASC`,
    [staleHours]
  );
  return result.rows;
}

export async function participantExistsFresh(id: string, staleHours = 36): Promise<boolean> {
  const db = getPool();
  const result = await db.query(
    `SELECT 1 FROM participants
     WHERE id = $1 AND updated_at >= NOW() - ($2::text || ' hours')::interval`,
    [id, staleHours]
  );
  return (result.rowCount ?? 0) > 0;
}

export async function closePool(): Promise<void> {
  if (pool) {
    await pool.end();
    pool = null;
  }
}

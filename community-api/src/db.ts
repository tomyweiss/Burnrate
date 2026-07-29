import pg from "pg";

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
  `);
}

export interface ParticipantRow {
  id: string;
  nickname: string | null;
  spend_cents_24h: number;
  model_breakdown: { name: string; spendCents: number }[];
  interaction_stats: { panelOpens: number; tabChanges: Record<string, number> };
  client_version: string | null;
  updated_at: Date;
}

export interface ParticipantUpsertExtras {
  interactionStats?: { panelOpens: number; tabChanges: Record<string, number> } | null;
  clientVersion?: string | null;
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

  if (interactionStats || clientVersion) {
    await db.query(
      `INSERT INTO participants (
         id, nickname, spend_cents_24h, model_breakdown, interaction_stats, client_version, updated_at
       )
       VALUES ($1, $2, $3, $4::jsonb, $5::jsonb, $6, NOW())
       ON CONFLICT (id) DO UPDATE SET
         nickname = EXCLUDED.nickname,
         spend_cents_24h = EXCLUDED.spend_cents_24h,
         model_breakdown = EXCLUDED.model_breakdown,
         interaction_stats = COALESCE(EXCLUDED.interaction_stats, participants.interaction_stats),
         client_version = COALESCE(EXCLUDED.client_version, participants.client_version),
         updated_at = NOW()`,
      [
        id,
        nickname,
        spendCents,
        JSON.stringify(modelBreakdown),
        JSON.stringify(interactionStats ?? { panelOpens: 0, tabChanges: {} }),
        clientVersion,
      ]
    );
    return;
  }

  await db.query(
    `INSERT INTO participants (id, nickname, spend_cents_24h, model_breakdown, updated_at)
     VALUES ($1, $2, $3, $4::jsonb, NOW())
     ON CONFLICT (id) DO UPDATE SET
       nickname = EXCLUDED.nickname,
       spend_cents_24h = EXCLUDED.spend_cents_24h,
       model_breakdown = EXCLUDED.model_breakdown,
       updated_at = NOW()`,
    [id, nickname, spendCents, JSON.stringify(modelBreakdown)]
  );
}

export async function deleteParticipant(id: string): Promise<boolean> {
  const db = getPool();
  const result = await db.query(`DELETE FROM participants WHERE id = $1`, [id]);
  return (result.rowCount ?? 0) > 0;
}

export async function fetchFreshParticipants(staleHours = 36): Promise<ParticipantRow[]> {
  const db = getPool();
  const result = await db.query<ParticipantRow>(
    `SELECT id, nickname, spend_cents_24h, model_breakdown, interaction_stats, client_version, updated_at
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

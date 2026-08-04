export function median(values: number[]): number {
  if (values.length === 0) return 0;
  const sorted = [...values].sort((a, b) => a - b);
  const mid = Math.floor(sorted.length / 2);
  if (sorted.length % 2 === 0) {
    return Math.round((sorted[mid - 1] + sorted[mid]) / 2);
  }
  return sorted[mid];
}

export function buildModelMix(
  reports: { model_breakdown: { name: string; spendCents: number }[] }[]
): Record<string, number> {
  const mix: Record<string, number> = {};
  for (const report of reports) {
    for (const model of report.model_breakdown) {
      mix[model.name] = (mix[model.name] ?? 0) + model.spendCents;
    }
  }
  return mix;
}

export function buildVersionMix(reports: { client_version: string | null }[]): Record<string, number> {
  const mix: Record<string, number> = {};
  for (const report of reports) {
    const version = report.client_version ?? "unknown";
    mix[version] = (mix[version] ?? 0) + 1;
  }
  return mix;
}

export interface CohortRollupInput {
  day: string;
  dailyRows: {
    participant_id: string;
    spend_cents: number;
    event_count: number;
    panel_opens: number;
    model_breakdown: { name: string; spendCents: number }[];
    client_version: string | null;
  }[];
  newParticipants: number;
  optouts: number;
  now?: Date;
}

export function computeCohortRollup(params: CohortRollupInput) {
  const spends = params.dailyRows.map((row) => row.spend_cents);
  return {
    day: params.day,
    active_participants: params.dailyRows.length,
    new_participants: params.newParticipants,
    total_spend_cents: spends.reduce((sum, value) => sum + value, 0),
    median_spend_cents: median(spends),
    total_events: params.dailyRows.reduce((sum, row) => sum + row.event_count, 0),
    total_panel_opens: params.dailyRows.reduce((sum, row) => sum + row.panel_opens, 0),
    version_mix: buildVersionMix(params.dailyRows),
    model_mix: buildModelMix(params.dailyRows),
    optouts: params.optouts,
    computed_at: params.now ?? new Date(),
  };
}

export function dayToClose(now = new Date()): string {
  const close = new Date(Date.UTC(now.getUTCFullYear(), now.getUTCMonth(), now.getUTCDate()));
  close.setUTCDate(close.getUTCDate() - 2);
  return close.toISOString().slice(0, 10);
}

export const KNOWN_TAB_KEYS = new Set([
  "models",
  "sessions",
  "skills",
  "feed",
  "bench",
  "community",
  "settings",
  "usage",
  "changelog",
]);

export const REGION_BUCKETS = new Set(["americas", "emea", "apac"]);

export const NICKNAME_SOURCES = new Set(["cursor", "random", "anonymous"]);

export const TIMELINE_PRESETS = new Set(["today", "last24h", "last7d", "thisBilling", "custom"]);

export const MAX_MODELS = 50;
export const MAX_MODEL_NAME = 64;
export const MAX_SPEND = 10_000_000;
export const MAX_TOKENS = 10_000_000_000;
export const MAX_COUNTER = 1_000_000;
export const MAX_DAILY_REPORTS = 2;

export interface ModelSpend {
  name: string;
  spendCents: number;
}

export interface DailyReportBody {
  day: string;
  spendCents: number;
  models: ModelSpend[];
  eventCount: number;
  onDemandCents: number;
  includedCents: number;
  erroredEventCount: number;
  tokenInput: number;
  tokenOutput: number;
  tokenCacheRead: number;
  tokenCacheWrite: number;
  uniqueModels: number;
  topModel?: string | null;
  peakHourUtc: number;
  activeHourCount: number;
  regionBucket: string;
  panelOpens: number;
  tabChanges: Record<string, number>;
  refreshAttempts: number;
  refreshFailures: number;
  nicknameSource: string;
  clientConfig: Record<string, unknown>;
}

export interface NormalizedDailyReport {
  day: string;
  spendCents: number;
  models: ModelSpend[];
  eventCount: number;
  onDemandCents: number;
  includedCents: number;
  erroredEventCount: number;
  tokenInput: number;
  tokenOutput: number;
  tokenCacheRead: number;
  tokenCacheWrite: number;
  uniqueModels: number;
  topModel: string | null;
  peakHourUtc: number;
  activeHourCount: number;
  regionBucket: string | null;
  panelOpens: number;
  tabChanges: Record<string, number>;
  refreshAttempts: number;
  refreshFailures: number;
  nicknameSource: string;
  clientConfig: Record<string, unknown>;
}

function clampInt(value: unknown, min: number, max: number, fallback = 0): number {
  if (typeof value !== "number" || !Number.isFinite(value)) return fallback;
  const rounded = Math.round(value);
  return Math.min(max, Math.max(min, rounded));
}

function isValidDay(day: string, now = new Date()): boolean {
  if (!/^\d{4}-\d{2}-\d{2}$/.test(day)) return false;
  const parsed = Date.parse(`${day}T00:00:00.000Z`);
  if (Number.isNaN(parsed)) return false;
  const today = utcDayString(now);
  const yesterday = utcDayString(new Date(now.getTime() - 86_400_000));
  return day === today || day === yesterday;
}

export function utcDayString(date: Date): string {
  return date.toISOString().slice(0, 10);
}

export function validateModels(models: unknown): string | null {
  if (!Array.isArray(models)) return "models must be an array";
  if (models.length > MAX_MODELS) return "models array too large";
  for (const model of models) {
    if (!model || typeof model !== "object") return "Invalid model entry";
    const entry = model as ModelSpend;
    if (typeof entry.name !== "string" || !entry.name.trim()) return "Invalid model entry";
    if (entry.name.length > MAX_MODEL_NAME) return "model name too long";
    if (typeof entry.spendCents !== "number" || entry.spendCents < 0 || entry.spendCents > MAX_SPEND) {
      return "Invalid model entry";
    }
  }
  return null;
}

/** Lenient rolling-24h model list: truncate, clamp, and skip bad entries (old app versions). */
export function sanitizeModels(models: unknown): { models: ModelSpend[] } | { error: string } {
  if (!Array.isArray(models)) return { error: "models must be an array" };

  const sanitized: ModelSpend[] = [];
  for (const model of models.slice(0, MAX_MODELS)) {
    if (!model || typeof model !== "object") continue;
    const entry = model as ModelSpend;
    if (typeof entry.name !== "string" || !entry.name.trim()) continue;
    if (typeof entry.spendCents !== "number" || !Number.isFinite(entry.spendCents) || entry.spendCents < 0) {
      continue;
    }
    sanitized.push({
      name: entry.name.trim().slice(0, MAX_MODEL_NAME),
      spendCents: clampInt(entry.spendCents, 0, MAX_SPEND),
    });
  }

  return { models: sanitized };
}

/** Clamp rolling-24h spend; reject only when missing or negative. */
export function normalizeRollingSpend(spendCents: unknown): number | null {
  if (typeof spendCents !== "number" || !Number.isFinite(spendCents) || spendCents < 0) {
    return null;
  }
  return clampInt(spendCents, 0, MAX_SPEND);
}

export function sanitizeClientConfig(raw: unknown): Record<string, unknown> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const input = raw as Record<string, unknown>;
  const output: Record<string, unknown> = {};

  if (typeof input.timelinePreset === "string" && TIMELINE_PRESETS.has(input.timelinePreset)) {
    output.timelinePreset = input.timelinePreset;
  }
  if (typeof input.refreshIntervalSeconds === "number") {
    output.refreshIntervalSeconds = clampInt(input.refreshIntervalSeconds, 15, 600);
  }
  if (typeof input.anomalyThresholdDollars === "number") {
    output.anomalyThresholdDollars = clampInt(input.anomalyThresholdDollars, 1, 100);
  }
  if (typeof input.anomalyWindowMinutes === "number") {
    output.anomalyWindowMinutes = clampInt(input.anomalyWindowMinutes, 1, 60);
  }
  if (typeof input.hideAmountInMenuBar === "boolean") {
    output.hideAmountInMenuBar = input.hideAmountInMenuBar;
  }
  if (typeof input.autoCheckForUpdates === "boolean") {
    output.autoCheckForUpdates = input.autoCheckForUpdates;
  }
  if (typeof input.launchAtLogin === "boolean") {
    output.launchAtLogin = input.launchAtLogin;
  }
  if (typeof input.customTimezone === "boolean") {
    output.customTimezone = input.customTimezone;
  }
  if (typeof input.billingDayOfMonth === "number") {
    output.billingDayOfMonth = clampInt(input.billingDayOfMonth, 1, 31);
  }
  if (Array.isArray(input.hiddenTabs)) {
    output.hiddenTabs = input.hiddenTabs
      .filter((tab): tab is string => typeof tab === "string" && KNOWN_TAB_KEYS.has(tab))
      .slice(0, 16);
  }

  return output;
}

function sanitizeTabChanges(raw: unknown): Record<string, number> {
  if (!raw || typeof raw !== "object" || Array.isArray(raw)) return {};
  const output: Record<string, number> = {};
  for (const [key, value] of Object.entries(raw as Record<string, unknown>)) {
    if (!KNOWN_TAB_KEYS.has(key)) continue;
    output[key] = clampInt(value, 0, MAX_COUNTER);
    if (Object.keys(output).length >= 32) break;
  }
  return output;
}

export function normalizeDailyReport(report: DailyReportBody, now = new Date()): NormalizedDailyReport | string {
  if (!isValidDay(report.day, now)) return "Invalid dailyReports day";
  const modelsResult = sanitizeModels(report.models);
  if ("error" in modelsResult) return modelsResult.error;

  const regionBucket = REGION_BUCKETS.has(report.regionBucket) ? report.regionBucket : null;
  const nicknameSource = NICKNAME_SOURCES.has(report.nicknameSource)
    ? report.nicknameSource
    : "anonymous";

  let topModel: string | null = null;
  if (typeof report.topModel === "string" && report.topModel.trim()) {
    topModel = report.topModel.trim().slice(0, MAX_MODEL_NAME);
  }

  return {
    day: report.day,
    spendCents: clampInt(report.spendCents, 0, MAX_SPEND),
    models: modelsResult.models,
    eventCount: clampInt(report.eventCount, 0, MAX_COUNTER),
    onDemandCents: clampInt(report.onDemandCents, 0, MAX_SPEND),
    includedCents: clampInt(report.includedCents, 0, MAX_SPEND),
    erroredEventCount: clampInt(report.erroredEventCount, 0, MAX_COUNTER),
    tokenInput: clampInt(report.tokenInput, 0, MAX_TOKENS),
    tokenOutput: clampInt(report.tokenOutput, 0, MAX_TOKENS),
    tokenCacheRead: clampInt(report.tokenCacheRead, 0, MAX_TOKENS),
    tokenCacheWrite: clampInt(report.tokenCacheWrite, 0, MAX_TOKENS),
    uniqueModels: clampInt(report.uniqueModels, 0, MAX_MODELS),
    topModel,
    peakHourUtc: clampInt(report.peakHourUtc, 0, 23),
    activeHourCount: clampInt(report.activeHourCount, 0, 24),
    regionBucket,
    panelOpens: clampInt(report.panelOpens, 0, MAX_COUNTER),
    tabChanges: sanitizeTabChanges(report.tabChanges),
    refreshAttempts: clampInt(report.refreshAttempts, 0, MAX_COUNTER),
    refreshFailures: clampInt(report.refreshFailures, 0, MAX_COUNTER),
    nicknameSource,
    clientConfig: sanitizeClientConfig(report.clientConfig),
  };
}

export function validateDailyReports(
  reports: unknown,
  now = new Date()
): { reports: NormalizedDailyReport[] } | { error: string } {
  if (reports === undefined || reports === null) {
    return { reports: [] };
  }
  if (!Array.isArray(reports)) return { error: "dailyReports must be an array" };
  if (reports.length > MAX_DAILY_REPORTS) return { error: "dailyReports too many entries" };

  const seen = new Set<string>();
  const normalized: NormalizedDailyReport[] = [];
  for (const report of reports) {
    if (!report || typeof report !== "object") return { error: "Invalid dailyReports entry" };
    const result = normalizeDailyReport(report as DailyReportBody, now);
    if (typeof result === "string") return { error: result };
    if (seen.has(result.day)) return { error: "duplicate dailyReports day" };
    seen.add(result.day);
    normalized.push(result);
  }
  return { reports: normalized };
}

export function tenureBucket(dayCount: number): string {
  if (dayCount <= 1) return "1";
  if (dayCount <= 6) return "2-6";
  if (dayCount <= 29) return "7-29";
  return "30+";
}

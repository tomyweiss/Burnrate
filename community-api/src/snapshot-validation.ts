import {
  sanitizeModels,
  normalizeRollingSpend,
  validateDailyReports,
  type ModelSpend,
  type NormalizedDailyReport,
} from "./daily-analytics.js";
import {
  WINDOW_HOURS,
  isValidUUID,
  validateClientVersion,
  validateInteractionStats,
  type InteractionStats,
  type SnapshotBody,
} from "./rank.js";

export interface NormalizedSnapshot {
  participantId: string;
  spendCents: number;
  models: ModelSpend[];
  nickname: string | null;
  previousNickname: string | null;
  clientVersion: string | null;
  interactionStats: InteractionStats | null;
  dailyReports: NormalizedDailyReport[];
}

/** Validate and normalize a community snapshot, preserving old-client tolerance on rolling fields. */
export function validateAndNormalizeSnapshot(
  body: SnapshotBody,
  now = new Date()
): { error: string } | { snapshot: NormalizedSnapshot } {
  if (!body.participantId || !isValidUUID(body.participantId)) {
    return { error: "Invalid participantId" };
  }

  const spendCents = normalizeRollingSpend(body.spendCents);
  if (spendCents === null) {
    return { error: "Invalid spendCents" };
  }

  if (body.windowHours !== undefined && body.windowHours !== WINDOW_HOURS) {
    return { error: "windowHours must be 24" };
  }

  const modelsResult = sanitizeModels(body.models);
  if ("error" in modelsResult) return { error: modelsResult.error };

  if (body.nickname != null && typeof body.nickname !== "string") {
    return { error: "Invalid nickname" };
  }
  if (body.nickname && body.nickname.length > 64) {
    return { error: "nickname too long" };
  }

  if (body.previousNickname != null && typeof body.previousNickname !== "string") {
    return { error: "Invalid previousNickname" };
  }
  if (body.previousNickname && body.previousNickname.length > 64) {
    return { error: "previousNickname too long" };
  }

  if (body.interactionStats !== undefined) {
    const interactionError = validateInteractionStats(body.interactionStats);
    if (interactionError) return { error: interactionError };
  }

  if (body.clientVersion !== undefined) {
    const versionError = validateClientVersion(body.clientVersion);
    if (versionError) return { error: versionError };
  }

  const dailyResult = validateDailyReports(body.dailyReports, now);
  if ("error" in dailyResult) return { error: dailyResult.error };

  return {
    snapshot: {
      participantId: body.participantId,
      spendCents,
      models: modelsResult.models,
      nickname: body.nickname?.trim() || null,
      previousNickname: body.previousNickname?.trim() || null,
      clientVersion: body.clientVersion?.trim() || null,
      interactionStats: body.interactionStats ?? null,
      dailyReports: dailyResult.reports,
    },
  };
}

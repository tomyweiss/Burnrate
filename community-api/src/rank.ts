export const STALE_HOURS = 36;
/** Always compute ranks when the requester is present (no minimum cohort). */
export const MIN_COHORT = 1;
export const WINDOW_HOURS = 24;
/** Max leaderboard rows returned by GET /v1/community/rank. */
export const LEADERBOARD_LIMIT = 30;

export interface ModelSpend {
  name: string;
  spendCents: number;
}

export interface InteractionStats {
  panelOpens: number;
  tabChanges: Record<string, number>;
}

export interface SnapshotBody {
  participantId: string;
  nickname?: string | null;
  previousNickname?: string | null;
  windowHours?: number;
  spendCents: number;
  models: ModelSpend[];
  dailyReports?: unknown;
  interactionStats?: InteractionStats;
  clientVersion?: string;
}

export interface LeaderboardEntry {
  rank: number;
  nickname: string | null;
  spendCents: number;
  isYou?: boolean;
}

export interface RankResponse {
  participantCount: number;
  rank: number | null;
  yourSpendCents: number;
  medianSpendCents: number | null;
  p25SpendCents: number | null;
  p75SpendCents: number | null;
  maxSpendCents: number | null;
  leaderboardNear: LeaderboardEntry[];
  notEnoughParticipants: boolean;
}

export interface Participant {
  id: string;
  nickname: string | null;
  spendCents: number;
}

/** Competition ranking for values sorted descending. */
export function competitionRanks(values: number[]): number[] {
  if (values.length === 0) return [];
  const ranks: number[] = [];
  let rank = 1;
  let i = 0;
  while (i < values.length) {
    const value = values[i];
    let count = 1;
    while (i + count < values.length && values[i + count] === value) {
      count += 1;
    }
    for (let j = 0; j < count; j += 1) {
      ranks.push(rank);
    }
    rank += count;
    i += count;
  }
  return ranks;
}

function percentile(sortedAsc: number[], p: number): number {
  if (sortedAsc.length === 0) return 0;
  const index = (sortedAsc.length - 1) * p;
  const lower = Math.floor(index);
  const upper = Math.ceil(index);
  if (lower === upper) return sortedAsc[lower];
  const weight = index - lower;
  return Math.round(sortedAsc[lower] * (1 - weight) + sortedAsc[upper] * weight);
}

export function buildRankResponse(
  participants: Participant[],
  requesterId: string
): RankResponse | null {
  const requester = participants.find((p) => p.id === requesterId);
  if (!requester) return null;

  if (participants.length < MIN_COHORT) {
    return {
      participantCount: participants.length,
      rank: null,
      yourSpendCents: requester.spendCents,
      medianSpendCents: null,
      p25SpendCents: null,
      p75SpendCents: null,
      maxSpendCents: null,
      leaderboardNear: [],
      notEnoughParticipants: true,
    };
  }

  const sortedDesc = [...participants].sort((a, b) => {
    if (b.spendCents !== a.spendCents) return b.spendCents - a.spendCents;
    return a.id.localeCompare(b.id);
  });
  const spendsDesc = sortedDesc.map((p) => p.spendCents);
  const ranks = competitionRanks(spendsDesc);

  const sortedAsc = [...spendsDesc].sort((a, b) => a - b);
  const requesterIndex = sortedDesc.findIndex((p) => p.id === requesterId);
  const requesterRank = ranks[requesterIndex];

  const leaderboardNear: LeaderboardEntry[] = sortedDesc
    .slice(0, LEADERBOARD_LIMIT)
    .map((p, index) => ({
      rank: ranks[index],
      nickname: p.nickname,
      spendCents: p.spendCents,
      isYou: p.id === requesterId,
    }));

  return {
    participantCount: participants.length,
    rank: requesterRank,
    yourSpendCents: requester.spendCents,
    medianSpendCents: percentile(sortedAsc, 0.5),
    p25SpendCents: percentile(sortedAsc, 0.25),
    p75SpendCents: percentile(sortedAsc, 0.75),
    maxSpendCents: spendsDesc[0] ?? 0,
    leaderboardNear,
    notEnoughParticipants: false,
  };
}

export function isValidUUID(value: string): boolean {
  return /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(value);
}

export function validateInteractionStats(stats: InteractionStats): string | null {
  if (typeof stats.panelOpens !== "number" || stats.panelOpens < 0 || !Number.isInteger(stats.panelOpens)) {
    return "Invalid interactionStats.panelOpens";
  }
  if (!stats.tabChanges || typeof stats.tabChanges !== "object" || Array.isArray(stats.tabChanges)) {
    return "Invalid interactionStats.tabChanges";
  }
  for (const [key, count] of Object.entries(stats.tabChanges)) {
    if (!key || key.length > 32) return "Invalid interactionStats.tabChanges key";
    if (typeof count !== "number" || count < 0 || !Number.isInteger(count)) {
      return "Invalid interactionStats.tabChanges value";
    }
  }
  return null;
}

export function validateClientVersion(version: string): string | null {
  if (typeof version !== "string" || version.length === 0 || version.length > 32) {
    return "Invalid clientVersion";
  }
  if (!/^[0-9A-Za-z][0-9A-Za-z._-]*$/.test(version)) {
    return "Invalid clientVersion";
  }
  return null;
}

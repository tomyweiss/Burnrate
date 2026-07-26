import { describe, expect, it } from "vitest";
import {
  buildRankResponse,
  competitionRanks,
  isValidUUID,
} from "./rank.js";

describe("competitionRanks", () => {
  it("handles ties", () => {
    expect(competitionRanks([100, 80, 80, 50])).toEqual([1, 2, 2, 4]);
  });
});

describe("buildRankResponse", () => {
  const participants = [
    { id: "a", nickname: "one", spendCents: 100 },
    { id: "b", nickname: "two", spendCents: 80 },
    { id: "c", nickname: null, spendCents: 80 },
    { id: "d", nickname: "four", spendCents: 50 },
    { id: "e", nickname: "five", spendCents: 40 },
  ];

  it("returns rank for a single participant", () => {
    const alone = participants.slice(0, 1);
    const res = buildRankResponse(alone, "a");
    expect(res?.notEnoughParticipants).toBe(false);
    expect(res?.rank).toBe(1);
    expect(res?.participantCount).toBe(1);
  });

  it("returns rank and neighbors for a small cohort", () => {
    const small = participants.slice(0, 3);
    const res = buildRankResponse(small, "c");
    expect(res?.notEnoughParticipants).toBe(false);
    expect(res?.rank).toBe(2);
    expect(res?.participantCount).toBe(3);
  });

  it("returns rank and neighbors for a larger cohort", () => {
    const res = buildRankResponse(participants, "c");
    expect(res?.notEnoughParticipants).toBe(false);
    expect(res?.rank).toBe(2);
    expect(res?.participantCount).toBe(5);
    expect(res?.leaderboardNear.some((e) => e.isYou)).toBe(true);
    expect(res?.leaderboardNear.every((e) => !("participantId" in e))).toBe(true);
  });

  it("returns null when requester missing", () => {
    expect(buildRankResponse(participants, "missing")).toBeNull();
  });
});

describe("isValidUUID", () => {
  it("accepts lowercase uuid", () => {
    expect(isValidUUID("550e8400-e29b-41d4-a716-446655440000")).toBe(true);
  });
  it("rejects garbage", () => {
    expect(isValidUUID("not-a-uuid")).toBe(false);
  });
});

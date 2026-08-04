import { describe, expect, it } from "vitest";
import { MAX_MODELS, MAX_MODEL_NAME, MAX_SPEND, sanitizeModels, normalizeRollingSpend } from "./daily-analytics.js";
import { validateAndNormalizeSnapshot } from "./snapshot-validation.js";

const LEGACY_PARTICIPANT = "11111111-1111-4111-8111-111111111111";

describe("legacy snapshot compatibility", () => {
  it("accepts minimal v4-style payloads without dailyReports or previousNickname", () => {
    const result = validateAndNormalizeSnapshot({
      participantId: LEGACY_PARTICIPANT,
      windowHours: 24,
      spendCents: 12345,
      models: [{ name: "claude-4-sonnet", spendCents: 12345 }],
      nickname: "Cursor User",
      clientVersion: "1.2.3",
    });

    expect("snapshot" in result).toBe(true);
    if (!("snapshot" in result)) return;
    expect(result.snapshot.dailyReports).toEqual([]);
    expect(result.snapshot.previousNickname).toBeNull();
    expect(result.snapshot.spendCents).toBe(12345);
  });

  it("clamps oversized rolling spend instead of rejecting", () => {
    const result = validateAndNormalizeSnapshot({
      participantId: LEGACY_PARTICIPANT,
      spendCents: MAX_SPEND + 999,
      models: [{ name: "claude-4-sonnet", spendCents: 100 }],
    });

    expect("snapshot" in result).toBe(true);
    if (!("snapshot" in result)) return;
    expect(result.snapshot.spendCents).toBe(MAX_SPEND);
  });

  it("truncates oversized model arrays and long model names", () => {
    const models = Array.from({ length: MAX_MODELS + 10 }, (_, index) => ({
      name: `model-${index}-${"x".repeat(100)}`,
      spendCents: index + 1,
    }));

    const sanitized = sanitizeModels(models);
    expect("models" in sanitized).toBe(true);
    if (!("models" in sanitized)) return;
    expect(sanitized.models.length).toBe(MAX_MODELS);
    expect(sanitized.models[0].name.length).toBeLessThanOrEqual(MAX_MODEL_NAME);
    expect(sanitized.models[MAX_MODELS - 1].name).toBe(`model-${MAX_MODELS - 1}-${"x".repeat(100)}`.slice(0, MAX_MODEL_NAME));
  });

  it("clamps per-model spend in rolling snapshots", () => {
    const sanitized = sanitizeModels([{ name: "big", spendCents: MAX_SPEND + 500 }]);
    expect("models" in sanitized).toBe(true);
    if (!("models" in sanitized)) return;
    expect(sanitized.models[0].spendCents).toBe(MAX_SPEND);
  });

  it("still rejects malformed dailyReports from newer clients", () => {
    const result = validateAndNormalizeSnapshot({
      participantId: LEGACY_PARTICIPANT,
      spendCents: 100,
      models: [{ name: "claude-4-sonnet", spendCents: 100 }],
      dailyReports: [{ day: "2099-01-01", spendCents: 1, models: [] }],
    });

    expect("error" in result).toBe(true);
  });

  it("normalizeRollingSpend rejects negative values like the old server", () => {
    expect(normalizeRollingSpend(-1)).toBeNull();
    expect(normalizeRollingSpend(Number.NaN)).toBeNull();
  });
});

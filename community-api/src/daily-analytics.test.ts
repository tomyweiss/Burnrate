import { describe, expect, it } from "vitest";
import {
  normalizeDailyReport,
  normalizeRollingSpend,
  sanitizeModels,
  tenureBucket,
  validateDailyReports,
  validateModels,
  MAX_SPEND,
} from "./daily-analytics.js";

describe("validateModels", () => {
  it("rejects oversized model arrays", () => {
    const models = Array.from({ length: 51 }, (_, index) => ({
      name: `model-${index}`,
      spendCents: 1,
    }));
    expect(validateModels(models)).toBe("models array too large");
  });
});

describe("sanitizeModels", () => {
  it("truncates instead of rejecting oversized arrays", () => {
    const models = Array.from({ length: 60 }, (_, index) => ({
      name: `model-${index}`,
      spendCents: 1,
    }));
    const result = sanitizeModels(models);
    expect("models" in result && result.models.length).toBe(50);
  });
});

describe("normalizeRollingSpend", () => {
  it("clamps large values", () => {
    expect(normalizeRollingSpend(MAX_SPEND + 1)).toBe(MAX_SPEND);
  });
});

describe("validateDailyReports", () => {
  it("rejects duplicate days", () => {
    const today = new Date().toISOString().slice(0, 10);
    const result = validateDailyReports([
      baseReport(today),
      baseReport(today),
    ]);
    expect("error" in result && result.error).toBe("duplicate dailyReports day");
  });

  it("accepts today and yesterday", () => {
    const now = new Date();
    const today = now.toISOString().slice(0, 10);
    const yesterday = new Date(now.getTime() - 86_400_000).toISOString().slice(0, 10);
    const result = validateDailyReports([baseReport(today), baseReport(yesterday)], now);
    expect("reports" in result && result.reports.length).toBe(2);
  });
});

describe("normalizeDailyReport", () => {
  it("drops invalid region buckets", () => {
    const today = new Date().toISOString().slice(0, 10);
    const result = normalizeDailyReport({
      ...baseReport(today),
      regionBucket: "invalid",
    });
    expect(typeof result !== "string" && result.regionBucket).toBeNull();
  });
});

describe("tenureBucket", () => {
  it("maps day counts to coarse buckets", () => {
    expect(tenureBucket(1)).toBe("1");
    expect(tenureBucket(5)).toBe("2-6");
    expect(tenureBucket(10)).toBe("7-29");
    expect(tenureBucket(40)).toBe("30+");
  });
});

function baseReport(day: string) {
  return {
    day,
    spendCents: 100,
    models: [{ name: "claude-4-sonnet", spendCents: 100 }],
    eventCount: 1,
    onDemandCents: 100,
    includedCents: 0,
    erroredEventCount: 0,
    tokenInput: 10,
    tokenOutput: 5,
    tokenCacheRead: 0,
    tokenCacheWrite: 0,
    uniqueModels: 1,
    topModel: "claude-4-sonnet",
    peakHourUtc: 12,
    activeHourCount: 1,
    regionBucket: "americas",
    panelOpens: 1,
    tabChanges: { models: 1 },
    refreshAttempts: 1,
    refreshFailures: 0,
    nicknameSource: "cursor",
    clientConfig: { timelinePreset: "today" },
  };
}

import { describe, expect, it } from "vitest";
import { computeCohortRollup, dayToClose, median } from "./cohort-rollup.js";

describe("median", () => {
  it("handles even and odd lengths", () => {
    expect(median([100, 200])).toBe(150);
    expect(median([100, 200, 300])).toBe(200);
  });
});

describe("computeCohortRollup", () => {
  it("aggregates daily rows", () => {
    const rollup = computeCohortRollup({
      day: "2026-08-02",
      dailyRows: [
        {
          participant_id: "a",
          spend_cents: 100,
          event_count: 2,
          panel_opens: 3,
          model_breakdown: [{ name: "claude-4-sonnet", spendCents: 100 }],
          client_version: "0.0.26",
        },
        {
          participant_id: "b",
          spend_cents: 300,
          event_count: 4,
          panel_opens: 1,
          model_breakdown: [{ name: "gpt-4.1", spendCents: 300 }],
          client_version: "0.0.25",
        },
      ],
      newParticipants: 1,
      optouts: 0,
    });

    expect(rollup.active_participants).toBe(2);
    expect(rollup.total_spend_cents).toBe(400);
    expect(rollup.median_spend_cents).toBe(200);
    expect(rollup.version_mix["0.0.26"]).toBe(1);
    expect(rollup.model_mix["claude-4-sonnet"]).toBe(100);
  });
});

describe("dayToClose", () => {
  it("closes day minus two in UTC", () => {
    const now = new Date("2026-08-04T15:00:00.000Z");
    expect(dayToClose(now)).toBe("2026-08-02");
  });
});

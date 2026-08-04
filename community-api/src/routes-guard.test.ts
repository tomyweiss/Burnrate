import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { describe, expect, it } from "vitest";

const root = dirname(fileURLToPath(import.meta.url));

describe("public API guard", () => {
  it("rank route does not read analytics tables", () => {
    const routes = readFileSync(join(root, "routes.ts"), "utf8");
    const rankSection = routes.slice(routes.indexOf('app.get("/v1/community/rank"'));
    expect(rankSection).not.toContain("participant_daily_stats");
    expect(rankSection).not.toContain("optout_events");
    expect(rankSection).not.toContain("daily_cohort_rollup");
    expect(rankSection).not.toContain("failure_logs");
  });
});

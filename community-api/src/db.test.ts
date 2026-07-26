import { describe, expect, it } from "vitest";
import { buildPoolConfig } from "./db.js";

describe("buildPoolConfig", () => {
  it("enables TLS for Railway private network (postgres-ssl)", () => {
    const cfg = buildPoolConfig(
      "postgresql://postgres:secret@postgres.railway.internal:5432/railway"
    );
    expect(cfg.ssl).toEqual({ rejectUnauthorized: false });
  });

  it("enables TLS for Railway public proxy hosts", () => {
    const cfg = buildPoolConfig(
      "postgresql://postgres:secret@sakura.proxy.rlwy.net:49214/railway"
    );
    expect(cfg.ssl).toEqual({ rejectUnauthorized: false });
  });

  it("keeps local URLs without SSL", () => {
    const cfg = buildPoolConfig("postgresql://postgres:secret@localhost:5432/railway");
    expect(cfg.ssl).toBeUndefined();
  });
});

import { describe, expect, it } from "vitest";
import { normalizeFailure, validateFailure } from "./failure-log.js";

describe("validateFailure", () => {
  it("accepts a minimal valid payload", () => {
    expect(
      validateFailure({
        source: "usage",
        category: "network",
        message: "Request timed out",
      })
    ).toBeNull();
  });

  it("rejects unknown source", () => {
    expect(
      validateFailure({
        source: "billing",
        category: "network",
        message: "oops",
      })
    ).toBe("Invalid source");
  });

  it("rejects invalid participantId", () => {
    expect(
      validateFailure({
        source: "community",
        category: "api",
        message: "HTTP 503",
        participantId: "not-a-uuid",
      })
    ).toBe("Invalid participantId");
  });

  it("normalizes trimmed fields", () => {
    expect(
      normalizeFailure({
        source: " app ",
        category: " unknown ",
        message: " crash ",
        clientVersion: " 0.0.32 ",
      })
    ).toEqual({
      source: "app",
      category: "unknown",
      message: "crash",
      clientVersion: "0.0.32",
      participantId: null,
      context: {},
    });
  });
});

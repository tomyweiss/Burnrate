import { describe, expect, it } from "vitest";
import {
  appendNicknameHistory,
  normalizeNickname,
  reconcileNickname,
} from "./nickname-reconcile.js";

describe("normalizeNickname", () => {
  it("trims and rejects empty values", () => {
    expect(normalizeNickname("  cobalt-fox  ")).toBe("cobalt-fox");
    expect(normalizeNickname("   ")).toBeNull();
    expect(normalizeNickname(null)).toBeNull();
  });
});

describe("reconcileNickname", () => {
  it("is idempotent when the row already has the next nickname", () => {
    const result = reconcileNickname({
      currentNickname: "Tom Weiss",
      nextNickname: "Tom Weiss",
      previousNickname: "cobalt-fox",
    });

    expect(result.outcome).toBe("already_current");
    expect(result.historyEntry).toBeNull();
    expect(result.mismatch).toBe(false);
  });

  it("reconciles a random nickname to a cursor display name", () => {
    const result = reconcileNickname({
      currentNickname: "cobalt-fox",
      nextNickname: "Tom Weiss",
      previousNickname: "cobalt-fox",
    });

    expect(result.outcome).toBe("applied");
    expect(result.historyEntry).toBe("cobalt-fox");
    expect(result.mismatch).toBe(false);
  });

  it("flags a mismatch but still records the old nickname", () => {
    const result = reconcileNickname({
      currentNickname: "other-name",
      nextNickname: "Tom Weiss",
      previousNickname: "cobalt-fox",
    });

    expect(result.outcome).toBe("applied");
    expect(result.historyEntry).toBe("other-name");
    expect(result.mismatch).toBe(true);
  });
});

describe("appendNicknameHistory", () => {
  it("deduplicates prior nicknames", () => {
    expect(appendNicknameHistory(["cobalt-fox"], "cobalt-fox")).toEqual(["cobalt-fox"]);
    expect(appendNicknameHistory(["cobalt-fox"], "Tom Weiss")).toEqual([
      "cobalt-fox",
      "Tom Weiss",
    ]);
  });
});

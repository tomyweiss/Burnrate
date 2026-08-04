export function normalizeNickname(value: string | null | undefined): string | null {
  if (value == null) return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

export type NicknameReconcileOutcome = "applied" | "already_current" | "new_participant";

export interface NicknameReconcileInput {
  currentNickname: string | null;
  nextNickname: string | null;
  previousNickname?: string | null;
}

export interface NicknameReconcileResult {
  outcome: NicknameReconcileOutcome;
  mismatch: boolean;
  historyEntry: string | null;
}

/**
 * Decide how to reconcile a participant rename.
 * When previousNickname is supplied, the current stored nickname should match it
 * unless the row was already updated (idempotent retry).
 */
export function reconcileNickname(input: NicknameReconcileInput): NicknameReconcileResult {
  const current = normalizeNickname(input.currentNickname);
  const next = normalizeNickname(input.nextNickname);
  const previous = normalizeNickname(input.previousNickname);

  if (current === next) {
    return { outcome: "already_current", mismatch: false, historyEntry: null };
  }

  if (current === null) {
    return { outcome: "new_participant", mismatch: false, historyEntry: null };
  }

  if (previous === null) {
    return {
      outcome: "applied",
      mismatch: false,
      historyEntry: current,
    };
  }

  const mismatch = current !== previous;
  return {
    outcome: "applied",
    mismatch,
    historyEntry: current,
  };
}

export function appendNicknameHistory(
  history: string[] | null | undefined,
  entry: string | null
): string[] {
  if (!entry) return history ?? [];
  const base = history ?? [];
  if (base.includes(entry)) return base;
  return [...base, entry];
}

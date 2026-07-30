import { isValidUUID } from "./rank.js";

export const FAILURE_SOURCES = new Set(["usage", "community", "updates", "app"]);
export const FAILURE_CATEGORIES = new Set([
  "network",
  "api",
  "auth",
  "decode",
  "validation",
  "unknown",
]);

export interface FailureBody {
  source: string;
  category: string;
  message: string;
  clientVersion?: string;
  participantId?: string;
  context?: Record<string, string>;
}

export function validateFailure(body: FailureBody): string | null {
  const source = body.source?.trim();
  if (!source || !FAILURE_SOURCES.has(source)) {
    return "Invalid source";
  }

  const category = body.category?.trim();
  if (!category || !FAILURE_CATEGORIES.has(category)) {
    return "Invalid category";
  }

  const message = body.message?.trim();
  if (!message) {
    return "Invalid message";
  }
  if (message.length > 2000) {
    return "message too long";
  }

  if (body.participantId !== undefined && !isValidUUID(body.participantId)) {
    return "Invalid participantId";
  }

  if (body.clientVersion !== undefined) {
    const version = body.clientVersion.trim();
    if (!version || version.length > 32) {
      return "Invalid clientVersion";
    }
  }

  if (body.context !== undefined) {
    if (typeof body.context !== "object" || body.context === null || Array.isArray(body.context)) {
      return "Invalid context";
    }
    const entries = Object.entries(body.context);
    if (entries.length > 20) {
      return "context too large";
    }
    for (const [key, value] of entries) {
      if (!key.trim() || key.length > 64) {
        return "Invalid context key";
      }
      if (typeof value !== "string" || value.length > 500) {
        return "Invalid context value";
      }
    }
  }

  return null;
}

export function normalizeFailure(body: FailureBody) {
  return {
    source: body.source.trim(),
    category: body.category.trim(),
    message: body.message.trim(),
    clientVersion: body.clientVersion?.trim() || null,
    participantId: body.participantId?.trim() || null,
    context: body.context ?? {},
  };
}

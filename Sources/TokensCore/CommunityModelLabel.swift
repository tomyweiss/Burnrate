import Foundation

public enum CommunityModelLabel {
  /// Compact leaderboard label: drops a leading `claude-`, then full name when short,
  /// otherwise a hyphenated prefix with an ellipsis.
  public static func leaderboard(_ raw: String?, maxLength: Int = 20) -> String? {
    guard let raw else { return nil }
    let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }

    let compact = stripClaudePrefix(trimmed)
    guard !compact.isEmpty else { return nil }
    if compact.count <= maxLength { return compact }

    let parts = compact.split(separator: "-", omittingEmptySubsequences: false).map(String.init)
    if parts.count <= 1 {
      return String(compact.prefix(max(1, maxLength - 1))) + "…"
    }

    var result = parts[0]
    for part in parts.dropFirst() {
      let candidate = result + "-" + part
      if candidate.count + 1 > maxLength {
        break
      }
      result = candidate
    }

    if result.count < compact.count {
      return result + "…"
    }
    return result
  }

  private static func stripClaudePrefix(_ name: String) -> String {
    let lower = name.lowercased()
    guard lower.hasPrefix("claude-") else { return name }
    return String(name.dropFirst("claude-".count))
  }
}

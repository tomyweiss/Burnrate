import Foundation

public enum LeaderboardDedup {
    /// Collapses duplicate display names to a single row, preferring `isYou` then highest spend.
    public static func deduplicateNicknames(_ entries: [CommunityLeaderboardEntry]) -> [CommunityLeaderboardEntry] {
        var bestByKey: [String: CommunityLeaderboardEntry] = [:]
        for entry in entries {
            let key = nicknameKey(entry.nickname)
            if let existing = bestByKey[key] {
                bestByKey[key] = preferred(existing, entry)
            } else {
                bestByKey[key] = entry
            }
        }
        return bestByKey.values.sorted { $0.rank < $1.rank }
    }

    private static func nicknameKey(_ nickname: String?) -> String {
        let trimmed = nickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "__anonymous__" : trimmed.lowercased()
    }

    private static func preferred(
        _ existing: CommunityLeaderboardEntry,
        _ candidate: CommunityLeaderboardEntry
    ) -> CommunityLeaderboardEntry {
        if existing.isYou { return existing }
        if candidate.isYou { return candidate }
        if existing.spendCents != candidate.spendCents {
            return existing.spendCents > candidate.spendCents ? existing : candidate
        }
        return existing.rank <= candidate.rank ? existing : candidate
    }
}

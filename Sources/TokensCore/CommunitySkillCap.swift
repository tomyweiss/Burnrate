import Foundation

/// Per-skill spend and invocation counts for operator analytics uploads.
public struct CommunitySkillSpend: Sendable, Codable, Equatable {
    public let name: String
    public let invocationCount: Int
    public let spendCents: Int

    public init(name: String, invocationCount: Int, spendCents: Int) {
        self.name = name
        self.invocationCount = invocationCount
        self.spendCents = spendCents
    }
}

/// Normalize and cap daily skill rows before community upload.
public enum CommunitySkillCap {
    public static let maxSkills = 50
    public static let maxNameLength = 64
    public static let otherBucketName = "other"

    public static func normalizeName(_ raw: String) -> String? {
        var name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if name.hasPrefix("/") {
            name = String(name.dropFirst())
        }
        name = name.lowercased()
        guard !name.isEmpty else { return nil }
        return String(name.prefix(maxNameLength))
    }

    /// Merge duplicate names, keep the top `maxSkills` by spend, fold the rest into `other`.
    public static func cap(
        _ skills: [(name: String, invocationCount: Int, spendCents: Int)]
    ) -> [CommunitySkillSpend] {
        var merged: [String: (invocationCount: Int, spendCents: Int)] = [:]
        for skill in skills {
            guard let name = normalizeName(skill.name), name != otherBucketName else { continue }
            let invocations = max(0, skill.invocationCount)
            let spend = max(0, skill.spendCents)
            let existing = merged[name] ?? (0, 0)
            merged[name] = (
                existing.invocationCount + invocations,
                existing.spendCents + spend
            )
        }

        let sorted = merged
            .map { name, totals in
                CommunitySkillSpend(
                    name: name,
                    invocationCount: totals.invocationCount,
                    spendCents: totals.spendCents
                )
            }
            .sorted {
                if $0.spendCents == $1.spendCents {
                    return $0.invocationCount > $1.invocationCount
                }
                return $0.spendCents > $1.spendCents
            }

        guard sorted.count > maxSkills else { return sorted }

        let top = Array(sorted.prefix(maxSkills))
        let overflow = sorted.dropFirst(maxSkills)
        let overflowInvocations = overflow.reduce(0) { $0 + $1.invocationCount }
        let overflowSpend = overflow.reduce(0) { $0 + $1.spendCents }
        guard overflowInvocations > 0 || overflowSpend > 0 else { return top }

        if let otherIndex = top.firstIndex(where: { $0.name == otherBucketName }) {
            let other = top[otherIndex]
            var updated = top
            updated[otherIndex] = CommunitySkillSpend(
                name: otherBucketName,
                invocationCount: other.invocationCount + overflowInvocations,
                spendCents: other.spendCents + overflowSpend
            )
            return updated
        }

        return top + [
            CommunitySkillSpend(
                name: otherBucketName,
                invocationCount: overflowInvocations,
                spendCents: overflowSpend
            ),
        ]
    }

    /// Sum skill rows that were capped separately (Cursor and Claude Code), then cap once.
    public static func merge(_ groups: [[CommunitySkillSpend]]) -> [CommunitySkillSpend] {
        var named: [(name: String, invocationCount: Int, spendCents: Int)] = []
        var otherInvocations = 0
        var otherSpend = 0
        for skill in groups.joined() {
            if skill.name == otherBucketName {
                otherInvocations += max(0, skill.invocationCount)
                otherSpend += max(0, skill.spendCents)
            } else {
                named.append((
                    name: skill.name,
                    invocationCount: skill.invocationCount,
                    spendCents: skill.spendCents
                ))
            }
        }

        var capped = cap(named)
        guard otherInvocations > 0 || otherSpend > 0 else { return capped }

        if let index = capped.firstIndex(where: { $0.name == otherBucketName }) {
            let existing = capped[index]
            capped[index] = CommunitySkillSpend(
                name: otherBucketName,
                invocationCount: existing.invocationCount + otherInvocations,
                spendCents: existing.spendCents + otherSpend
            )
            return capped
        }

        let carried = CommunitySkillSpend(
            name: otherBucketName,
            invocationCount: otherInvocations,
            spendCents: otherSpend
        )
        guard capped.count >= maxSkills, let smallest = smallestIndex(in: capped) else {
            return capped + [carried]
        }
        let dropped = capped.remove(at: smallest)
        return capped + [
            CommunitySkillSpend(
                name: otherBucketName,
                invocationCount: carried.invocationCount + dropped.invocationCount,
                spendCents: carried.spendCents + dropped.spendCents
            ),
        ]
    }

    private static func smallestIndex(in skills: [CommunitySkillSpend]) -> Int? {
        skills.indices.min { lhs, rhs in
            let left = skills[lhs]
            let right = skills[rhs]
            if left.spendCents == right.spendCents {
                return left.invocationCount < right.invocationCount
            }
            return left.spendCents < right.spendCents
        }
    }
}

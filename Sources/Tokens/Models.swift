import Foundation

struct UsageEventsResponse: Decodable, Sendable {
    let totalUsageEventsCount: Int?
    let usageEventsDisplay: [UsageEvent]?
}

struct UsageEvent: Decodable, Sendable, Hashable {
    let timestamp: String
    let model: String?
    let kind: String?
    let chargedCents: Double?
    let cursorTokenFee: Double?
    let isTokenBasedCall: Bool?
    let tokenUsage: TokenUsage?
    let usageBasedCosts: String?
    let conversationId: String?

    var timestampMs: Double {
        Double(timestamp) ?? 0
    }

    var costCents: Double {
        if let chargedCents {
            return chargedCents
        }
        if let total = tokenUsage?.totalCents {
            return total + (cursorTokenFee ?? 0)
        }
        return 0
    }

    var inputTokens: Int { tokenUsage?.inputTokens ?? 0 }
    var outputTokens: Int { tokenUsage?.outputTokens ?? 0 }
    var cacheReadTokens: Int { tokenUsage?.cacheReadTokens ?? 0 }
    var cacheWriteTokens: Int { tokenUsage?.cacheWriteTokens ?? 0 }

    var sessionKey: String {
        let id = conversationId?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return id.isEmpty ? "unknown-session" : id
    }
}

struct TokenUsage: Decodable, Sendable, Hashable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheWriteTokens: Int?
    let cacheReadTokens: Int?
    let totalCents: Double?
    let discountPercentOff: Double?
}

struct SessionUsage: Identifiable, Sendable, Hashable {
    var id: String { conversationId }
    let conversationId: String
    let name: String?
    let workspaceName: String?
    let isCloud: Bool
    let isArchived: Bool
    let repoName: String?
    let branchName: String?
    let costCents: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let eventCount: Int
    let lastTimestampMs: Double
    /// Models used in this session, sorted by that session's per-model cost desc.
    let models: [String]
    /// Subagents rolled into this root conversation (Sessions list only).
    let subagentCount: Int

    var costDollars: Double { costCents / 100.0 }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        let short = conversationId.count > 8
            ? String(conversationId.prefix(8))
            : conversationId
        return "Session \(short)"
    }

    /// Extra subtitle: workspace for local, or `repo · branch` for cloud.
    var locationSubtitle: String? {
        if isCloud {
            var parts: [String] = []
            if let repoName, !repoName.isEmpty { parts.append(repoName) }
            if let branchName, !branchName.isEmpty { parts.append(branchName) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        let workspace = workspaceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return workspace.isEmpty ? nil : workspace
    }

    func enriched(with meta: SessionMeta?) -> SessionUsage {
        guard let meta else { return self }
        return SessionUsage(
            conversationId: conversationId,
            name: meta.name ?? name,
            workspaceName: meta.workspaceName ?? workspaceName,
            isCloud: meta.isCloud || isCloud || conversationId.hasPrefix("bc-"),
            isArchived: meta.isArchived || isArchived,
            repoName: meta.repoName ?? repoName,
            branchName: meta.branchName ?? branchName,
            costCents: costCents,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            eventCount: eventCount,
            lastTimestampMs: lastTimestampMs,
            models: models,
            subagentCount: subagentCount
        )
    }
}

struct AgentUsage: Identifiable, Sendable, Hashable {
    var id: String { conversationId }
    let conversationId: String
    let name: String?
    let subagentTypeName: String?
    let isMain: Bool
    let costCents: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let eventCount: Int
    let lastTimestampMs: Double
    let models: [String]

    var costDollars: Double { costCents / 100.0 }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }

    var displayName: String {
        if isMain { return "Main" }
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        if let type = subagentTypeName, !type.isEmpty { return type }
        let short = conversationId.count > 8
            ? String(conversationId.prefix(8))
            : conversationId
        return "Agent \(short)"
    }
}

struct ConversationUsage: Identifiable, Sendable, Hashable {
    var id: String { conversationId }
    let conversationId: String
    let name: String?
    let workspaceName: String?
    let isCloud: Bool
    let isArchived: Bool
    let repoName: String?
    let branchName: String?
    let costCents: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let eventCount: Int
    let lastTimestampMs: Double
    let models: [String]
    let main: AgentUsage
    let subagents: [AgentUsage]

    var costDollars: Double { costCents / 100.0 }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }

    var subagentCount: Int { subagents.count }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        let short = conversationId.count > 8
            ? String(conversationId.prefix(8))
            : conversationId
        return "Session \(short)"
    }

    var locationSubtitle: String? {
        if isCloud {
            var parts: [String] = []
            if let repoName, !repoName.isEmpty { parts.append(repoName) }
            if let branchName, !branchName.isEmpty { parts.append(branchName) }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
        let workspace = workspaceName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return workspace.isEmpty ? nil : workspace
    }

    var asSessionUsage: SessionUsage {
        SessionUsage(
            conversationId: conversationId,
            name: name,
            workspaceName: workspaceName,
            isCloud: isCloud,
            isArchived: isArchived,
            repoName: repoName,
            branchName: branchName,
            costCents: costCents,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            eventCount: eventCount,
            lastTimestampMs: lastTimestampMs,
            models: models,
            subagentCount: subagentCount
        )
    }
}

struct ModelUsage: Identifiable, Sendable, Hashable {
    var id: String { model }
    let model: String
    let costCents: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let eventCount: Int
    let sessions: [SessionUsage]

    var costDollars: Double { costCents / 100.0 }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }

    func withSessions(_ sessions: [SessionUsage]) -> ModelUsage {
        ModelUsage(
            model: model,
            costCents: costCents,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            eventCount: eventCount,
            sessions: sessions
        )
    }
}

struct UsageSnapshot: Sendable {
    let windowCostCents: Double
    let recentCostCents: Double
    let models: [ModelUsage]
    /// Root conversations (subagents rolled in), sorted by cost desc.
    let sessionsAcrossModels: [SessionUsage]
    /// Same roots with main vs subagent breakdown for detail screen.
    let conversations: [ConversationUsage]
    /// Leaf conversationId → root conversationId (identity when not a subagent).
    let rootIdByConversation: [String: String]
    /// Variable-length buckets for the active timeline window.
    let sparklineCostCents: [Double]
    let window: UsageTimeWindow
    let eventCount: Int
    let fetchedAt: Date

    var windowDollars: Double { windowCostCents / 100.0 }
    var recentDollars: Double { recentCostCents / 100.0 }

    func conversation(id: String) -> ConversationUsage? {
        conversations.first { $0.conversationId == id }
    }

    func rootId(for conversationId: String) -> String {
        rootIdByConversation[conversationId] ?? conversationId
    }

    static let empty = UsageSnapshot(
        windowCostCents: 0,
        recentCostCents: 0,
        models: [],
        sessionsAcrossModels: [],
        conversations: [],
        rootIdByConversation: [:],
        sparklineCostCents: Array(repeating: 0, count: 24),
        window: UsageTimeWindow(preset: .today, timeZone: .current),
        eventCount: 0,
        fetchedAt: .distantPast
    )
}

enum TokensError: Error, LocalizedError, Sendable {
    case databaseNotFound
    case tokenNotFound
    case invalidToken
    case httpStatus(Int)
    case apiMessage(String)
    case decodingFailed
    case tooManyPages

    var errorDescription: String? {
        switch self {
        case .databaseNotFound:
            "Cursor database not found. Is Cursor installed?"
        case .tokenNotFound:
            "No auth token found. Sign in to Cursor, then refresh."
        case .invalidToken:
            "Could not parse Cursor auth token."
        case .httpStatus(let code):
            "Cursor API returned HTTP \(code)."
        case .apiMessage(let message):
            message
        case .decodingFailed:
            "Could not decode usage response."
        case .tooManyPages:
            "Too many usage events to load for the selected timeline."
        }
    }
}

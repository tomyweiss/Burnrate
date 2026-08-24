import Foundation
import TokensCore

struct UsageEventsResponse: Codable, Sendable {
    let totalUsageEventsCount: Int?
    let usageEventsDisplay: [UsageEvent]?
}

struct UsageEvent: Codable, Sendable, Hashable {
    let timestamp: String
    let model: String?
    let kind: String?
    let chargedCents: Double?
    let cursorTokenFee: Double?
    let isTokenBasedCall: Bool?
    let tokenUsage: TokenUsage?
    let usageBasedCosts: String?
    let conversationId: String?
    /// Billable request units. On request-based plans this is the only per-event
    /// billing signal Cursor populates; the dollar fields stay at zero.
    let requestsCosts: Double?

    var timestampMs: Double {
        Double(timestamp) ?? 0
    }

    var billingKind: BillingKind {
        BillingKind(rawKind: kind)
    }

    var requestUnits: Double {
        guard billingKind.isBillable else { return 0 }
        return requestsCosts ?? 0
    }

    var costCents: Double {
        if let chargedCents, chargedCents > 0 {
            return chargedCents
        }
        if let total = tokenUsage?.totalCents {
            return total + (cursorTokenFee ?? 0)
        }
        return 0
    }

    /// Dollar cost in cents, preferring Cursor's own per-event amount and falling
    /// back to request units priced by `rates` on request-based plans.
    func costCents(using rates: SpendRates) -> Double {
        let charged = costCents
        if charged > 0 { return charged }
        return rates.cents(forUnits: requestUnits, kind: billingKind)
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

struct TokenUsage: Codable, Sendable, Hashable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheWriteTokens: Int?
    let cacheReadTokens: Int?
    let totalCents: Double?
    let discountPercentOff: Double?
}

/// How Cursor billed a usage event.
enum BillingKind: Sendable, Hashable {
    /// Covered by the plan's included allowance.
    case included
    /// Charged as on-demand spend beyond the included allowance.
    case usageBased
    /// Failed request; never billed.
    case errored
    case unknown

    init(rawKind: String?) {
        switch rawKind {
        case "USAGE_EVENT_KIND_INCLUDED_IN_BUSINESS", "USAGE_EVENT_KIND_INCLUDED_IN_PRO":
            self = .included
        case "USAGE_EVENT_KIND_USAGE_BASED":
            self = .usageBased
        case "USAGE_EVENT_KIND_ERRORED_NOT_CHARGED":
            self = .errored
        default:
            self = .unknown
        }
    }

    var isBillable: Bool { self != .errored }
}

/// Billing-cycle spend totals for the signed-in user, straight from Cursor.
struct SpendSummary: Codable, Sendable, Hashable {
    /// On-demand spend beyond the included allowance, in cents.
    let onDemandCents: Double
    /// Spend absorbed by the plan's included allowance, in cents.
    let includedCents: Double
    let cycleStartMs: Double

    var totalCents: Double { onDemandCents + includedCents }
}

/// Converts request units into cents, calibrated against `SpendSummary` totals.
///
/// Request-based plans report no per-event dollar amount, so the only way to
/// attribute spend to a session or model is to price each event's request units
/// using the cycle-wide rate Cursor implies.
struct SpendRates: Codable, Sendable, Hashable {
    let includedCentsPerUnit: Double
    let usageBasedCentsPerUnit: Double
    let computedAt: Date

    static let unavailable = SpendRates(
        includedCentsPerUnit: 0,
        usageBasedCentsPerUnit: 0,
        computedAt: .distantPast
    )

    var isAvailable: Bool {
        includedCentsPerUnit > 0 || usageBasedCentsPerUnit > 0
    }

    func cents(forUnits units: Double, kind: BillingKind) -> Double {
        guard units > 0 else { return 0 }
        switch kind {
        case .errored:
            return 0
        case .included:
            return units * includedCentsPerUnit
        case .usageBased, .unknown:
            return units * usageBasedCentsPerUnit
        }
    }

    /// Derives per-unit rates by spreading cycle spend across the cycle's request units.
    static func calibrate(summary: SpendSummary, cycleEvents: [UsageEvent]) -> SpendRates {
        var includedUnits: Double = 0
        var usageBasedUnits: Double = 0
        for event in cycleEvents {
            switch event.billingKind {
            case .included:
                includedUnits += event.requestUnits
            case .usageBased, .unknown:
                usageBasedUnits += event.requestUnits
            case .errored:
                continue
            }
        }

        return SpendRates(
            includedCentsPerUnit: includedUnits > 0 ? summary.includedCents / includedUnits : 0,
            usageBasedCentsPerUnit: usageBasedUnits > 0 ? summary.onDemandCents / usageBasedUnits : 0,
            computedAt: Date()
        )
    }
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
    /// Cost from this conversation's own billing events (excludes subagents).
    let ownCostCents: Double
    /// `ownCostCents` plus all descendant subagent costs.
    let costCents: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let eventCount: Int
    let lastTimestampMs: Double
    /// Models used in this session, sorted by that session's per-model cost desc.
    let models: [String]
    /// Immediate parent conversation when this session is a subagent.
    let parentConversationId: String?
    /// Direct child subagent conversation ids (not transitive).
    let childConversationIds: [String]

    var isSubagent: Bool { parentConversationId != nil }
    var hasSubagents: Bool { !childConversationIds.isEmpty }

    var costDollars: Double { costCents / 100.0 }
    var ownCostDollars: Double { ownCostCents / 100.0 }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return DisplayText.sanitize(trimmed) }
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
            ownCostCents: ownCostCents,
            costCents: costCents,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            eventCount: eventCount,
            lastTimestampMs: lastTimestampMs,
            models: models,
            parentConversationId: parentConversationId,
            childConversationIds: childConversationIds
        )
    }
}

struct ModelUsage: Identifiable, Sendable, Hashable {
    var id: String { model }
    let model: String
    let costCents: Double
    /// Median cost per usage event (request), in cents.
    let medianCostCents: Double
    let inputTokens: Int
    let outputTokens: Int
    let cacheReadTokens: Int
    let cacheWriteTokens: Int
    let eventCount: Int
    let sessions: [SessionUsage]

    var costDollars: Double { costCents / 100.0 }

    /// Average cost per usage event (request) for this model.
    var averageCostDollars: Double {
        guard eventCount > 0 else { return 0 }
        return costDollars / Double(eventCount)
    }

    var medianCostDollars: Double { medianCostCents / 100.0 }

    var totalTokens: Int {
        inputTokens + outputTokens + cacheReadTokens + cacheWriteTokens
    }

    func withSessions(_ sessions: [SessionUsage]) -> ModelUsage {
        ModelUsage(
            model: model,
            costCents: costCents,
            medianCostCents: medianCostCents,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            cacheReadTokens: cacheReadTokens,
            cacheWriteTokens: cacheWriteTokens,
            eventCount: eventCount,
            sessions: sessions
        )
    }
}

/// A user prompt with the cost attributed to it: every usage event in the same
/// conversation from the prompt's timestamp until the next prompt.
struct PromptUsage: Identifiable, Sendable, Hashable {
    var id: String { "\(conversationId):\(bubbleId)" }
    let conversationId: String
    let bubbleId: String
    let text: String
    let createdAtMs: Double
    let sessionName: String?
    let costCents: Double
    let eventCount: Int
    /// Total tokens (in + out + cache) across the prompt's events.
    let totalTokens: Int
    /// Timestamp of the last usage event attributed to this prompt.
    let lastEventMs: Double
    /// Models used to answer this prompt, sorted by cost desc.
    let models: [String]
    /// Skills (slash commands) mentioned in the prompt.
    let skills: [String]

    var costDollars: Double { costCents / 100.0 }

    /// Approximate response duration: first prompt keystroke to last billed event.
    var durationSeconds: Double {
        // Ignore synthetic/unknown timestamps (0 or pre-2001) so missing createdAt
        // does not yield a multi-decade duration.
        guard eventCount > 0, createdAtMs > 1_000_000_000_000, lastEventMs > createdAtMs else {
            return 0
        }
        return (lastEventMs - createdAtMs) / 1000
    }

    /// First line of the prompt, for compact display.
    var headline: String {
        CursorPromptText.headline(text)
    }

    /// Full prompt text with terminal prompt glyphs removed for display.
    var displayText: String {
        DisplayText.sanitize(CursorPromptText.visible(text))
    }
}

/// Aggregated cost for one skill (slash command) across the window.
struct SkillUsage: Identifiable, Sendable, Hashable {
    var id: String { skill }
    let skill: String
    let costCents: Double
    /// Median cost per use, in cents.
    let medianCostCents: Double
    let invocationCount: Int
    let eventCount: Int
    let lastUsedMs: Double

    var costDollars: Double { costCents / 100.0 }

    var averageCostDollars: Double {
        guard invocationCount > 0 else { return 0 }
        return costDollars / Double(invocationCount)
    }

    var medianCostDollars: Double { medianCostCents / 100.0 }
}

enum Stats {
    static func median(_ values: [Double]) -> Double {
        guard !values.isEmpty else { return 0 }
        let sorted = values.sorted()
        let mid = sorted.count / 2
        return sorted.count.isMultiple(of: 2)
            ? (sorted[mid - 1] + sorted[mid]) / 2
            : sorted[mid]
    }
}

struct UsageSnapshot: Sendable {
    let windowCostCents: Double
    let recentCostCents: Double
    let models: [ModelUsage]
    /// All sessions (roots and subagents) with hierarchy + rolled-up cost, sorted by cost desc.
    let sessionsAcrossModels: [SessionUsage]
    /// Root-session prompts with subagent work folded in; used by Feed / Skills / parent detail.
    let prompts: [PromptUsage]
    /// Subagent sessions' own prompts (events not folded to parent); used by subagent detail.
    let subagentPrompts: [PromptUsage]
    /// Per-skill cost breakdown, sorted by cost desc.
    let skills: [SkillUsage]
    /// Variable-length buckets for the active timeline window.
    let sparklineCostCents: [Double]
    let window: UsageTimeWindow
    let eventCount: Int
    let fetchedAt: Date

    var windowDollars: Double { windowCostCents / 100.0 }
    var recentDollars: Double { recentCostCents / 100.0 }

    /// Root sessions only (subagents hidden from the top-level Sessions list).
    var rootSessions: [SessionUsage] {
        sessionsAcrossModels.filter { !$0.isSubagent }
    }

    func session(id: String) -> SessionUsage? {
        sessionsAcrossModels.first { $0.conversationId == id }
    }

    func childSessions(of parent: SessionUsage) -> [SessionUsage] {
        let order = Dictionary(uniqueKeysWithValues: parent.childConversationIds.enumerated().map { ($1, $0) })
        return sessionsAcrossModels
            .filter { $0.parentConversationId == parent.conversationId }
            .sorted {
                let lhs = order[$0.conversationId] ?? Int.max
                let rhs = order[$1.conversationId] ?? Int.max
                if lhs != rhs { return lhs < rhs }
                return $0.lastTimestampMs > $1.lastTimestampMs
            }
    }

    func prompts(for session: SessionUsage) -> [PromptUsage] {
        let source = session.isSubagent ? subagentPrompts : prompts
        return source.filter { $0.conversationId == session.conversationId }
    }

    static let empty = UsageSnapshot(
        windowCostCents: 0,
        recentCostCents: 0,
        models: [],
        sessionsAcrossModels: [],
        prompts: [],
        subagentPrompts: [],
        skills: [],
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
    case spendUnavailable

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
        case .spendUnavailable:
            "Cursor did not report spend totals for this account."
        }
    }
}

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
}

struct TokenUsage: Decodable, Sendable, Hashable {
    let inputTokens: Int?
    let outputTokens: Int?
    let cacheWriteTokens: Int?
    let cacheReadTokens: Int?
    let totalCents: Double?
    let discountPercentOff: Double?
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

    var costDollars: Double { costCents / 100.0 }
}

struct UsageSnapshot: Sendable {
    let todayCostCents: Double
    let recentCostCents: Double
    let models: [ModelUsage]
    let eventCount: Int
    let fetchedAt: Date

    var todayDollars: Double { todayCostCents / 100.0 }
    var recentDollars: Double { recentCostCents / 100.0 }

    static let empty = UsageSnapshot(
        todayCostCents: 0,
        recentCostCents: 0,
        models: [],
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
            "Too many usage events to load for today."
        }
    }
}

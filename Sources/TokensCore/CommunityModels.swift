import Foundation

/// Minimal per-model spend for community upload.
public struct CommunityModelSpend: Sendable, Codable, Equatable {
    public let name: String
    public let spendCents: Int

    public init(name: String, spendCents: Int) {
        self.name = name
        self.spendCents = spendCents
    }
}

/// Rolling 24h aggregate uploaded to the community API.
public struct CommunitySnapshotPayload: Sendable, Codable, Equatable {
    public let participantId: String
    public let nickname: String?
    /// When renaming, the nickname previously stored for this participant (server reconciliation).
    public let previousNickname: String?
    public let windowHours: Int
    public let spendCents: Int
    public let models: [CommunityModelSpend]
    /// UTC calendar-day aggregates for operator analytics (today + yesterday).
    public let dailyReports: [CommunityDailyReport]?
    /// Cumulative UI interaction counts (panel opens vs tab changes), only when opted in.
    public let interactionStats: CommunityInteractionStats?
    /// Burnrate app version string, e.g. `0.0.25` or `0.0.25-dev`.
    public let clientVersion: String?

    public init(
        participantId: String,
        nickname: String?,
        previousNickname: String? = nil,
        windowHours: Int = 24,
        spendCents: Int,
        models: [CommunityModelSpend],
        dailyReports: [CommunityDailyReport]? = nil,
        interactionStats: CommunityInteractionStats? = nil,
        clientVersion: String? = nil
    ) {
        self.participantId = participantId
        self.nickname = nickname
        self.previousNickname = previousNickname
        self.windowHours = windowHours
        self.spendCents = spendCents
        self.models = models
        self.dailyReports = dailyReports
        self.interactionStats = interactionStats
        self.clientVersion = clientVersion
    }
}

/// Cumulative panel interaction metrics uploaded with community snapshots.
public struct CommunityInteractionStats: Sendable, Codable, Equatable {
    public var panelOpens: Int
    /// Per-surface tab/route change counts (e.g. "models", "sessions", "settings").
    public var tabChanges: [String: Int]

    public init(panelOpens: Int = 0, tabChanges: [String: Int] = [:]) {
        self.panelOpens = panelOpens
        self.tabChanges = tabChanges
    }

    public mutating func recordPanelOpen() {
        panelOpens += 1
    }

    public mutating func recordTabChange(_ tab: String) {
        tabChanges[tab, default: 0] += 1
    }
}

/// One row in the community leaderboard (up to 30 returned by the API).
public struct CommunityLeaderboardEntry: Sendable, Codable, Equatable {
    public let rank: Int
    public let nickname: String?
    public let spendCents: Int
    public let isYou: Bool

    public init(rank: Int, nickname: String?, spendCents: Int, isYou: Bool = false) {
        self.rank = rank
        self.nickname = nickname
        self.spendCents = spendCents
        self.isYou = isYou
    }
}

/// Rank response from GET /v1/community/rank.
public struct CommunityRankResponse: Sendable, Codable, Equatable {
    public let participantCount: Int
    public let rank: Int?
    public let yourSpendCents: Int
    public let medianSpendCents: Int?
    public let p25SpendCents: Int?
    public let p75SpendCents: Int?
    public let maxSpendCents: Int?
    public let leaderboardNear: [CommunityLeaderboardEntry]
    public let notEnoughParticipants: Bool

    public init(
        participantCount: Int,
        rank: Int?,
        yourSpendCents: Int,
        medianSpendCents: Int?,
        p25SpendCents: Int?,
        p75SpendCents: Int?,
        maxSpendCents: Int?,
        leaderboardNear: [CommunityLeaderboardEntry],
        notEnoughParticipants: Bool = false
    ) {
        self.participantCount = participantCount
        self.rank = rank
        self.yourSpendCents = yourSpendCents
        self.medianSpendCents = medianSpendCents
        self.p25SpendCents = p25SpendCents
        self.p75SpendCents = p75SpendCents
        self.maxSpendCents = maxSpendCents
        self.leaderboardNear = leaderboardNear
        self.notEnoughParticipants = notEnoughParticipants
    }
}

/// Event input for building a community snapshot (no session/prompt fields).
public struct CommunityCostEvent: Sendable, Equatable {
    public let timestampMs: Double
    public let model: String
    public let costCents: Double

    public init(timestampMs: Double, model: String, costCents: Double) {
        self.timestampMs = timestampMs
        self.model = model
        self.costCents = costCents
    }
}

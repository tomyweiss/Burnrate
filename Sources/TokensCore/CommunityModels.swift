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
    public let windowHours: Int
    public let spendCents: Int
    public let models: [CommunityModelSpend]
    /// Cumulative UI interaction counts (panel opens vs tab changes), only when opted in.
    public let interactionStats: CommunityInteractionStats?

    public init(
        participantId: String,
        nickname: String?,
        windowHours: Int = 24,
        spendCents: Int,
        models: [CommunityModelSpend],
        interactionStats: CommunityInteractionStats? = nil
    ) {
        self.participantId = participantId
        self.nickname = nickname
        self.windowHours = windowHours
        self.spendCents = spendCents
        self.models = models
        self.interactionStats = interactionStats
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

/// One row in the near-you leaderboard.
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

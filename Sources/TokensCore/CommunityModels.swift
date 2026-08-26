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
    /// Per-device membership secret; proves possession of this participant row.
    public let membershipSecret: String
    public let nickname: String?
    /// When renaming, the nickname previously stored for this participant (server reconciliation).
    public let previousNickname: String?
    /// When rotating credentials, the prior participant row to retire on the server.
    public let previousParticipantId: String?
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
        membershipSecret: String,
        nickname: String?,
        previousNickname: String? = nil,
        previousParticipantId: String? = nil,
        windowHours: Int = 24,
        spendCents: Int,
        models: [CommunityModelSpend],
        dailyReports: [CommunityDailyReport]? = nil,
        interactionStats: CommunityInteractionStats? = nil,
        clientVersion: String? = nil
    ) {
        self.participantId = participantId
        self.membershipSecret = membershipSecret
        self.nickname = nickname
        self.previousNickname = previousNickname
        self.previousParticipantId = previousParticipantId
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
    public let topModel: String?
    public let clientVersion: String?
    public let isYou: Bool

    public init(
        rank: Int,
        nickname: String?,
        spendCents: Int,
        topModel: String? = nil,
        clientVersion: String? = nil,
        isYou: Bool = false
    ) {
        self.rank = rank
        self.nickname = nickname
        self.spendCents = spendCents
        self.topModel = topModel
        self.clientVersion = clientVersion
        self.isYou = isYou
    }
}

/// Which community leaderboard window to display.
public struct CommunityRankWindow: Sendable, Hashable, Codable {
    public enum Kind: String, Sendable, Codable {
        case rolling24h
        case utcDay
    }

    public let kind: Kind
    /// UTC calendar day (`YYYY-MM-DD`) when `kind` is `.utcDay`.
    public let day: String?

    public static let rolling24h = CommunityRankWindow(kind: .rolling24h, day: nil)

    public static func utcDay(_ day: String) -> CommunityRankWindow {
        CommunityRankWindow(kind: .utcDay, day: day)
    }

    public init(kind: Kind, day: String?) {
        self.kind = kind
        self.day = day
    }

    public var apiDayParameter: String? {
        kind == .utcDay ? day : nil
    }
}

extension CommunityRankWindow {
    public static let maxDayLookback = 90

    public static func todayUTC(now: Date = Date()) -> CommunityRankWindow {
        .utcDay(CommunityDayFormat.utcDayString(for: now))
    }

    public static func yesterdayUTC(now: Date = Date()) -> CommunityRankWindow {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now) ?? now
        return .utcDay(CommunityDayFormat.utcDayString(for: yesterday))
    }

    public func shiftedDays(by offset: Int, now: Date = Date()) -> CommunityRankWindow? {
        guard kind == .utcDay, let day, let dayStartMs = CommunityDayFormat.utcDayStartMs(for: day) else {
            return nil
        }
        let shifted = Date(timeIntervalSince1970: dayStartMs / 1000 + Double(offset) * 86_400)
        let shiftedDay = CommunityDayFormat.utcDayString(for: shifted)
        let today = CommunityDayFormat.utcDayString(for: now)
        guard shiftedDay <= today else { return nil }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        guard let minDate = calendar.date(byAdding: .day, value: -Self.maxDayLookback, to: now) else {
            return nil
        }
        let minDay = CommunityDayFormat.utcDayString(for: minDate)
        guard shiftedDay >= minDay else { return nil }
        return .utcDay(shiftedDay)
    }

    public var canStepBackward: Bool {
        shiftedDays(by: -1) != nil
    }

    public var canStepForward: Bool {
        shiftedDays(by: 1) != nil
    }

    public func displayLabel(now: Date = Date()) -> String {
        switch kind {
        case .rolling24h:
            return "Live"
        case .utcDay:
            guard let day, let dayStartMs = CommunityDayFormat.utcDayStartMs(for: day) else {
                return "Day"
            }
            let date = Date(timeIntervalSince1970: dayStartMs / 1000)
            let formatter = DateFormatter()
            formatter.timeZone = TimeZone(secondsFromGMT: 0)
            formatter.dateFormat = "MMM d"
            let label = formatter.string(from: date)
            if day == CommunityDayFormat.utcDayString(for: now) {
                return "Today · \(label)"
            }
            if day == CommunityRankWindow.yesterdayUTC(now: now).day {
                return "Yesterday · \(label)"
            }
            return label
        }
    }

    public func spendCaption(now: Date = Date()) -> String {
        switch kind {
        case .rolling24h:
            return "24H SPEND"
        case .utcDay:
            if day == CommunityDayFormat.utcDayString(for: now) {
                return "TODAY SPEND"
            }
            return "DAY SPEND"
        }
    }
}

/// Rank response from GET /v1/community/rank.
public struct CommunityRankResponse: Sendable, Codable, Equatable {
    public let window: String
    public let day: String?
    public let isProvisional: Bool
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
        window: String = "rolling24h",
        day: String? = nil,
        isProvisional: Bool = false,
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
        self.window = window
        self.day = day
        self.isProvisional = isProvisional
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

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        window = try container.decodeIfPresent(String.self, forKey: .window) ?? "rolling24h"
        day = try container.decodeIfPresent(String.self, forKey: .day)
        isProvisional = try container.decodeIfPresent(Bool.self, forKey: .isProvisional) ?? false
        participantCount = try container.decode(Int.self, forKey: .participantCount)
        rank = try container.decodeIfPresent(Int.self, forKey: .rank)
        yourSpendCents = try container.decode(Int.self, forKey: .yourSpendCents)
        medianSpendCents = try container.decodeIfPresent(Int.self, forKey: .medianSpendCents)
        p25SpendCents = try container.decodeIfPresent(Int.self, forKey: .p25SpendCents)
        p75SpendCents = try container.decodeIfPresent(Int.self, forKey: .p75SpendCents)
        maxSpendCents = try container.decodeIfPresent(Int.self, forKey: .maxSpendCents)
        leaderboardNear = try container.decode([CommunityLeaderboardEntry].self, forKey: .leaderboardNear)
        notEnoughParticipants = try container.decodeIfPresent(Bool.self, forKey: .notEnoughParticipants) ?? false
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(window, forKey: .window)
        try container.encodeIfPresent(day, forKey: .day)
        try container.encode(isProvisional, forKey: .isProvisional)
        try container.encode(participantCount, forKey: .participantCount)
        try container.encodeIfPresent(rank, forKey: .rank)
        try container.encode(yourSpendCents, forKey: .yourSpendCents)
        try container.encodeIfPresent(medianSpendCents, forKey: .medianSpendCents)
        try container.encodeIfPresent(p25SpendCents, forKey: .p25SpendCents)
        try container.encodeIfPresent(p75SpendCents, forKey: .p75SpendCents)
        try container.encodeIfPresent(maxSpendCents, forKey: .maxSpendCents)
        try container.encode(leaderboardNear, forKey: .leaderboardNear)
        try container.encode(notEnoughParticipants, forKey: .notEnoughParticipants)
    }

    private enum CodingKeys: String, CodingKey {
        case window, day, isProvisional, participantCount, rank, yourSpendCents
        case medianSpendCents, p25SpendCents, p75SpendCents, maxSpendCents
        case leaderboardNear, notEnoughParticipants
    }

    public var rankWindow: CommunityRankWindow {
        if window == "utcDay", let day {
            return .utcDay(day)
        }
        return .rolling24h
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

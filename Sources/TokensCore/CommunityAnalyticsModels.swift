import Foundation

/// How Cursor billed a usage event (upload-safe subset).
public enum CommunityBillingKind: String, Sendable, Codable, Equatable {
    case included
    case usageBased
    case errored
    case unknown
}

/// Coarse regional bucket derived from UTC offset on the client; offset never uploaded.
public enum CommunityRegionBucket: String, Sendable, Codable, Equatable {
    case americas
    case emea
    case apac
}

/// Usage event fields needed for community analytics (no session/prompt data).
public struct CommunityAnalyticsEvent: Sendable, Equatable {
    public let timestampMs: Double
    public let model: String
    public let costCents: Double
    public let billingKind: CommunityBillingKind
    public let tokenInput: Int
    public let tokenOutput: Int
    public let tokenCacheRead: Int
    public let tokenCacheWrite: Int

    public init(
        timestampMs: Double,
        model: String,
        costCents: Double,
        billingKind: CommunityBillingKind,
        tokenInput: Int = 0,
        tokenOutput: Int = 0,
        tokenCacheRead: Int = 0,
        tokenCacheWrite: Int = 0
    ) {
        self.timestampMs = timestampMs
        self.model = model
        self.costCents = costCents
        self.billingKind = billingKind
        self.tokenInput = tokenInput
        self.tokenOutput = tokenOutput
        self.tokenCacheRead = tokenCacheRead
        self.tokenCacheWrite = tokenCacheWrite
    }
}

/// Allow-listed settings snapshot for adoption analytics.
public struct CommunityClientConfig: Sendable, Codable, Equatable {
    public let timelinePreset: String
    public let refreshIntervalSeconds: Int
    public let anomalyThresholdDollars: Int
    public let anomalyWindowMinutes: Int
    public let hideAmountInMenuBar: Bool
    public let autoCheckForUpdates: Bool
    public let launchAtLogin: Bool
    public let hiddenTabs: [String]
    public let customTimezone: Bool
    public let billingDayOfMonth: Int

    public init(
        timelinePreset: String,
        refreshIntervalSeconds: Int,
        anomalyThresholdDollars: Int,
        anomalyWindowMinutes: Int,
        hideAmountInMenuBar: Bool,
        autoCheckForUpdates: Bool,
        launchAtLogin: Bool,
        hiddenTabs: [String],
        customTimezone: Bool,
        billingDayOfMonth: Int
    ) {
        self.timelinePreset = timelinePreset
        self.refreshIntervalSeconds = refreshIntervalSeconds
        self.anomalyThresholdDollars = anomalyThresholdDollars
        self.anomalyWindowMinutes = anomalyWindowMinutes
        self.hideAmountInMenuBar = hideAmountInMenuBar
        self.autoCheckForUpdates = autoCheckForUpdates
        self.launchAtLogin = launchAtLogin
        self.hiddenTabs = hiddenTabs
        self.customTimezone = customTimezone
        self.billingDayOfMonth = billingDayOfMonth
    }
}

/// One UTC calendar day aggregate for operator analytics.
public struct CommunityDailyReport: Sendable, Codable, Equatable {
    public let day: String
    public let spendCents: Int
    public let models: [CommunityModelSpend]
    public let eventCount: Int
    public let onDemandCents: Int
    public let includedCents: Int
    public let erroredEventCount: Int
    public let tokenInput: Int
    public let tokenOutput: Int
    public let tokenCacheRead: Int
    public let tokenCacheWrite: Int
    public let uniqueModels: Int
    public let topModel: String?
    public let peakHourUtc: Int
    public let activeHourCount: Int
    public let regionBucket: CommunityRegionBucket
    public let panelOpens: Int
    public let tabChanges: [String: Int]
    public let refreshAttempts: Int
    public let refreshFailures: Int
    public let nicknameSource: String
    public let clientConfig: CommunityClientConfig

    public init(
        day: String,
        spendCents: Int,
        models: [CommunityModelSpend],
        eventCount: Int,
        onDemandCents: Int,
        includedCents: Int,
        erroredEventCount: Int,
        tokenInput: Int,
        tokenOutput: Int,
        tokenCacheRead: Int,
        tokenCacheWrite: Int,
        uniqueModels: Int,
        topModel: String?,
        peakHourUtc: Int,
        activeHourCount: Int,
        regionBucket: CommunityRegionBucket,
        panelOpens: Int,
        tabChanges: [String: Int],
        refreshAttempts: Int,
        refreshFailures: Int,
        nicknameSource: String,
        clientConfig: CommunityClientConfig
    ) {
        self.day = day
        self.spendCents = spendCents
        self.models = models
        self.eventCount = eventCount
        self.onDemandCents = onDemandCents
        self.includedCents = includedCents
        self.erroredEventCount = erroredEventCount
        self.tokenInput = tokenInput
        self.tokenOutput = tokenOutput
        self.tokenCacheRead = tokenCacheRead
        self.tokenCacheWrite = tokenCacheWrite
        self.uniqueModels = uniqueModels
        self.topModel = topModel
        self.peakHourUtc = peakHourUtc
        self.activeHourCount = activeHourCount
        self.regionBucket = regionBucket
        self.panelOpens = panelOpens
        self.tabChanges = tabChanges
        self.refreshAttempts = refreshAttempts
        self.refreshFailures = refreshFailures
        self.nicknameSource = nicknameSource
        self.clientConfig = clientConfig
    }
}

public enum CommunityDayFormat {
    public static func utcDayString(for date: Date) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", components.year ?? 0, components.month ?? 0, components.day ?? 0)
    }

    public static func utcDayStartMs(for day: String) -> Double? {
        let parts = day.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var components = DateComponents()
        components.year = parts[0]
        components.month = parts[1]
        components.day = parts[2]
        guard let date = calendar.date(from: components) else { return nil }
        return date.timeIntervalSince1970 * 1000
    }

    /// Maps system UTC offset to a coarse regional bucket; offset is never uploaded.
    public static func regionBucket(now: Date = Date()) -> CommunityRegionBucket {
        let offsetSeconds = TimeZone.current.secondsFromGMT(for: now)
        let offsetHours = offsetSeconds / 3600
        if offsetHours >= -12, offsetHours <= -3 {
            return .americas
        }
        if offsetHours >= -2, offsetHours <= 4 {
            return .emea
        }
        return .apac
    }

    public static func reportDays(now: Date = Date()) -> [String] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let today = utcDayString(for: now)
        guard let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now) else {
            return [today]
        }
        let yesterday = utcDayString(for: yesterdayDate)
        return [today, yesterday]
    }
}

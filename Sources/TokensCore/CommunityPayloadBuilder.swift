import Foundation

public enum CommunityPayloadBuilder {
    public static let windowHours = 24
    /// Minimum fetch window so yesterday's UTC day is always available locally.
    public static let analyticsFetchHours = 48

    /// Usage-event fetch start: at least `analyticsFetchHours` before `now`, even when the UI
    /// window is shorter (e.g. "Today" since midnight).
    public static func eventFetchStart(
        displayWindowStart: Date,
        now: Date = Date()
    ) -> Date {
        let analyticsStart = now.addingTimeInterval(-Double(analyticsFetchHours) * 3600)
        return min(displayWindowStart, analyticsStart)
    }

    public struct DailyEngagement: Sendable, Equatable {
        public let panelOpens: Int
        public let tabChanges: [String: Int]
        public let refreshAttempts: Int
        public let refreshFailures: Int

        public init(
            panelOpens: Int = 0,
            tabChanges: [String: Int] = [:],
            refreshAttempts: Int = 0,
            refreshFailures: Int = 0
        ) {
            self.panelOpens = panelOpens
            self.tabChanges = tabChanges
            self.refreshAttempts = refreshAttempts
            self.refreshFailures = refreshFailures
        }
    }

    /// Build rolling 24h snapshot plus UTC daily reports for today and yesterday.
    public static func build(
        participantId: String,
        nickname: String?,
        previousNickname: String? = nil,
        events: [CommunityAnalyticsEvent],
        now: Date = Date(),
        interactionStats: CommunityInteractionStats? = nil,
        dailyEngagement: (String) -> DailyEngagement = { _ in DailyEngagement() },
        nicknameSource: String,
        clientConfig: CommunityClientConfig,
        clientVersion: String? = nil
    ) -> CommunitySnapshotPayload {
        let rollingStartMs = now.addingTimeInterval(-Double(windowHours) * 3600).timeIntervalSince1970 * 1000
        let endMs = now.timeIntervalSince1970 * 1000

        var totalCents: Double = 0
        var byModel: [String: Double] = [:]

        for event in events {
            guard event.timestampMs >= rollingStartMs, event.timestampMs <= endMs else { continue }
            totalCents += event.costCents
            let modelName = event.model.isEmpty ? "unknown" : event.model
            byModel[modelName, default: 0] += event.costCents
        }

        let models = byModel
            .map { CommunityModelSpend(name: $0.key, spendCents: Int($0.value.rounded())) }
            .sorted { $0.spendCents > $1.spendCents }

        let regionBucket = CommunityDayFormat.regionBucket(now: now)
        let dailyReports = CommunityDayFormat.reportDays(now: now).map { day in
            buildDailyReport(
                day: day,
                events: events,
                now: now,
                engagement: dailyEngagement(day),
                regionBucket: regionBucket,
                nicknameSource: nicknameSource,
                clientConfig: clientConfig
            )
        }

        return CommunitySnapshotPayload(
            participantId: participantId,
            nickname: nickname,
            previousNickname: previousNickname,
            windowHours: windowHours,
            spendCents: Int(totalCents.rounded()),
            models: models,
            dailyReports: dailyReports,
            interactionStats: interactionStats,
            clientVersion: clientVersion
        )
    }

    /// Backward-compatible build from legacy cost-only events.
    public static func build(
        participantId: String,
        nickname: String?,
        previousNickname: String? = nil,
        events: [CommunityCostEvent],
        now: Date = Date(),
        interactionStats: CommunityInteractionStats? = nil,
        clientVersion: String? = nil
    ) -> CommunitySnapshotPayload {
        let analyticsEvents = events.map {
            CommunityAnalyticsEvent(
                timestampMs: $0.timestampMs,
                model: $0.model,
                costCents: $0.costCents,
                billingKind: .unknown
            )
        }
        let defaultConfig = CommunityClientConfig(
            timelinePreset: "today",
            refreshIntervalSeconds: 60,
            anomalyThresholdDollars: 10,
            anomalyWindowMinutes: 10,
            hideAmountInMenuBar: false,
            autoCheckForUpdates: true,
            launchAtLogin: false,
            hiddenTabs: [],
            customTimezone: false,
            billingDayOfMonth: 1
        )
        return build(
            participantId: participantId,
            nickname: nickname,
            previousNickname: previousNickname,
            events: analyticsEvents,
            now: now,
            interactionStats: interactionStats,
            nicknameSource: "anonymous",
            clientConfig: defaultConfig,
            clientVersion: clientVersion
        )
    }

    static func buildDailyReport(
        day: String,
        events: [CommunityAnalyticsEvent],
        now: Date,
        engagement: DailyEngagement,
        regionBucket: CommunityRegionBucket,
        nicknameSource: String,
        clientConfig: CommunityClientConfig
    ) -> CommunityDailyReport {
        guard let dayStartMs = CommunityDayFormat.utcDayStartMs(for: day) else {
            return emptyDailyReport(
                day: day,
                engagement: engagement,
                regionBucket: regionBucket,
                nicknameSource: nicknameSource,
                clientConfig: clientConfig
            )
        }

        let today = CommunityDayFormat.utcDayString(for: now)
        let dayEndMs: Double
        if day == today {
            dayEndMs = now.timeIntervalSince1970 * 1000
        } else if let nextDayStart = CommunityDayFormat.utcDayStartMs(for: day),
                  let nextMs = Calendar.utc.date(byAdding: .day, value: 1, to: Date(timeIntervalSince1970: nextDayStart / 1000))?.timeIntervalSince1970 {
            dayEndMs = nextMs * 1000
        } else {
            dayEndMs = dayStartMs + 86_400_000
        }

        var totalCents: Double = 0
        var onDemandCents: Double = 0
        var includedCents: Double = 0
        var erroredCount = 0
        var eventCount = 0
        var tokenInput = 0
        var tokenOutput = 0
        var tokenCacheRead = 0
        var tokenCacheWrite = 0
        var byModel: [String: Double] = [:]
        var spendByHour: [Int: Double] = [:]
        var activeHours: Set<Int> = []

        for event in events {
            guard event.timestampMs >= dayStartMs, event.timestampMs < dayEndMs else { continue }

            if event.billingKind == .errored {
                erroredCount += 1
                continue
            }

            eventCount += 1
            totalCents += event.costCents
            let modelName = event.model.isEmpty ? "unknown" : event.model
            byModel[modelName, default: 0] += event.costCents

            switch event.billingKind {
            case .usageBased:
                onDemandCents += event.costCents
            case .included:
                includedCents += event.costCents
            case .errored, .unknown:
                break
            }

            tokenInput += event.tokenInput
            tokenOutput += event.tokenOutput
            tokenCacheRead += event.tokenCacheRead
            tokenCacheWrite += event.tokenCacheWrite

            let hour = utcHour(forMs: event.timestampMs)
            spendByHour[hour, default: 0] += event.costCents
            if event.costCents > 0 {
                activeHours.insert(hour)
            }
        }

        let models = byModel
            .map { CommunityModelSpend(name: $0.key, spendCents: Int($0.value.rounded())) }
            .sorted { $0.spendCents > $1.spendCents }

        let topModel = models.first?.name
        let peakHour = spendByHour.max(by: { $0.value < $1.value })?.key ?? 0

        return CommunityDailyReport(
            day: day,
            spendCents: Int(totalCents.rounded()),
            models: models,
            eventCount: eventCount,
            onDemandCents: Int(onDemandCents.rounded()),
            includedCents: Int(includedCents.rounded()),
            erroredEventCount: erroredCount,
            tokenInput: tokenInput,
            tokenOutput: tokenOutput,
            tokenCacheRead: tokenCacheRead,
            tokenCacheWrite: tokenCacheWrite,
            uniqueModels: models.count,
            topModel: topModel,
            peakHourUtc: peakHour,
            activeHourCount: activeHours.count,
            regionBucket: regionBucket,
            panelOpens: engagement.panelOpens,
            tabChanges: engagement.tabChanges,
            refreshAttempts: engagement.refreshAttempts,
            refreshFailures: engagement.refreshFailures,
            nicknameSource: nicknameSource,
            clientConfig: clientConfig
        )
    }

    private static func utcHour(forMs ms: Double) -> Int {
        let date = Date(timeIntervalSince1970: ms / 1000)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar.component(.hour, from: date)
    }

    private static func emptyDailyReport(
        day: String,
        engagement: DailyEngagement,
        regionBucket: CommunityRegionBucket,
        nicknameSource: String,
        clientConfig: CommunityClientConfig
    ) -> CommunityDailyReport {
        CommunityDailyReport(
            day: day,
            spendCents: 0,
            models: [],
            eventCount: 0,
            onDemandCents: 0,
            includedCents: 0,
            erroredEventCount: 0,
            tokenInput: 0,
            tokenOutput: 0,
            tokenCacheRead: 0,
            tokenCacheWrite: 0,
            uniqueModels: 0,
            topModel: nil,
            peakHourUtc: 0,
            activeHourCount: 0,
            regionBucket: regionBucket,
            panelOpens: engagement.panelOpens,
            tabChanges: engagement.tabChanges,
            refreshAttempts: engagement.refreshAttempts,
            refreshFailures: engagement.refreshFailures,
            nicknameSource: nicknameSource,
            clientConfig: clientConfig
        )
    }
}

private extension Calendar {
    static var utc: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }
}

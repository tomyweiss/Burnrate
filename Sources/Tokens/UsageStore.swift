import Foundation
import AppKit
import TokensCore

@MainActor
@Observable
final class UsageStore {
    private(set) var snapshot: UsageSnapshot = .empty
    private(set) var isLoading = false
    private(set) var hasCompletedFetch = false
    private(set) var lastError: String?
    private(set) var isSpikeActive = false
    private(set) var notificationFeedback: String?
    private(set) var isShowingCachedData = false
    private(set) var communityAnalyticsEvents: [CommunityAnalyticsEvent] = []

    private(set) var spendSummary: SpendSummary?

    private let api = CursorAPI()
    private let anomalyMonitor: AnomalyMonitor?
    private let settings: SettingsStore
    private weak var communityStore: CommunityStore?
    private var pollTask: Task<Void, Never>?
    private var rates: SpendRates = .unavailable
    let refreshMetrics = RefreshMetricsTracker()

    /// Pricing only moves when the billing cycle rolls over, and calibrating costs
    /// a full-cycle event fetch, so it runs far less often than the usage poll.
    private let calibrationInterval: TimeInterval = 30 * 60

    init(settings: SettingsStore, enableAnomalyAlerts: Bool = true) {
        self.settings = settings
        self.anomalyMonitor = enableAnomalyAlerts ? AnomalyMonitor() : nil
        if enableAnomalyAlerts {
            NotificationPresenter.shared.install()
        }
    }

    func setCommunityStore(_ store: CommunityStore?) {
        communityStore = store
    }

    var isStale: Bool {
        guard hasCompletedFetch, snapshot.fetchedAt != .distantPast else { return false }
        let limit = max(15, settings.refreshIntervalSeconds) * 3
        return Date().timeIntervalSince(snapshot.fetchedAt) > limit
    }

    /// Matches the burn-pill severity for the rolling spike window.
    var burnLevel: BurnLevel {
        BurnLevel.level(
            recentDollars: snapshot.recentDollars,
            thresholdDollars: settings.anomalyThresholdDollars,
            hasError: lastError != nil && !isShowingCachedData
        )
    }

    var menuSymbolName: String {
        burnLevel.symbolName
    }

    var menuBarIcon: NSImage {
        if AppIdentity.isDevBuild {
            return burnLevel.menuBarImageWithDevDot()
        }
        return burnLevel.menuBarImage()
    }

    var menuAmountText: String? {
        if settings.hideAmountInMenuBar { return nil }
        if !hasCompletedFetch, lastError == nil {
            return "$—.——"
        }
        return MoneyFormat.dollars(snapshot.windowDollars)
    }

    func start() {
        loadCachedSnapshotIfAvailable()
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            await self?.anomalyMonitor?.requestAuthorizationIfNeeded()
            while let self, !Task.isCancelled {
                await self.refresh()
                let seconds = max(15, self.settings.refreshIntervalSeconds)
                try? await Task.sleep(for: .seconds(seconds))
            }
        }
    }

    func stop() {
        pollTask?.cancel()
        pollTask = nil
    }

    func refresh() async {
        isLoading = true
        defer { isLoading = false }

        refreshMetrics.recordAttempt()

        do {
            let credentials = try TokenProvider.loadSessionCredentials()
            let now = Date()
            let window = settings.usageWindow
            let range = window.dateRange(now: now)
            let fetchStart = CommunityPayloadBuilder.eventFetchStart(
                displayWindowStart: range.start,
                now: now
            )
            let startMs = Int64(fetchStart.timeIntervalSince1970 * 1000)
            let endMs = Int64(range.end.timeIntervalSince1970 * 1000)

            let events = try await api.fetchUsageEvents(
                credentials: credentials,
                startMs: startMs,
                endMs: endMs
            )

            await refreshSpendCalibrationIfNeeded(credentials: credentials, now: now)

            // Aggregation scans local Cursor SQLite data (session + prompt
            // catalogs); keep it off the main thread.
            let recentWindowMinutes = settings.anomalyWindowMinutes
            let activeRates = rates
            let next = await Task.detached(priority: .userInitiated) {
                Aggregator.snapshot(
                    events: events,
                    now: now,
                    window: window,
                    recentWindowMinutes: recentWindowMinutes,
                    rates: activeRates
                )
            }.value
            snapshot = next
            communityAnalyticsEvents = Self.communityAnalyticsEvents(from: events, now: now, rates: activeRates)
            lastError = nil
            isShowingCachedData = false
            hasCompletedFetch = true
            isSpikeActive = next.recentCostCents >= settings.anomalyThresholdDollars * 100
            UsageRefreshCache.save(
                events: events,
                settings: settings,
                recentWindowMinutes: recentWindowMinutes,
                fetchedAt: next.fetchedAt
            )
            await anomalyMonitor?.evaluate(snapshot: next, settings: settings)
            await communityStore?.handleUsageRefreshIfNeeded()
        } catch {
            lastError = NetworkMessages.userMessage(for: error, cachedDataAvailable: isShowingCachedData)
            hasCompletedFetch = true
            refreshMetrics.recordFailure()
            FailureReporter.report(error: error, source: .usage)
            // Keep last good snapshot and amount visible.
        }
    }

    func sendTestNotification() async {
        guard let anomalyMonitor else {
            notificationFeedback = "Notifications are unavailable."
            return
        }
        notificationFeedback = await anomalyMonitor.sendTestNotification(settings: settings)
    }

    /// Prices request units in dollars for plans where Cursor reports no per-event cost.
    ///
    /// Cursor only exposes real spend as a billing-cycle total, so the cycle's
    /// events are refetched to work out what one request unit is worth.
    private func refreshSpendCalibrationIfNeeded(
        credentials: SessionCredentials,
        now: Date
    ) async {
        guard now.timeIntervalSince(rates.computedAt) > calibrationInterval else { return }

        do {
            let summary = try await api.fetchSpendSummary(credentials: credentials)
            let cycleStart = summary.cycleStartMs > 0
                ? Int64(summary.cycleStartMs)
                : Int64(now.addingTimeInterval(-30 * 24 * 60 * 60).timeIntervalSince1970 * 1000)
            let cycleEvents = try await api.fetchUsageEvents(
                credentials: credentials,
                startMs: cycleStart,
                endMs: Int64(now.timeIntervalSince1970 * 1000)
            )
            let calibrated = SpendRates.calibrate(summary: summary, cycleEvents: cycleEvents)
            guard calibrated.isAvailable else { return }
            rates = calibrated
            spendSummary = summary
        } catch {
            // Falls back to Cursor's own per-event amounts; not worth surfacing.
            FailureReporter.report(error: error, source: .usage)
        }
    }

    private func loadCachedSnapshotIfAvailable() {
        let recentWindowMinutes = settings.anomalyWindowMinutes
        guard let cache = UsageRefreshCache.load(
            matching: settings,
            recentWindowMinutes: recentWindowMinutes
        ) else {
            return
        }

        let now = Date()
        let window = settings.usageWindow
        let cachedSnapshot = Aggregator.snapshot(
            events: cache.events,
            now: now,
            window: window,
            recentWindowMinutes: recentWindowMinutes,
            rates: rates
        )
        snapshot = UsageSnapshot(
            windowCostCents: cachedSnapshot.windowCostCents,
            recentCostCents: cachedSnapshot.recentCostCents,
            models: cachedSnapshot.models,
            sessionsAcrossModels: cachedSnapshot.sessionsAcrossModels,
            prompts: cachedSnapshot.prompts,
            subagentPrompts: cachedSnapshot.subagentPrompts,
            skills: cachedSnapshot.skills,
            sparklineCostCents: cachedSnapshot.sparklineCostCents,
            window: cachedSnapshot.window,
            eventCount: cachedSnapshot.eventCount,
            fetchedAt: cache.fetchedAt
        )
        communityAnalyticsEvents = Self.communityAnalyticsEvents(from: cache.events, now: now, rates: rates)
        hasCompletedFetch = true
        isShowingCachedData = true
    }

    static func communityAnalyticsEvents(
        from events: [UsageEvent],
        now: Date = Date(),
        rates: SpendRates = .unavailable
    ) -> [CommunityAnalyticsEvent] {
        let cutoffMs = now.addingTimeInterval(-Double(CommunityPayloadBuilder.analyticsFetchHours) * 3600)
            .timeIntervalSince1970 * 1000
        return events.compactMap { event in
            guard event.timestampMs >= cutoffMs else { return nil }
            let model = event.model?.isEmpty == false ? event.model! : "unknown"
            return CommunityAnalyticsEvent(
                timestampMs: event.timestampMs,
                model: model,
                costCents: event.costCents(using: rates),
                billingKind: mapBillingKind(event.billingKind),
                tokenInput: event.inputTokens,
                tokenOutput: event.outputTokens,
                tokenCacheRead: event.cacheReadTokens,
                tokenCacheWrite: event.cacheWriteTokens
            )
        }
    }

    private static func mapBillingKind(_ kind: BillingKind) -> CommunityBillingKind {
        switch kind {
        case .included: return .included
        case .usageBased: return .usageBased
        case .errored: return .errored
        case .unknown: return .unknown
        }
    }
}

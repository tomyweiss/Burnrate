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
    private(set) var communityDailySkills: [String: [CommunitySkillSpend]] = [:]

    private(set) var spendSummary: SpendSummary?

    private let api = CursorAPI()
    private let anomalyMonitor: AnomalyMonitor?
    private let settings: SettingsStore
    private weak var communityStore: CommunityStore?
    private var pollTask: Task<Void, Never>?
    private var eventCache = EventWindowCache()
    private var refreshGeneration = 0
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
        // MenuBarExtra recreates panel content on every click; don't re-hydrate.
        guard pollTask == nil else { return }
        if !hasCompletedFetch {
            isLoading = true
        }
        pollTask = Task { [weak self] in
            await self?.anomalyMonitor?.requestAuthorizationIfNeeded()
            await self?.hydrateFromCacheIfNeeded()
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

    func refresh(reuseEventsIfPossible: Bool = false) async {
        refreshGeneration += 1
        let generation = refreshGeneration

        let now = Date()
        let window = settings.usageWindow
        let range = window.dateRange(now: now)
        let fetchStart = CommunityPayloadBuilder.eventFetchStart(
            displayWindowStart: range.start,
            now: now
        )
        let startMs = fetchStart.timeIntervalSince1970 * 1000
        let endMs = range.end.timeIntervalSince1970 * 1000
        let canReuse = reuseEventsIfPossible && eventCache.covers(startMs: startMs, endMs: endMs)

        if !canReuse {
            isLoading = true
        }
        defer {
            if generation == refreshGeneration {
                isLoading = false
            }
        }

        refreshMetrics.recordAttempt()

        do {
            let credentials = try TokenProvider.loadSessionCredentials()

            let events: [UsageEvent]
            if canReuse {
                events = eventCache.events
            } else {
                events = try await api.fetchUsageEvents(
                    credentials: credentials,
                    startMs: Int64(startMs),
                    endMs: Int64(endMs)
                )
                guard generation == refreshGeneration else { return }
                mergeFetchedEvents(events, startMs: startMs, endMs: endMs)
            }

            let recentWindowMinutes = settings.anomalyWindowMinutes
            let activeRates = rates
            let cachedEvents = events

            let cheap = await Task.detached(priority: .userInitiated) {
                Aggregator.snapshot(
                    events: cachedEvents,
                    now: now,
                    window: window,
                    recentWindowMinutes: recentWindowMinutes,
                    rates: activeRates,
                    includePrompts: false
                )
            }.value
            guard generation == refreshGeneration else { return }

            applySnapshot(
                cheap,
                events: events,
                now: now,
                rates: activeRates,
                fetchedAt: cheap.fetchedAt
            )
            isLoading = false

            await refreshSpendCalibrationIfNeeded(
                credentials: credentials,
                now: now,
                availableEvents: events,
                availableStartMs: eventCache.startMs
            )
            guard generation == refreshGeneration else { return }

            let pricedRates = rates
            let full = await Task.detached(priority: .userInitiated) {
                Aggregator.snapshot(
                    events: cachedEvents,
                    now: now,
                    window: window,
                    recentWindowMinutes: recentWindowMinutes,
                    rates: pricedRates,
                    includePrompts: true
                )
            }.value
            guard generation == refreshGeneration else { return }

            applySnapshot(
                full,
                events: events,
                now: now,
                rates: pricedRates,
                fetchedAt: full.fetchedAt
            )
            UsageRefreshCache.save(
                events: eventCache.events,
                settings: settings,
                recentWindowMinutes: recentWindowMinutes,
                fetchedAt: full.fetchedAt,
                fetchStartMs: eventCache.startMs,
                fetchEndMs: eventCache.endMs
            )
            await anomalyMonitor?.evaluate(snapshot: full, settings: settings)
            await communityStore?.handleUsageRefreshIfNeeded()
        } catch {
            guard generation == refreshGeneration else { return }
            lastError = NetworkMessages.userMessage(for: error, cachedDataAvailable: isShowingCachedData)
            hasCompletedFetch = true
            refreshMetrics.recordFailure()
            FailureReporter.report(error: error, source: .usage)
        }
    }

    private func mergeFetchedEvents(_ events: [UsageEvent], startMs: Double, endMs: Double) {
        if eventCache.isEmpty || startMs <= eventCache.startMs {
            eventCache = EventWindowCache(events: events, startMs: startMs, endMs: endMs)
            return
        }
        let kept = eventCache.events.filter { $0.timestampMs < startMs }
        eventCache = EventWindowCache(
            events: kept + events,
            startMs: eventCache.startMs,
            endMs: max(eventCache.endMs, endMs)
        )
    }

    private func applySnapshot(
        _ next: UsageSnapshot,
        events: [UsageEvent],
        now: Date,
        rates: SpendRates,
        fetchedAt: Date
    ) {
        snapshot = UsageSnapshot(
            windowCostCents: next.windowCostCents,
            recentCostCents: next.recentCostCents,
            models: next.models,
            sessionsAcrossModels: next.sessionsAcrossModels,
            prompts: next.prompts,
            subagentPrompts: next.subagentPrompts,
            skills: next.skills,
            sparklineCostCents: next.sparklineCostCents,
            window: next.window,
            eventCount: next.eventCount,
            fetchedAt: fetchedAt
        )
        communityAnalyticsEvents = Self.communityAnalyticsEvents(from: events, now: now, rates: rates)
        communityDailySkills = Aggregator.communityDailySkills(events: events, now: now, rates: rates)
        lastError = nil
        isShowingCachedData = false
        hasCompletedFetch = true
        isSpikeActive = next.recentCostCents >= settings.anomalyThresholdDollars * 100
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
        now: Date,
        availableEvents: [UsageEvent],
        availableStartMs: Double
    ) async {
        guard now.timeIntervalSince(rates.computedAt) > calibrationInterval else { return }

        do {
            let summary = try await api.fetchSpendSummary(credentials: credentials)
            let cycleStart = summary.cycleStartMs > 0
                ? Int64(summary.cycleStartMs)
                : Int64(now.addingTimeInterval(-30 * 24 * 60 * 60).timeIntervalSince1970 * 1000)
            let cycleEvents: [UsageEvent]
            if availableStartMs <= Double(cycleStart) + 60_000 {
                cycleEvents = availableEvents.filter { $0.timestampMs >= Double(cycleStart) }
            } else {
                cycleEvents = try await api.fetchUsageEvents(
                    credentials: credentials,
                    startMs: cycleStart,
                    endMs: Int64(now.timeIntervalSince1970 * 1000)
                )
            }
            let calibrated = SpendRates.calibrate(summary: summary, cycleEvents: cycleEvents)
            guard calibrated.isAvailable else { return }
            rates = calibrated
            spendSummary = summary
        } catch {
            FailureReporter.report(error: error, source: .usage)
        }
    }

    private func hydrateFromCacheIfNeeded() async {
        guard !hasCompletedFetch else { return }

        let recentWindowMinutes = settings.anomalyWindowMinutes
        let window = settings.usageWindow
        let activeRates = rates
        let now = Date()
        let range = window.dateRange(now: now)
        let fetchStart = CommunityPayloadBuilder.eventFetchStart(
            displayWindowStart: range.start,
            now: now
        )
        let neededStartMs = fetchStart.timeIntervalSince1970 * 1000
        let neededEndMs = range.end.timeIntervalSince1970 * 1000

        struct CacheHydration: Sendable {
            let snapshot: UsageSnapshot?
            let cache: EventWindowCache
            let fetchedAt: Date
            let events: [UsageEvent]
        }

        let loaded = await Task.detached(priority: .userInitiated) {
            guard let payload = UsageRefreshCache.load() else { return nil as CacheHydration? }
            let cache = EventWindowCache(
                events: payload.events,
                startMs: payload.resolvedStartMs,
                endMs: payload.resolvedEndMs
            )
            let snapshot: UsageSnapshot?
            if cache.covers(startMs: neededStartMs, endMs: neededEndMs) {
                snapshot = Aggregator.snapshot(
                    events: payload.events,
                    now: now,
                    window: window,
                    recentWindowMinutes: recentWindowMinutes,
                    rates: activeRates,
                    includePrompts: false
                )
            } else {
                snapshot = nil
            }
            return CacheHydration(
                snapshot: snapshot,
                cache: cache,
                fetchedAt: payload.fetchedAt,
                events: payload.events
            )
        }.value

        guard let loaded, !hasCompletedFetch else { return }

        eventCache = loaded.cache
        guard let cachedSnapshot = loaded.snapshot else { return }

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
            fetchedAt: loaded.fetchedAt
        )
        communityAnalyticsEvents = Self.communityAnalyticsEvents(
            from: loaded.events,
            now: now,
            rates: activeRates
        )
        communityDailySkills = Aggregator.communityDailySkills(
            events: loaded.events,
            now: now,
            rates: activeRates
        )
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

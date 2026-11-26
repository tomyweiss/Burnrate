import Foundation
import TokensCore

@MainActor
@Observable
final class ClaudeCodeStore {
    private(set) var snapshot: UsageSnapshot = .empty
    private(set) var isInstalled = false
    private(set) var hasCompletedFetch = false
    private(set) var isLoading = false
    /// Nil while a refresh is not indexing transcripts.
    private(set) var indexingProgress: (done: Int, total: Int)?
    private(set) var unpricedModels: [String] = []
    private(set) var lastError: String?
    private(set) var isSpikeActive = false
    /// Distinct Claude Code sessions in the index. Subagents count as their parent.
    private(set) var sessionCount = 0
    /// Transcript `.jsonl` path keyed by conversation id (`sessionId` or `sessionId:agent-…`).
    private(set) var transcriptPaths: [String: String] = [:]
    /// Estimated list-price cents since this billing cycle started. Nil before the
    /// first successful index.
    private(set) var cycleSpendCents: Double?
    /// Estimated Claude Code usage for the community snapshot. Combined with Cursor
    /// under the same participant before upload.
    private(set) var communityAnalyticsEvents: [CommunityAnalyticsEvent] = []
    private(set) var communityDailySkills: [String: [CommunitySkillSpend]] = [:]
    /// Last successful 5-hour and weekly windows. Kept when a later fetch fails.
    private(set) var limits: ClaudeLimits?
    /// Set when the opt-in limits call cannot be made or fails. Spend keeps working.
    private(set) var limitsError: String?

    private let settings: SettingsStore
    private let anomalyMonitor: AnomalyMonitor?
    private let index: ClaudeTranscriptIndex
    private let projectsRoot: URL
    private let planLimits: ClaudePlanLimits
    private let limitsCacheURL: URL
    private var lastLimitsFetchAt: Date?
    private var limitsRetryAt: Date?
    private var limitsBackoff: TimeInterval = 0
    private var lastRenewAt: Date?
    private var pollTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var refreshInFlight = false
    private var installedObserver: (@MainActor (Bool) -> Void)?
    private weak var communityStore: CommunityStore?
    private weak var spendCap: SpendCapController?

    func setSpendCap(_ controller: SpendCapController?) {
        spendCap = controller
    }

    func setCommunityStore(_ store: CommunityStore?) {
        communityStore = store
    }

    func setInstalledObserver(_ observer: @escaping @MainActor (Bool) -> Void) {
        installedObserver = observer
        observer(isInstalled)
    }

    var burnLevel: BurnLevel {
        BurnLevel.level(
            recentDollars: snapshot.recentDollars,
            thresholdDollars: settings.anomalyThresholdDollars,
            hasError: lastError != nil
        )
    }

    init(
        settings: SettingsStore,
        anomalyMonitor: AnomalyMonitor?,
        projectsRoot: URL = ClaudeTranscriptIndex.defaultRoot,
        cacheURL: URL = ClaudeTranscriptIndex.defaultCacheURL,
        planLimits: ClaudePlanLimits = .live
    ) {
        self.settings = settings
        self.anomalyMonitor = anomalyMonitor
        self.projectsRoot = projectsRoot
        self.planLimits = planLimits
        self.index = ClaudeTranscriptIndex(projectsRoot: projectsRoot, cacheURL: cacheURL)
        self.limitsCacheURL = cacheURL.deletingLastPathComponent()
            .appendingPathComponent("claude-limits.json")
        if settings.claudeLimitsEnabled {
            limits = Self.loadLimits(from: limitsCacheURL)
        }
    }

    /// Drops cached windows when the user turns plan limits off.
    func clearPlanLimits() {
        limits = nil
        limitsError = nil
        lastLimitsFetchAt = nil
        limitsRetryAt = nil
        limitsBackoff = 0
        try? FileManager.default.removeItem(at: limitsCacheURL)
    }

    /// Last good windows from a previous launch, so a relaunch during a rate limit
    /// still shows rows. Reset times may be in the past until the next fetch.
    private static func loadLimits(from url: URL) -> ClaudeLimits? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(ClaudeLimits.self, from: data)
    }

    private func saveLimits(_ limits: ClaudeLimits) {
        guard let data = try? JSONEncoder().encode(limits) else { return }
        try? FileManager.default.createDirectory(
            at: limitsCacheURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try? data.write(to: limitsCacheURL, options: .atomic)
    }

    func start() {
        guard pollTask == nil else { return }
        if !hasCompletedFetch {
            isLoading = true
        }
        pollTask = Task { [weak self] in
            await self?.anomalyMonitor?.requestAuthorizationIfNeeded()
            await self?.refreshInstallStatus()
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

    /// Probes `~/.claude/projects` without indexing. Launch and Settings call this so the
    /// "Claude Code · N sessions / Not found" line stays right while a disabled source skips polls.
    func refreshInstallStatus() async {
        let installed = ClaudeTranscriptIndex.isClaudeCodeInstalled(root: projectsRoot)
        setInstalled(installed)
        if installed {
            sessionCount = await index.sessionCount()
        } else {
            sessionCount = 0
        }
    }

    /// The index actor suspends inside `refresh`, and a second call can enter before
    /// the first writes its snapshot. Overlap would let the older parse win, so only
    /// one refresh reads the index at a time. A request that arrives mid-flight bumps
    /// the generation and runs after the in-flight pass.
    func refresh() async {
        refreshGeneration += 1
        guard !refreshInFlight else { return }
        refreshInFlight = true
        defer {
            refreshInFlight = false
            if Task.isCancelled {
                isLoading = false
                indexingProgress = nil
            }
        }

        while !Task.isCancelled {
            let generation = refreshGeneration
            await performRefresh(generation: generation)
            if generation == refreshGeneration { return }
        }
    }

    private func performRefresh(generation: Int) async {
        await refreshPlanLimits()
        guard generation == refreshGeneration else { return }
        guard settings.claudeCodeEnabled else {
            clearSnapshot()
            hasCompletedFetch = true
            isLoading = false
            indexingProgress = nil
            await communityStore?.handleClaudeRefreshIfNeeded()
            return
        }

        let now = Date()
        let window = settings.usageWindow
        let range = window.dateRange(now: now)
        let communityStart = CommunityPayloadBuilder.eventFetchStart(
            displayWindowStart: range.start,
            now: now
        )
        let cycleStart = UsageTimeWindow(
            preset: .thisBilling,
            timeZone: settings.resolvedTimeZone,
            billingDayOfMonth: settings.billingDayOfMonth
        ).dateRange(now: now).start
        let capStart = spendCap?.armedAt
        let fetchStart = min(communityStart, cycleStart, capStart ?? cycleStart)
        let fetchStartMs = fetchStart.timeIntervalSince1970 * 1000

        let installed = ClaudeTranscriptIndex.isClaudeCodeInstalled(root: projectsRoot)
        guard generation == refreshGeneration else { return }
        setInstalled(installed)

        guard installed else {
            clearSnapshot()
            sessionCount = 0
            hasCompletedFetch = true
            isLoading = false
            indexingProgress = nil
            await communityStore?.handleClaudeRefreshIfNeeded()
            return
        }

        isLoading = true
        let files = await index.refresh(
            sinceMs: fetchStartMs,
            progress: progressHandler(generation: generation)
        )
        guard generation == refreshGeneration else { return }

        let fresh = files.filter { $0.mtime.timeIntervalSince1970 * 1000 >= fetchStartMs }
        let recentWindowMinutes = settings.anomalyWindowMinutes

        let indexed = await Task.detached(priority: .userInitiated) {
            let built = ClaudeCodeEvents.build(files: fresh)
            let snapshot = Aggregator.snapshot(
                events: built.events,
                now: now,
                window: window,
                recentWindowMinutes: recentWindowMinutes,
                rates: .unavailable,
                includeLocalComposers: false,
                grokLibrary: built.library,
                cursorLocalCatalogs: false,
                extraMeta: built.meta
            )
            let skills = Aggregator.communityDailySkills(
                events: built.events,
                now: now,
                grokLibrary: built.library,
                cursorLocalCatalogs: false
            )
            return (snapshot, built.unpricedModels, built.events, skills)
        }.value
        guard generation == refreshGeneration else { return }

        let (next, unpriced, events, skills) = indexed
        snapshot = next
        unpricedModels = unpriced
        communityAnalyticsEvents = UsageStore.communityAnalyticsEvents(from: events, now: now)
        communityDailySkills = skills
        cycleSpendCents = Self.cycleSpendCents(events: events, since: cycleStart, until: now)
        sessionCount = Set(files.map(\.sessionId)).count
        transcriptPaths = Self.transcriptPaths(in: files)
        lastError = nil
        hasCompletedFetch = true
        isLoading = false
        indexingProgress = nil
        isSpikeActive = next.recentCostCents >= settings.anomalyThresholdDollars * 100
        await anomalyMonitor?.evaluate(snapshot: next, settings: settings, source: .claudeCode)
        if let spendCap, let capStart = spendCap.armedAt {
            let spent = Self.cycleSpendCents(events: events, since: capStart, until: now)
            await spendCap.evaluate(spentCents: spent, limits: limits, now: now)
        }
        await communityStore?.handleClaudeRefreshIfNeeded()
    }

    /// At most once per refresh, and not again for 60 seconds. A 429 waits
    /// `Retry-After` or a doubling backoff, whichever is longer. A failed call
    /// keeps the previous windows and sets `limitsError`. An expired or rejected
    /// login is renewed once, at most every `ClaudeLimitsClient.renewInterval`.
    private func refreshPlanLimits() async {
        guard settings.claudeLimitsEnabled else {
            clearPlanLimits()
            return
        }
        guard settings.claudeCodeEnabled else { return }

        let now = planLimits.now()
        if let lastLimitsFetchAt, now.timeIntervalSince(lastLimitsFetchAt) < ClaudeLimitsClient.minimumInterval {
            return
        }
        if let limitsRetryAt, now < limitsRetryAt {
            return
        }

        guard var data = planLimits.readKeychain(),
              ClaudeOAuthToken.extract(from: data, now: now) != .signedOut
        else {
            limitsError = ClaudeLimitsClient.noLogin
            return
        }
        var renewed = false
        if ClaudeOAuthToken.extract(from: data, now: now) == .expired {
            guard let fresh = await renewLogin(data, now: now) else {
                limitsError = ClaudeLimitsClient.loginExpired
                return
            }
            data = fresh
            renewed = true
        }
        guard case .valid(var accessToken) = ClaudeOAuthToken.extract(from: data, now: now) else {
            limitsError = ClaudeLimitsClient.unavailable
            return
        }
        lastLimitsFetchAt = now
        do {
            let fetched: ClaudeLimits
            do {
                fetched = try await planLimits.fetch(accessToken)
            } catch ClaudeLimitsClientError.httpStatus(401) where !renewed {
                guard let fresh = await renewLogin(data, now: now),
                      case .valid(let token) = ClaudeOAuthToken.extract(from: fresh, now: now)
                else { throw ClaudeLimitsClientError.httpStatus(401) }
                accessToken = token
                fetched = try await planLimits.fetch(accessToken)
            }
            guard settings.claudeLimitsEnabled else {
                clearPlanLimits()
                return
            }
            limits = fetched
            limitsError = nil
            limitsRetryAt = nil
            limitsBackoff = 0
            saveLimits(fetched)
        } catch {
            guard settings.claudeLimitsEnabled else {
                clearPlanLimits()
                return
            }
            if case ClaudeLimitsClientError.rateLimited(let retryAfter) = error {
                limitsBackoff = min(
                    max(limitsBackoff * 2, ClaudeLimitsClient.minimumBackoff),
                    ClaudeLimitsClient.maximumBackoff
                )
                limitsRetryAt = now.addingTimeInterval(max(retryAfter ?? 0, limitsBackoff))
            }
            if case ClaudeLimitsClientError.httpStatus(401) = error {
                limitsError = ClaudeLimitsClient.loginExpired
            } else {
                limitsError = ClaudeLimitsClient.unavailable
            }
        }
    }

    private func renewLogin(_ data: Data, now: Date) async -> Data? {
        if let lastRenewAt, now.timeIntervalSince(lastRenewAt) < ClaudeLimitsClient.renewInterval {
            return nil
        }
        lastRenewAt = now
        return await planLimits.renew(data)
    }

    private func progressHandler(generation: Int) -> @Sendable (Int, Int) -> Void {
        let store = UncheckedMainActor(self)
        return { done, total in
            Task { @MainActor in
                guard store.value.refreshGeneration == generation, store.value.isLoading else { return }
                store.value.indexingProgress = (done, total)
            }
        }
    }

    private func setInstalled(_ installed: Bool) {
        guard isInstalled != installed else { return }
        isInstalled = installed
        installedObserver?(installed)
    }

    nonisolated static func transcriptPaths(in files: [ClaudeSessionFile]) -> [String: String] {
        var paths: [String: String] = [:]
        for file in files {
            let id = file.agentId.map { "\(file.sessionId):\($0)" } ?? file.sessionId
            paths[id] = file.path
        }
        return paths
    }

    private func clearSnapshot() {
        snapshot = .empty
        unpricedModels = []
        isSpikeActive = false
        lastError = nil
        transcriptPaths = [:]
        communityAnalyticsEvents = []
        communityDailySkills = [:]
        cycleSpendCents = nil
    }

    /// List-price cents for events inside the billing cycle. Unpriced models add nothing.
    static func cycleSpendCents(events: [UsageEvent], since cycleStart: Date, until now: Date) -> Double {
        let startMs = cycleStart.timeIntervalSince1970 * 1000
        let endMs = now.timeIntervalSince1970 * 1000
        return events.reduce(0) { total, event in
            guard event.timestampMs >= startMs, event.timestampMs <= endMs else { return total }
            return total + event.costCents(using: .unavailable)
        }
    }
}

/// Lets the index progress callback hop back to the main actor. The callback is
/// `@Sendable` and runs off the main actor; the store is not `Sendable`.
private struct UncheckedMainActor<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

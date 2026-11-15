import Foundation

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

    private let settings: SettingsStore
    private let anomalyMonitor: AnomalyMonitor?
    private let index: ClaudeTranscriptIndex
    private let projectsRoot: URL
    private var pollTask: Task<Void, Never>?
    private var refreshGeneration = 0
    private var refreshInFlight = false

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
        cacheURL: URL = ClaudeTranscriptIndex.defaultCacheURL
    ) {
        self.settings = settings
        self.anomalyMonitor = anomalyMonitor
        self.projectsRoot = projectsRoot
        self.index = ClaudeTranscriptIndex(projectsRoot: projectsRoot, cacheURL: cacheURL)
    }

    func start() {
        guard pollTask == nil else { return }
        if !hasCompletedFetch {
            isLoading = true
        }
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
        let now = Date()
        let window = settings.usageWindow
        let range = window.dateRange(now: now)
        let startMs = range.start.timeIntervalSince1970 * 1000

        let installed = ClaudeTranscriptIndex.isClaudeCodeInstalled(root: projectsRoot)
        guard generation == refreshGeneration else { return }
        isInstalled = installed

        guard installed, settings.claudeCodeEnabled else {
            clearSnapshot()
            hasCompletedFetch = true
            isLoading = false
            indexingProgress = nil
            return
        }

        isLoading = true
        let files = await index.refresh(
            sinceMs: startMs,
            progress: progressHandler(generation: generation)
        )
        guard generation == refreshGeneration else { return }

        let fresh = files.filter { $0.mtime.timeIntervalSince1970 * 1000 >= startMs }
        let built = ClaudeCodeEvents.build(files: fresh)
        let recentWindowMinutes = settings.anomalyWindowMinutes
        let events = built.events
        let library = built.library
        let meta = built.meta
        let unpriced = built.unpricedModels

        let next = await Task.detached(priority: .userInitiated) {
            Aggregator.snapshot(
                events: events,
                now: now,
                window: window,
                recentWindowMinutes: recentWindowMinutes,
                rates: .unavailable,
                includeLocalComposers: false,
                grokLibrary: library,
                cursorLocalCatalogs: false,
                extraMeta: meta
            )
        }.value
        guard generation == refreshGeneration else { return }

        snapshot = next
        unpricedModels = unpriced
        lastError = nil
        hasCompletedFetch = true
        isLoading = false
        indexingProgress = nil
        isSpikeActive = next.recentCostCents >= settings.anomalyThresholdDollars * 100
        await anomalyMonitor?.evaluate(snapshot: next, settings: settings, source: .claudeCode)
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

    private func clearSnapshot() {
        snapshot = .empty
        unpricedModels = []
        isSpikeActive = false
        lastError = nil
    }
}

/// Lets the index progress callback hop back to the main actor. The callback is
/// `@Sendable` and runs off the main actor; the store is not `Sendable`.
private struct UncheckedMainActor<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}

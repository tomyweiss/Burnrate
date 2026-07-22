import Foundation
import AppKit

@MainActor
@Observable
final class UsageStore {
    private(set) var snapshot: UsageSnapshot = .empty
    private(set) var isLoading = false
    private(set) var hasCompletedFetch = false
    private(set) var lastError: String?
    private(set) var isSpikeActive = false
    private(set) var notificationFeedback: String?

    private let api = CursorAPI()
    private let anomalyMonitor: AnomalyMonitor?
    private let settings: SettingsStore
    private var pollTask: Task<Void, Never>?

    init(settings: SettingsStore, enableAnomalyAlerts: Bool = true) {
        self.settings = settings
        self.anomalyMonitor = enableAnomalyAlerts ? AnomalyMonitor() : nil
        if enableAnomalyAlerts {
            NotificationPresenter.shared.install()
        }
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
            hasError: lastError != nil
        )
    }

    var menuSymbolName: String {
        burnLevel.symbolName
    }

    var menuBarIcon: NSImage {
        burnLevel.menuBarImage()
    }

    var menuAmountText: String? {
        if settings.hideAmountInMenuBar { return nil }
        if !hasCompletedFetch, lastError == nil {
            return "$—.——"
        }
        return MoneyFormat.dollars(snapshot.windowDollars)
    }

    func start() {
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

        do {
            let credentials = try TokenProvider.loadSessionCredentials()
            let now = Date()
            let window = settings.usageWindow
            let range = window.dateRange(now: now)
            let startMs = Int64(range.start.timeIntervalSince1970 * 1000)
            let endMs = Int64(range.end.timeIntervalSince1970 * 1000)

            let events = try await api.fetchUsageEvents(
                credentials: credentials,
                startMs: startMs,
                endMs: endMs
            )

            let next = Aggregator.snapshot(
                events: events,
                now: now,
                window: window,
                recentWindowMinutes: settings.anomalyWindowMinutes
            )
            snapshot = next
            lastError = nil
            hasCompletedFetch = true
            isSpikeActive = next.recentCostCents >= settings.anomalyThresholdDollars * 100
            await anomalyMonitor?.evaluate(snapshot: next, settings: settings)
        } catch {
            lastError = error.localizedDescription
            hasCompletedFetch = true
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
}

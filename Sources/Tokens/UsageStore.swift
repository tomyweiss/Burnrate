import Foundation

@MainActor
@Observable
final class UsageStore {
    private(set) var snapshot: UsageSnapshot = .empty
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var menuTitle = "$—"

    private let api = CursorAPI()
    private let anomalyMonitor: AnomalyMonitor?
    private let settings: SettingsStore
    private var pollTask: Task<Void, Never>?

    init(settings: SettingsStore, enableAnomalyAlerts: Bool = true) {
        self.settings = settings
        self.anomalyMonitor = enableAnomalyAlerts ? AnomalyMonitor() : nil
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
            let midnight = Calendar.current.startOfDay(for: now)
            let startMs = Int64(midnight.timeIntervalSince1970 * 1000)
            let endMs = Int64(now.timeIntervalSince1970 * 1000)

            let events = try await api.fetchUsageEvents(
                credentials: credentials,
                startMs: startMs,
                endMs: endMs
            )

            let next = Aggregator.snapshot(
                events: events,
                now: now,
                recentWindowMinutes: settings.anomalyWindowMinutes
            )
            snapshot = next
            lastError = nil
            menuTitle = formatDollars(next.todayDollars)
            await anomalyMonitor?.evaluate(snapshot: next, settings: settings)
        } catch {
            lastError = error.localizedDescription
            menuTitle = "!"
        }
    }

    private func formatDollars(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }
}

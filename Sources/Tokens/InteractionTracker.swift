import Foundation
import TokensCore

/// Records panel opens and tab changes locally; uploaded via the Community API.
@MainActor
@Observable
final class InteractionTracker {
    private enum Keys {
        static let panelOpens = "communityInteractionPanelOpens"
        static let tabChanges = "communityInteractionTabChanges"
        static let dailyMetrics = "communityInteractionDailyMetrics"
    }

    private let defaults: UserDefaults
    private var dailyCounters: DayKeyedCounters

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.dailyCounters = DayKeyedCounters(defaults: defaults, storageKey: Keys.dailyMetrics)
    }

    func recordPanelOpen() {
        var stats = loadLifetime()
        stats.recordPanelOpen()
        saveLifetime(stats)

        let day = CommunityDayFormat.utcDayString(for: Date())
        dailyCounters.mutate(forDay: day) { $0.panelOpens += 1 }
    }

    func recordTabChange(_ tab: String) {
        var stats = loadLifetime()
        stats.recordTabChange(tab)
        saveLifetime(stats)

        let day = CommunityDayFormat.utcDayString(for: Date())
        dailyCounters.mutate(forDay: day) { $0.tabChanges[tab, default: 0] += 1 }
    }

    func snapshot() -> CommunityInteractionStats {
        loadLifetime()
    }

    func dailyEngagement(forDay day: String) -> CommunityPayloadBuilder.DailyEngagement {
        let values = dailyCounters.values(forDay: day)
        return CommunityPayloadBuilder.DailyEngagement(
            panelOpens: values.panelOpens,
            tabChanges: values.tabChanges,
            refreshAttempts: 0,
            refreshFailures: 0
        )
    }

    func reset() {
        defaults.removeObject(forKey: Keys.panelOpens)
        defaults.removeObject(forKey: Keys.tabChanges)
        dailyCounters.reset()
    }

    private func loadLifetime() -> CommunityInteractionStats {
        let panelOpens = defaults.integer(forKey: Keys.panelOpens)
        let tabChanges = defaults.dictionary(forKey: Keys.tabChanges) as? [String: Int] ?? [:]
        return CommunityInteractionStats(panelOpens: panelOpens, tabChanges: tabChanges)
    }

    private func saveLifetime(_ stats: CommunityInteractionStats) {
        defaults.set(stats.panelOpens, forKey: Keys.panelOpens)
        defaults.set(stats.tabChanges, forKey: Keys.tabChanges)
    }
}

/// Day-keyed usage refresh attempt/failure counters for reliability analytics.
@MainActor
final class RefreshMetricsTracker {
    private enum Keys {
        static let dailyMetrics = "communityRefreshDailyMetrics"
    }

    private var dailyCounters: DayKeyedCounters

    init(defaults: UserDefaults = .standard) {
        self.dailyCounters = DayKeyedCounters(defaults: defaults, storageKey: Keys.dailyMetrics)
    }

    func recordAttempt() {
        let day = CommunityDayFormat.utcDayString(for: Date())
        dailyCounters.mutate(forDay: day) { $0.refreshAttempts += 1 }
    }

    func recordFailure() {
        let day = CommunityDayFormat.utcDayString(for: Date())
        dailyCounters.mutate(forDay: day) { $0.refreshFailures += 1 }
    }

    func metrics(forDay day: String) -> (attempts: Int, failures: Int) {
        let values = dailyCounters.values(forDay: day)
        return (values.refreshAttempts, values.refreshFailures)
    }

    func reset() {
        dailyCounters.reset()
    }
}

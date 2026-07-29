import Foundation
import TokensCore

/// Records panel opens and tab changes locally; uploaded via the opt-in Community API.
@MainActor
@Observable
final class InteractionTracker {
    private enum Keys {
        static let panelOpens = "communityInteractionPanelOpens"
        static let tabChanges = "communityInteractionTabChanges"
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    func recordPanelOpen(ifEnabled enabled: Bool) {
        guard enabled else { return }
        var stats = load()
        stats.recordPanelOpen()
        save(stats)
    }

    func recordTabChange(_ tab: String, ifEnabled enabled: Bool) {
        guard enabled else { return }
        var stats = load()
        stats.recordTabChange(tab)
        save(stats)
    }

    func snapshot() -> CommunityInteractionStats {
        load()
    }

    func reset() {
        defaults.removeObject(forKey: Keys.panelOpens)
        defaults.removeObject(forKey: Keys.tabChanges)
    }

    private func load() -> CommunityInteractionStats {
        let panelOpens = defaults.integer(forKey: Keys.panelOpens)
        let tabChanges = defaults.dictionary(forKey: Keys.tabChanges) as? [String: Int] ?? [:]
        return CommunityInteractionStats(panelOpens: panelOpens, tabChanges: tabChanges)
    }

    private func save(_ stats: CommunityInteractionStats) {
        defaults.set(stats.panelOpens, forKey: Keys.panelOpens)
        defaults.set(stats.tabChanges, forKey: Keys.tabChanges)
    }
}

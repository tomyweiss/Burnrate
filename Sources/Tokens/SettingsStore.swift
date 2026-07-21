import Foundation
import ServiceManagement

@Observable
final class SettingsStore {
    private enum Keys {
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let anomalyThresholdDollars = "anomalyThresholdDollars"
        static let anomalyWindowMinutes = "anomalyWindowMinutes"
        static let anomalyCooldownMinutes = "anomalyCooldownMinutes"
    }

    var refreshIntervalSeconds: Double {
        didSet { defaults.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds) }
    }

    var anomalyThresholdDollars: Double {
        didSet { defaults.set(anomalyThresholdDollars, forKey: Keys.anomalyThresholdDollars) }
    }

    var anomalyWindowMinutes: Int {
        didSet { defaults.set(anomalyWindowMinutes, forKey: Keys.anomalyWindowMinutes) }
    }

    var anomalyCooldownMinutes: Int {
        didSet { defaults.set(anomalyCooldownMinutes, forKey: Keys.anomalyCooldownMinutes) }
    }

    var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let refresh = defaults.object(forKey: Keys.refreshIntervalSeconds) as? Double
        refreshIntervalSeconds = refresh ?? 60

        let threshold = defaults.object(forKey: Keys.anomalyThresholdDollars) as? Double
        anomalyThresholdDollars = threshold ?? 10

        let window = defaults.object(forKey: Keys.anomalyWindowMinutes) as? Int
        anomalyWindowMinutes = window ?? 10

        let cooldown = defaults.object(forKey: Keys.anomalyCooldownMinutes) as? Int
        anomalyCooldownMinutes = cooldown ?? 15

        if #available(macOS 13.0, *) {
            launchAtLogin = SMAppService.mainApp.status == .enabled
        } else {
            launchAtLogin = false
        }
    }

    private func applyLaunchAtLogin() {
        guard #available(macOS 13.0, *) else { return }
        let enabled = SMAppService.mainApp.status == .enabled
        do {
            if launchAtLogin, !enabled {
                try SMAppService.mainApp.register()
            } else if !launchAtLogin, enabled {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            let actual = SMAppService.mainApp.status == .enabled
            if launchAtLogin != actual {
                launchAtLogin = actual
            }
        }
    }
}

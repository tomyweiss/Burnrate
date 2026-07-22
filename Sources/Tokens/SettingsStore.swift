import Foundation
import ServiceManagement

@Observable
final class SettingsStore {
    private enum Keys {
        static let refreshIntervalSeconds = "refreshIntervalSeconds"
        static let anomalyThresholdDollars = "anomalyThresholdDollars"
        static let anomalyWindowMinutes = "anomalyWindowMinutes"
        static let anomalyCooldownMinutes = "anomalyCooldownMinutes"
        static let hideAmountInMenuBar = "hideAmountInMenuBar"
        static let autoCheckForUpdates = "autoCheckForUpdates"
        static let usageTimelinePreset = "usageTimelinePreset"
        static let billingDayOfMonth = "billingDayOfMonth"
        static let usageTimezoneIdentifier = "usageTimezoneIdentifier"
    }

    static let refreshIntervalOptions: [Double] = [15, 30, 60, 120, 300, 600]

    var refreshIntervalSeconds: Double {
        didSet {
            let nearest = Self.nearestInterval(refreshIntervalSeconds)
            if nearest != refreshIntervalSeconds {
                refreshIntervalSeconds = nearest
                return
            }
            defaults.set(refreshIntervalSeconds, forKey: Keys.refreshIntervalSeconds)
        }
    }

    var anomalyThresholdDollars: Double {
        didSet {
            let clamped = min(max(anomalyThresholdDollars, 1), 100)
            if clamped != anomalyThresholdDollars {
                anomalyThresholdDollars = clamped
                return
            }
            defaults.set(anomalyThresholdDollars, forKey: Keys.anomalyThresholdDollars)
        }
    }

    var anomalyWindowMinutes: Int {
        didSet {
            let clamped = min(max(anomalyWindowMinutes, 1), 60)
            if clamped != anomalyWindowMinutes {
                anomalyWindowMinutes = clamped
                return
            }
            defaults.set(anomalyWindowMinutes, forKey: Keys.anomalyWindowMinutes)
        }
    }

    var anomalyCooldownMinutes: Int {
        didSet {
            let clamped = min(max(anomalyCooldownMinutes, 1), 120)
            if clamped != anomalyCooldownMinutes {
                anomalyCooldownMinutes = clamped
                return
            }
            defaults.set(anomalyCooldownMinutes, forKey: Keys.anomalyCooldownMinutes)
        }
    }

    var hideAmountInMenuBar: Bool {
        didSet { defaults.set(hideAmountInMenuBar, forKey: Keys.hideAmountInMenuBar) }
    }

    var autoCheckForUpdates: Bool {
        didSet { defaults.set(autoCheckForUpdates, forKey: Keys.autoCheckForUpdates) }
    }

    var usageTimelinePreset: UsageTimelinePreset {
        didSet {
            defaults.set(usageTimelinePreset.rawValue, forKey: Keys.usageTimelinePreset)
        }
    }

    var billingDayOfMonth: Int {
        didSet {
            let clamped = min(max(billingDayOfMonth, 1), 31)
            if clamped != billingDayOfMonth {
                billingDayOfMonth = clamped
                return
            }
            defaults.set(billingDayOfMonth, forKey: Keys.billingDayOfMonth)
        }
    }

    /// `nil` means use the system timezone.
    var usageTimezoneIdentifier: String? {
        didSet {
            if let usageTimezoneIdentifier,
               TimeZone(identifier: usageTimezoneIdentifier) == nil {
                self.usageTimezoneIdentifier = nil
                return
            }
            if let usageTimezoneIdentifier {
                defaults.set(usageTimezoneIdentifier, forKey: Keys.usageTimezoneIdentifier)
            } else {
                defaults.removeObject(forKey: Keys.usageTimezoneIdentifier)
            }
        }
    }

    var resolvedTimeZone: TimeZone {
        if let usageTimezoneIdentifier,
           let timeZone = TimeZone(identifier: usageTimezoneIdentifier) {
            return timeZone
        }
        return .current
    }

    var usageWindow: UsageTimeWindow {
        UsageTimeWindow(
            preset: usageTimelinePreset,
            timeZone: resolvedTimeZone,
            billingDayOfMonth: billingDayOfMonth
        )
    }

    var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults

        let refresh = defaults.object(forKey: Keys.refreshIntervalSeconds) as? Double
        refreshIntervalSeconds = Self.nearestInterval(refresh ?? 60)

        let threshold = defaults.object(forKey: Keys.anomalyThresholdDollars) as? Double
        anomalyThresholdDollars = threshold ?? 10

        let window = defaults.object(forKey: Keys.anomalyWindowMinutes) as? Int
        anomalyWindowMinutes = window ?? 10

        let cooldown = defaults.object(forKey: Keys.anomalyCooldownMinutes) as? Int
        anomalyCooldownMinutes = cooldown ?? 15

        hideAmountInMenuBar = defaults.bool(forKey: Keys.hideAmountInMenuBar)

        if defaults.object(forKey: Keys.autoCheckForUpdates) == nil {
            autoCheckForUpdates = true
        } else {
            autoCheckForUpdates = defaults.bool(forKey: Keys.autoCheckForUpdates)
        }

        if let presetRaw = defaults.string(forKey: Keys.usageTimelinePreset),
           let preset = UsageTimelinePreset(rawValue: presetRaw) {
            usageTimelinePreset = preset
        } else {
            usageTimelinePreset = .today
        }

        let billingDay = defaults.object(forKey: Keys.billingDayOfMonth) as? Int
        billingDayOfMonth = billingDay ?? 1

        usageTimezoneIdentifier = defaults.string(forKey: Keys.usageTimezoneIdentifier)

        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    static func nearestInterval(_ value: Double) -> Double {
        Self.refreshIntervalOptions.min(by: { abs($0 - value) < abs($1 - value) }) ?? 60
    }

    static func intervalLabel(_ seconds: Double) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        let minutes = Int(seconds / 60)
        return "\(minutes)m"
    }

    static let knownTimeZones: [(id: String, label: String)] = {
        TimeZone.knownTimeZoneIdentifiers
            .sorted()
            .map { id in
                let timeZone = TimeZone(identifier: id)!
                let abbreviation = timeZone.abbreviation() ?? timeZone.identifier
                return (id, "\(id) (\(abbreviation))")
            }
    }()

    private func applyLaunchAtLogin() {
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

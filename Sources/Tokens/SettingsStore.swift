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
        static let showLocationSubtitle = "showLocationSubtitle"
        static let hideArchivedSessions = "hideArchivedSessions"
        static let blurSensitiveContent = "blurSensitiveContent"
        static let shareCommunityUsage = "shareCommunityUsage"
        static let communityParticipantId = "communityParticipantId"
        static let communityNickname = "communityNickname"
        static let communityNicknameSource = "communityNicknameSource"
        static let visibleUsageTabs = "visibleUsageTabs"
    }

    /// Tabs shown in the main usage panel picker. Bench is off by default.
    static let defaultVisibleUsageTabs: [UsageTab] = UsageTab.allCases.filter { $0 != .bench }

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

    var showLocationSubtitle: Bool {
        didSet { defaults.set(showLocationSubtitle, forKey: Keys.showLocationSubtitle) }
    }

    var hideArchivedSessions: Bool {
        didSet { defaults.set(hideArchivedSessions, forKey: Keys.hideArchivedSessions) }
    }

    /// Blur session titles and prompt text (for screen recordings / demos).
    var blurSensitiveContent: Bool {
        didSet { defaults.set(blurSensitiveContent, forKey: Keys.blurSensitiveContent) }
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

    /// Opt-in community usage sharing (required to view Community tab data).
    var shareCommunityUsage: Bool {
        didSet { defaults.set(shareCommunityUsage, forKey: Keys.shareCommunityUsage) }
    }

    /// Anonymous participant UUID; generated on first opt-in.
    var communityParticipantId: String? {
        didSet {
            if let communityParticipantId {
                defaults.set(communityParticipantId, forKey: Keys.communityParticipantId)
            } else {
                defaults.removeObject(forKey: Keys.communityParticipantId)
            }
        }
    }

    /// Optional fun nickname; `nil` displays as Anonymous.
    var communityNickname: String? {
        didSet {
            if let communityNickname {
                defaults.set(communityNickname, forKey: Keys.communityNickname)
            } else {
                defaults.removeObject(forKey: Keys.communityNickname)
            }
        }
    }

    var communityNicknameSource: CommunityNicknameSource {
        didSet {
            defaults.set(communityNicknameSource.rawValue, forKey: Keys.communityNicknameSource)
        }
    }

    private(set) var visibleUsageTabRawValues: [String] {
        didSet {
            let validated = Self.validatedVisibleTabRawValues(visibleUsageTabRawValues)
            if validated != visibleUsageTabRawValues {
                visibleUsageTabRawValues = validated
                return
            }
            defaults.set(validated, forKey: Keys.visibleUsageTabs)
        }
    }

    var visibleUsageTabs: Set<UsageTab> {
        get { Set(visibleUsageTabRawValues.compactMap(UsageTab.init(rawValue:))) }
        set {
            visibleUsageTabRawValues = UsageTab.allCases
                .filter { newValue.contains($0) }
                .map(\.rawValue)
        }
    }

    func orderedVisibleUsageTabs() -> [UsageTab] {
        UsageTab.allCases.filter { visibleUsageTabs.contains($0) }
    }

    func isUsageTabVisible(_ tab: UsageTab) -> Bool {
        visibleUsageTabs.contains(tab)
    }

    func setUsageTabVisible(_ tab: UsageTab, visible: Bool) {
        var tabs = visibleUsageTabs
        if visible {
            tabs.insert(tab)
        } else {
            tabs.remove(tab)
        }
        visibleUsageTabs = tabs
    }

    /// Returns a tab raw value that is currently visible in the usage panel picker.
    func normalizedPanelTabSelection(_ panelTabRaw: String) -> String {
        let visible = orderedVisibleUsageTabs()
        guard let current = UsageTab(rawValue: panelTabRaw), visible.contains(current) else {
            return (visible.first ?? .models).rawValue
        }
        return panelTabRaw
    }

    private static func validatedVisibleTabRawValues(_ rawValues: [String]) -> [String] {
        let tabs = UsageTab.allCases.filter { rawValues.contains($0.rawValue) }
        if tabs.isEmpty {
            return defaultVisibleUsageTabs.map(\.rawValue)
        }
        return tabs.map(\.rawValue)
    }

    /// Ensures a participant id exists; call when enabling sharing.
    func ensureCommunityParticipantId() -> String {
        if let communityParticipantId { return communityParticipantId }
        let id = UUID().uuidString.lowercased()
        communityParticipantId = id
        return id
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
        showLocationSubtitle = defaults.bool(forKey: Keys.showLocationSubtitle)
        hideArchivedSessions = defaults.bool(forKey: Keys.hideArchivedSessions)
        blurSensitiveContent = defaults.bool(forKey: Keys.blurSensitiveContent)

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

        shareCommunityUsage = defaults.bool(forKey: Keys.shareCommunityUsage)
        communityParticipantId = defaults.string(forKey: Keys.communityParticipantId)
        communityNickname = defaults.string(forKey: Keys.communityNickname)
        if let sourceRaw = defaults.string(forKey: Keys.communityNicknameSource),
           let source = CommunityNicknameSource(rawValue: sourceRaw) {
            communityNicknameSource = source
        } else {
            communityNicknameSource = .random
        }

        if let savedTabs = defaults.stringArray(forKey: Keys.visibleUsageTabs) {
            visibleUsageTabRawValues = Self.validatedVisibleTabRawValues(savedTabs)
        } else {
            visibleUsageTabRawValues = Self.defaultVisibleUsageTabs.map(\.rawValue)
        }

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

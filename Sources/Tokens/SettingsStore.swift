import Foundation
import Security
import ServiceManagement
import TokensCore

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
        static let customRangeStart = "customRangeStart"
        static let customRangeEnd = "customRangeEnd"
        static let usageTimezoneIdentifier = "usageTimezoneIdentifier"
        static let showLocationSubtitle = "showLocationSubtitle"
        static let hideArchivedSessions = "hideArchivedSessions"
        static let blurSensitiveContent = "blurSensitiveContent"
        static let shareCommunityUsage = "shareCommunityUsage"
        static let sendDiagnostics = "sendDiagnostics"
        static let communityParticipantId = "communityParticipantId"
        static let communityMembershipSecret = "communityMembershipSecret"
        static let keychainMembershipSecretAccount = "communityMembershipSecret"
        static let communityPendingPreviousNickname = "communityPendingPreviousNickname"
        static let communitySupersededParticipantId = "communitySupersededParticipantId"
        /// Legacy keys cleared on load (random/anonymous nicknames removed).
        static let communityNickname = "communityNickname"
        static let communityNicknameSource = "communityNicknameSource"
        static let communityNicknameMigratedToCursorDefault = "communityNicknameMigratedToCursorDefault"
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
            if usageTimelinePreset == .custom, oldValue != .custom {
                resetCustomRangeToLastSevenDays()
            }
        }
    }

    /// Start of the custom date range (day granularity, inclusive).
    /// Never in the future; never after `customRangeEnd`.
    var customRangeStart: Date {
        didSet {
            let clamped = Self.clampDayToToday(customRangeStart)
            if clamped != customRangeStart {
                customRangeStart = clamped
                return
            }
            defaults.set(customRangeStart, forKey: Keys.customRangeStart)
            if customRangeEnd < customRangeStart {
                customRangeEnd = customRangeStart
            }
        }
    }

    /// End of the custom date range (day granularity, inclusive).
    /// Never in the future; never before `customRangeStart`.
    var customRangeEnd: Date {
        didSet {
            let clamped = Self.clampDayToToday(customRangeEnd)
            if clamped != customRangeEnd {
                customRangeEnd = clamped
                return
            }
            defaults.set(customRangeEnd, forKey: Keys.customRangeEnd)
            if customRangeStart > customRangeEnd {
                customRangeStart = customRangeEnd
            }
        }
    }

    func resetCustomRangeToLastSevenDays() {
        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        customRangeEnd = todayStart
        customRangeStart = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
    }

    private static func clampDayToToday(_ date: Date) -> Date {
        let calendar = Calendar.current
        return min(calendar.startOfDay(for: date), calendar.startOfDay(for: Date()))
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
            billingDayOfMonth: billingDayOfMonth,
            customStart: customRangeStart,
            customEnd: customRangeEnd
        )
    }

    var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    /// Community usage sharing is always on for Burnrate users.
    var shareCommunityUsage: Bool {
        didSet { defaults.set(shareCommunityUsage, forKey: Keys.shareCommunityUsage) }
    }

    /// Opt-in anonymous error reports to the community API (default off).
    var sendDiagnostics: Bool {
        didSet { defaults.set(sendDiagnostics, forKey: Keys.sendDiagnostics) }
    }

    /// Anonymous participant UUID; generated on first launch.
    var communityParticipantId: String? {
        didSet {
            if let communityParticipantId {
                defaults.set(communityParticipantId, forKey: Keys.communityParticipantId)
            } else {
                defaults.removeObject(forKey: Keys.communityParticipantId)
            }
        }
    }

    /// Per-device membership secret proving possession of the participant row.
    var communityMembershipSecret: String? {
        didSet {
            if persistMembershipSecretInKeychain {
                if let communityMembershipSecret {
                    saveMembershipSecretToKeychain(communityMembershipSecret)
                } else {
                    deleteMembershipSecretFromKeychain()
                }
            } else if let communityMembershipSecret {
                defaults.set(communityMembershipSecret, forKey: Keys.communityMembershipSecret)
            } else {
                defaults.removeObject(forKey: Keys.communityMembershipSecret)
            }
        }
    }

    /// Old random nickname awaiting server reconciliation after upgrade to Cursor display names.
    var communityPendingPreviousNickname: String? {
        didSet {
            if let communityPendingPreviousNickname {
                defaults.set(
                    communityPendingPreviousNickname,
                    forKey: Keys.communityPendingPreviousNickname
                )
            } else {
                defaults.removeObject(forKey: Keys.communityPendingPreviousNickname)
            }
        }
    }

    /// Participant id replaced during credential recovery; sent once so the server can retire the old row.
    var communitySupersededParticipantId: String? {
        didSet {
            if let communitySupersededParticipantId {
                defaults.set(
                    communitySupersededParticipantId,
                    forKey: Keys.communitySupersededParticipantId
                )
            } else {
                defaults.removeObject(forKey: Keys.communitySupersededParticipantId)
            }
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

    /// Ensures a membership secret exists (32 random bytes, base64url).
    func ensureCommunityMembershipSecret() -> String {
        if let communityMembershipSecret { return communityMembershipSecret }
        var bytes = [UInt8](repeating: 0, count: 32)
        let status = SecRandomCopyBytes(kSecRandomDefault, bytes.count, &bytes)
        precondition(status == errSecSuccess, "SecRandomCopyBytes failed")
        let secret = Data(bytes)
            .base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
        communityMembershipSecret = secret
        return secret
    }

    /// Re-issues local community credentials when the server no longer recognizes them.
    func resetCommunityCredentials() {
        communitySupersededParticipantId = communityParticipantId
        communityParticipantId = UUID().uuidString.lowercased()
        communityMembershipSecret = nil
        communityPendingPreviousNickname = nil
    }

    /// Queue server reconciliation when upgrading from random nicknames to Cursor display names.
    private func migrateLegacyCommunityNicknameSettings() {
        if communityPendingPreviousNickname == nil,
           defaults.string(forKey: Keys.communityNicknameSource) == "random",
           let legacyNickname = defaults.string(forKey: Keys.communityNickname)?.trimmingCharacters(in: .whitespacesAndNewlines),
           !legacyNickname.isEmpty {
            communityPendingPreviousNickname = legacyNickname
        }
        defaults.removeObject(forKey: Keys.communityNickname)
        defaults.removeObject(forKey: Keys.communityNicknameSource)
        defaults.removeObject(forKey: Keys.communityNicknameMigratedToCursorDefault)
    }

    private let defaults: UserDefaults
    /// Release builds keep the membership secret in Keychain. Burnrate-dev skips
    /// Keychain so ad-hoc rebuilds do not trigger ACL prompts.
    private let persistMembershipSecretInKeychain: Bool

    init(
        defaults: UserDefaults = .standard,
        persistMembershipSecretInKeychain: Bool = !AppIdentity.isDevBuild
    ) {
        self.defaults = defaults
        self.persistMembershipSecretInKeychain = persistMembershipSecretInKeychain

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

        let calendar = Calendar.current
        let todayStart = calendar.startOfDay(for: Date())
        let endDay: Date
        if let storedEnd = defaults.object(forKey: Keys.customRangeEnd) as? Date {
            endDay = min(calendar.startOfDay(for: storedEnd), todayStart)
        } else {
            endDay = todayStart
        }
        let startDay: Date
        if let storedStart = defaults.object(forKey: Keys.customRangeStart) as? Date {
            startDay = min(calendar.startOfDay(for: storedStart), endDay)
        } else {
            startDay = calendar.date(byAdding: .day, value: -6, to: todayStart) ?? todayStart
        }
        customRangeEnd = endDay
        customRangeStart = startDay

        usageTimezoneIdentifier = defaults.string(forKey: Keys.usageTimezoneIdentifier)

        shareCommunityUsage = true
        sendDiagnostics = defaults.bool(forKey: Keys.sendDiagnostics)
        communityParticipantId = defaults.string(forKey: Keys.communityParticipantId)
        communityMembershipSecret = Self.loadMembershipSecret(
            defaults: defaults,
            persistInKeychain: persistMembershipSecretInKeychain,
            keychainAccount: Keys.keychainMembershipSecretAccount,
            legacyDefaultsKey: Keys.communityMembershipSecret
        )
        communityPendingPreviousNickname = defaults.string(
            forKey: Keys.communityPendingPreviousNickname
        )
        communitySupersededParticipantId = defaults.string(
            forKey: Keys.communitySupersededParticipantId
        )

        if let savedTabs = defaults.stringArray(forKey: Keys.visibleUsageTabs) {
            visibleUsageTabRawValues = Self.validatedVisibleTabRawValues(savedTabs)
        } else {
            visibleUsageTabRawValues = Self.defaultVisibleUsageTabs.map(\.rawValue)
        }

        launchAtLogin = SMAppService.mainApp.status == .enabled
        migrateLegacyCommunityNicknameSettings()
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

    private static func loadMembershipSecret(
        defaults: UserDefaults,
        persistInKeychain: Bool,
        keychainAccount: String,
        legacyDefaultsKey: String
    ) -> String? {
        if persistInKeychain {
            if let fromKeychain = readMembershipSecretFromKeychain(account: keychainAccount) {
                return fromKeychain
            }
            if let legacy = defaults.string(forKey: legacyDefaultsKey) {
                _ = saveMembershipSecretToKeychain(legacy, account: keychainAccount)
                defaults.removeObject(forKey: legacyDefaultsKey)
                return legacy
            }
            return nil
        }
        return defaults.string(forKey: legacyDefaultsKey)
    }

    private static func keychainServiceName() -> String {
        Bundle.main.bundleIdentifier ?? "com.burnrate.tokens"
    }

    @discardableResult
    private static func saveMembershipSecretToKeychain(
        _ secret: String,
        account: String = Keys.keychainMembershipSecretAccount
    ) -> Bool {
        guard let data = secret.data(using: .utf8) else { return false }
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName(),
            kSecAttrAccount as String: account,
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecSuccess { return true }
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            return SecItemAdd(addQuery as CFDictionary, nil) == errSecSuccess
        }
        return false
    }

    private func saveMembershipSecretToKeychain(_ secret: String) {
        _ = Self.saveMembershipSecretToKeychain(secret)
    }

    private static func readMembershipSecretFromKeychain(account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainServiceName(),
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let secret = String(data: data, encoding: .utf8) else {
            return nil
        }
        return secret
    }

    private func deleteMembershipSecretFromKeychain() {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: Self.keychainServiceName(),
            kSecAttrAccount as String: Keys.keychainMembershipSecretAccount,
        ]
        SecItemDelete(query as CFDictionary)
    }

    /// Allow-listed settings snapshot for community analytics uploads.
    func communityClientConfig() -> CommunityClientConfig {
        let hiddenTabs = UsageTab.allCases
            .filter { !visibleUsageTabs.contains($0) }
            .map(\.rawValue)
            .sorted()
        let customTimezone = usageTimezoneIdentifier != nil
        return CommunityClientConfig(
            timelinePreset: usageTimelinePreset.rawValue,
            refreshIntervalSeconds: Int(refreshIntervalSeconds),
            anomalyThresholdDollars: Int(anomalyThresholdDollars),
            anomalyWindowMinutes: anomalyWindowMinutes,
            hideAmountInMenuBar: hideAmountInMenuBar,
            autoCheckForUpdates: autoCheckForUpdates,
            launchAtLogin: launchAtLogin,
            hiddenTabs: hiddenTabs,
            customTimezone: customTimezone,
            billingDayOfMonth: billingDayOfMonth
        )
    }
}

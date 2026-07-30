import Foundation

/// Persists the last successful usage fetch so the panel stays usable offline.
enum UsageRefreshCache {
    struct Payload: Codable, Sendable {
        let events: [UsageEvent]
        let presetRaw: String
        let timeZoneIdentifier: String
        let billingDayOfMonth: Int
        let recentWindowMinutes: Int
        let fetchedAt: Date
    }

    private static let fileName = "usage-refresh-cache.json"

    private static var fileURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("Burnrate", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appendingPathComponent(fileName)
    }

    static func save(
        events: [UsageEvent],
        settings: SettingsStore,
        recentWindowMinutes: Int,
        fetchedAt: Date
    ) {
        let payload = Payload(
            events: events,
            presetRaw: settings.usageTimelinePreset.rawValue,
            timeZoneIdentifier: settings.resolvedTimeZone.identifier,
            billingDayOfMonth: settings.billingDayOfMonth,
            recentWindowMinutes: recentWindowMinutes,
            fetchedAt: fetchedAt
        )
        guard let data = try? JSONEncoder().encode(payload) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func load(matching settings: SettingsStore, recentWindowMinutes: Int) -> Payload? {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        guard payload.presetRaw == settings.usageTimelinePreset.rawValue,
              payload.timeZoneIdentifier == settings.resolvedTimeZone.identifier,
              payload.billingDayOfMonth == settings.billingDayOfMonth,
              payload.recentWindowMinutes == recentWindowMinutes else {
            return nil
        }
        return payload
    }
}

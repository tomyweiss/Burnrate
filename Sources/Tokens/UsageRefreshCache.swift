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
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
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
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            try FileManager.default.setAttributes(
                [.posixPermissions: NSNumber(value: 0o600)],
                ofItemAtPath: fileURL.path
            )
        } catch {
            // Best-effort cache; offline mode degrades gracefully.
        }
    }

    static func load(
        matchingPresetRaw presetRaw: String,
        timeZoneIdentifier: String,
        billingDayOfMonth: Int,
        recentWindowMinutes: Int
    ) -> Payload? {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        guard payload.presetRaw == presetRaw,
              payload.timeZoneIdentifier == timeZoneIdentifier,
              payload.billingDayOfMonth == billingDayOfMonth,
              payload.recentWindowMinutes == recentWindowMinutes else {
            return nil
        }
        return payload
    }
}

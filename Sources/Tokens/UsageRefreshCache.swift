import Foundation

/// In-memory usage events plus the API window they were fetched for.
struct EventWindowCache: Sendable, Equatable {
    var events: [UsageEvent] = []
    var startMs: Double = 0
    var endMs: Double = 0

    var isEmpty: Bool { events.isEmpty }

    /// True when this cache already contains every event needed for `startMs...endMs`.
    /// End is allowed to lag by `endSlackMs` so a fetch from a few minutes ago
    /// can still satisfy a window that ends at `now`.
    func covers(startMs: Double, endMs: Double, endSlackMs: Double = 5 * 60_000) -> Bool {
        guard !events.isEmpty else { return false }
        return self.startMs <= startMs + 60_000 && self.endMs >= endMs - endSlackMs
    }
}

/// Persists the last successful usage fetch so the panel stays usable offline.
enum UsageRefreshCache {
    struct Payload: Codable, Sendable {
        let events: [UsageEvent]
        let presetRaw: String
        let timeZoneIdentifier: String
        let billingDayOfMonth: Int
        let recentWindowMinutes: Int
        let fetchedAt: Date
        let fetchStartMs: Double?
        let fetchEndMs: Double?

        var resolvedStartMs: Double {
            fetchStartMs ?? events.map(\.timestampMs).min() ?? 0
        }

        var resolvedEndMs: Double {
            fetchEndMs ?? events.map(\.timestampMs).max() ?? 0
        }
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
        fetchedAt: Date,
        fetchStartMs: Double,
        fetchEndMs: Double
    ) {
        let payload = Payload(
            events: events,
            presetRaw: settings.usageTimelinePreset.rawValue,
            timeZoneIdentifier: settings.resolvedTimeZone.identifier,
            billingDayOfMonth: settings.billingDayOfMonth,
            recentWindowMinutes: recentWindowMinutes,
            fetchedAt: fetchedAt,
            fetchStartMs: fetchStartMs,
            fetchEndMs: fetchEndMs
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

    static func load() -> Payload? {
        guard let data = try? Data(contentsOf: fileURL),
              let payload = try? JSONDecoder().decode(Payload.self, from: data) else {
            return nil
        }
        return payload
    }
}

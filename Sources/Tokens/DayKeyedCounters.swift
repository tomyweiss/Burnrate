import Foundation
import TokensCore

/// Day-keyed counters with lazy UTC rollover (retains today + yesterday).
struct DayKeyedCounters {
    struct DayValues: Codable, Equatable {
        var panelOpens: Int = 0
        var tabChanges: [String: Int] = [:]
        var refreshAttempts: Int = 0
        var refreshFailures: Int = 0
    }

    private let defaults: UserDefaults
    private let storageKey: String

    init(defaults: UserDefaults = .standard, storageKey: String) {
        self.defaults = defaults
        self.storageKey = storageKey
    }

    mutating func load(now: Date = Date()) -> [String: DayValues] {
        prune(now: now)
        return readStored()
    }

    mutating func save(_ values: [String: DayValues], now: Date = Date()) {
        let allowed = Set(CommunityDayFormat.reportDays(now: now))
        let pruned = values.filter { allowed.contains($0.key) }
        if let data = try? JSONEncoder().encode(pruned) {
            defaults.set(data, forKey: storageKey)
        }
    }

    mutating func values(forDay day: String, now: Date = Date()) -> DayValues {
        let all = load(now: now)
        return all[day] ?? DayValues()
    }

    mutating func mutate(forDay day: String, now: Date = Date(), _ body: (inout DayValues) -> Void) {
        var all = load(now: now)
        var dayValues = all[day] ?? DayValues()
        body(&dayValues)
        all[day] = dayValues
        save(all, now: now)
    }

    func reset() {
        defaults.removeObject(forKey: storageKey)
    }

    private func readStored() -> [String: DayValues] {
        guard let data = defaults.data(forKey: storageKey),
              let decoded = try? JSONDecoder().decode([String: DayValues].self, from: data) else {
            return [:]
        }
        return decoded
    }

    private mutating func prune(now: Date) {
        let all = readStored()
        let allowed = Set(CommunityDayFormat.reportDays(now: now))
        let pruned = all.filter { allowed.contains($0.key) }
        if pruned.count != all.count {
            save(pruned, now: now)
        }
    }
}

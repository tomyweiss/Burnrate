import Foundation

enum Aggregator {
    static func snapshot(
        events: [UsageEvent],
        now: Date = Date(),
        recentWindowMinutes: Int
    ) -> UsageSnapshot {
        let calendar = Calendar.current
        let midnight = calendar.startOfDay(for: now)
        let midnightMs = midnight.timeIntervalSince1970 * 1000
        let recentStartMs = now.addingTimeInterval(TimeInterval(-recentWindowMinutes * 60))
            .timeIntervalSince1970 * 1000

        var todayCost: Double = 0
        var recentCost: Double = 0
        var byModel: [String: Accumulator] = [:]

        for event in events {
            let ts = event.timestampMs
            guard ts >= midnightMs else { continue }

            let cost = event.costCents
            todayCost += cost
            if ts >= recentStartMs {
                recentCost += cost
            }

            let name = event.model?.isEmpty == false ? event.model! : "unknown"
            var acc = byModel[name] ?? Accumulator()
            acc.costCents += cost
            acc.inputTokens += event.inputTokens
            acc.outputTokens += event.outputTokens
            acc.cacheReadTokens += event.cacheReadTokens
            acc.cacheWriteTokens += event.cacheWriteTokens
            acc.eventCount += 1
            byModel[name] = acc
        }

        let models = byModel
            .map { key, value in
                ModelUsage(
                    model: key,
                    costCents: value.costCents,
                    inputTokens: value.inputTokens,
                    outputTokens: value.outputTokens,
                    cacheReadTokens: value.cacheReadTokens,
                    cacheWriteTokens: value.cacheWriteTokens,
                    eventCount: value.eventCount
                )
            }
            .sorted { $0.costCents > $1.costCents }

        return UsageSnapshot(
            todayCostCents: todayCost,
            recentCostCents: recentCost,
            models: models,
            eventCount: events.filter { $0.timestampMs >= midnightMs }.count,
            fetchedAt: now
        )
    }

    private struct Accumulator {
        var costCents: Double = 0
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheReadTokens: Int = 0
        var cacheWriteTokens: Int = 0
        var eventCount: Int = 0
    }
}

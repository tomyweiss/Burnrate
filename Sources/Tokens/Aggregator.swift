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
        var hourly = Array(repeating: 0.0, count: 24)
        var byModel: [String: ModelAccumulator] = [:]
        var bySession: [String: CrossSessionAccumulator] = [:]

        for event in events {
            let ts = event.timestampMs
            guard ts >= midnightMs else { continue }

            let cost = event.costCents
            todayCost += cost
            if ts >= recentStartMs {
                recentCost += cost
            }

            let eventDate = Date(timeIntervalSince1970: ts / 1000)
            let hour = calendar.component(.hour, from: eventDate)
            if (0..<24).contains(hour) {
                hourly[hour] += cost
            }

            let modelName = event.model?.isEmpty == false ? event.model! : "unknown"
            var modelAcc = byModel[modelName] ?? ModelAccumulator()
            modelAcc.costCents += cost
            modelAcc.inputTokens += event.inputTokens
            modelAcc.outputTokens += event.outputTokens
            modelAcc.cacheReadTokens += event.cacheReadTokens
            modelAcc.cacheWriteTokens += event.cacheWriteTokens
            modelAcc.eventCount += 1

            let sessionKey = event.sessionKey
            var modelSession = modelAcc.sessions[sessionKey] ?? SessionAccumulator()
            modelSession.costCents += cost
            modelSession.inputTokens += event.inputTokens
            modelSession.outputTokens += event.outputTokens
            modelSession.cacheReadTokens += event.cacheReadTokens
            modelSession.cacheWriteTokens += event.cacheWriteTokens
            modelSession.eventCount += 1
            modelSession.lastTimestampMs = max(modelSession.lastTimestampMs, ts)
            modelAcc.sessions[sessionKey] = modelSession
            byModel[modelName] = modelAcc

            var cross = bySession[sessionKey] ?? CrossSessionAccumulator()
            cross.costCents += cost
            cross.inputTokens += event.inputTokens
            cross.outputTokens += event.outputTokens
            cross.cacheReadTokens += event.cacheReadTokens
            cross.cacheWriteTokens += event.cacheWriteTokens
            cross.eventCount += 1
            cross.lastTimestampMs = max(cross.lastTimestampMs, ts)
            cross.modelCosts[modelName, default: 0] += cost
            bySession[sessionKey] = cross
        }

        let models = byModel
            .map { key, value -> ModelUsage in
                let sessions = value.sessions
                    .map { sessionID, session in
                        SessionUsage(
                            conversationId: sessionID,
                            name: nil,
                            workspaceName: nil,
                            costCents: session.costCents,
                            inputTokens: session.inputTokens,
                            outputTokens: session.outputTokens,
                            cacheReadTokens: session.cacheReadTokens,
                            cacheWriteTokens: session.cacheWriteTokens,
                            eventCount: session.eventCount,
                            lastTimestampMs: session.lastTimestampMs,
                            models: [key]
                        )
                    }
                    .sorted(by: sessionSort)
                return ModelUsage(
                    model: key,
                    costCents: value.costCents,
                    inputTokens: value.inputTokens,
                    outputTokens: value.outputTokens,
                    cacheReadTokens: value.cacheReadTokens,
                    cacheWriteTokens: value.cacheWriteTokens,
                    eventCount: value.eventCount,
                    sessions: sessions
                )
            }
            .sorted { $0.costCents > $1.costCents }

        let crossSessions = bySession
            .map { sessionID, session in
                let modelsForSession = session.modelCosts
                    .sorted { $0.value > $1.value }
                    .map(\.key)
                return SessionUsage(
                    conversationId: sessionID,
                    name: nil,
                    workspaceName: nil,
                    costCents: session.costCents,
                    inputTokens: session.inputTokens,
                    outputTokens: session.outputTokens,
                    cacheReadTokens: session.cacheReadTokens,
                    cacheWriteTokens: session.cacheWriteTokens,
                    eventCount: session.eventCount,
                    lastTimestampMs: session.lastTimestampMs,
                    models: modelsForSession
                )
            }
            .sorted(by: sessionSort)

        let catalog = SessionCatalog.lookup(
            conversationIds: Set(crossSessions.map(\.conversationId))
                .filter { $0 != "unknown-session" }
        )

        let enrichedModels = models.map { model in
            model.withSessions(model.sessions.map { $0.enriched(with: catalog[$0.conversationId]) })
        }
        let enrichedCross = crossSessions.map { $0.enriched(with: catalog[$0.conversationId]) }

        return UsageSnapshot(
            todayCostCents: todayCost,
            recentCostCents: recentCost,
            models: enrichedModels,
            sessionsAcrossModels: enrichedCross,
            hourlyCostCents: hourly,
            eventCount: events.filter { $0.timestampMs >= midnightMs }.count,
            fetchedAt: now
        )
    }

    private static func sessionSort(_ a: SessionUsage, _ b: SessionUsage) -> Bool {
        if a.costCents == b.costCents {
            return a.lastTimestampMs > b.lastTimestampMs
        }
        return a.costCents > b.costCents
    }

    private struct SessionAccumulator {
        var costCents: Double = 0
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheReadTokens: Int = 0
        var cacheWriteTokens: Int = 0
        var eventCount: Int = 0
        var lastTimestampMs: Double = 0
    }

    private struct CrossSessionAccumulator {
        var costCents: Double = 0
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheReadTokens: Int = 0
        var cacheWriteTokens: Int = 0
        var eventCount: Int = 0
        var lastTimestampMs: Double = 0
        var modelCosts: [String: Double] = [:]
    }

    private struct ModelAccumulator {
        var costCents: Double = 0
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheReadTokens: Int = 0
        var cacheWriteTokens: Int = 0
        var eventCount: Int = 0
        var sessions: [String: SessionAccumulator] = [:]
    }
}

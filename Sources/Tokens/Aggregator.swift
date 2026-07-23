import Foundation

enum Aggregator {
    static func snapshot(
        events: [UsageEvent],
        now: Date = Date(),
        window: UsageTimeWindow,
        recentWindowMinutes: Int,
        graph: SessionGraph? = nil
    ) -> UsageSnapshot {
        let range = window.dateRange(now: now)
        let startMs = range.start.timeIntervalSince1970 * 1000
        let endMs = range.end.timeIntervalSince1970 * 1000
        let recentStartMs = now.addingTimeInterval(TimeInterval(-recentWindowMinutes * 60))
            .timeIntervalSince1970 * 1000

        let bucketCount = window.bucketCount(now: now)
        var windowCost: Double = 0
        var recentCost: Double = 0
        var buckets = Array(repeating: 0.0, count: bucketCount)
        var byModel: [String: ModelAccumulator] = [:]
        var byLeaf: [String: CrossSessionAccumulator] = [:]
        var filteredEventCount = 0

        for event in events {
            let ts = event.timestampMs
            guard ts >= startMs, ts <= endMs else { continue }

            filteredEventCount += 1
            let cost = event.costCents
            windowCost += cost
            if ts >= recentStartMs {
                recentCost += cost
            }

            let eventDate = Date(timeIntervalSince1970: ts / 1000)
            if let bucketIndex = window.bucketIndex(for: eventDate, now: now),
               bucketIndex < buckets.count {
                buckets[bucketIndex] += cost
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

            var leaf = byLeaf[sessionKey] ?? CrossSessionAccumulator()
            leaf.costCents += cost
            leaf.inputTokens += event.inputTokens
            leaf.outputTokens += event.outputTokens
            leaf.cacheReadTokens += event.cacheReadTokens
            leaf.cacheWriteTokens += event.cacheWriteTokens
            leaf.eventCount += 1
            leaf.lastTimestampMs = max(leaf.lastTimestampMs, ts)
            leaf.modelCosts[modelName, default: 0] += cost
            byLeaf[sessionKey] = leaf
        }

        let leafIds = Set(byLeaf.keys).filter { $0 != "unknown-session" }
        let sessionGraph = graph ?? SessionCatalog.graph(for: leafIds)
        let catalog = sessionGraph.meta
        var rootIdByConversation: [String: String] = [:]
        for id in byLeaf.keys {
            rootIdByConversation[id] = sessionGraph.rootId(for: id)
        }

        let models = byModel
            .map { key, value -> ModelUsage in
                let sessions = value.sessions
                    .map { sessionID, session in
                        SessionUsage(
                            conversationId: sessionID,
                            name: nil,
                            workspaceName: nil,
                            isCloud: sessionID.hasPrefix("bc-"),
                            isArchived: false,
                            repoName: nil,
                            branchName: nil,
                            costCents: session.costCents,
                            inputTokens: session.inputTokens,
                            outputTokens: session.outputTokens,
                            cacheReadTokens: session.cacheReadTokens,
                            cacheWriteTokens: session.cacheWriteTokens,
                            eventCount: session.eventCount,
                            lastTimestampMs: session.lastTimestampMs,
                            models: [key],
                            subagentCount: 0
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

        let conversations = rollUpConversations(
            byLeaf: byLeaf,
            graph: sessionGraph,
            catalog: catalog
        )
        let crossSessions = conversations.map(\.asSessionUsage)

        let enrichedModels = models.map { model in
            model.withSessions(model.sessions.map { $0.enriched(with: catalog[$0.conversationId]) })
        }

        // Ensure every conversation leaf maps to a root for UI navigation.
        for conversation in conversations {
            rootIdByConversation[conversation.conversationId] = conversation.conversationId
            for agent in conversation.subagents {
                rootIdByConversation[agent.conversationId] = conversation.conversationId
            }
        }

        return UsageSnapshot(
            windowCostCents: windowCost,
            recentCostCents: recentCost,
            models: enrichedModels,
            sessionsAcrossModels: crossSessions,
            conversations: conversations,
            rootIdByConversation: rootIdByConversation,
            sparklineCostCents: buckets,
            window: window,
            eventCount: filteredEventCount,
            fetchedAt: now
        )
    }

    /// Pure rollup used by tests; skips SessionCatalog I/O when graph is provided.
    static func rollUpConversations(
        byLeaf: [String: CrossSessionAccumulator],
        graph: SessionGraph,
        catalog: [String: SessionMeta]
    ) -> [ConversationUsage] {
        var leavesByRoot: [String: [String]] = [:]
        for leafId in byLeaf.keys {
            let root = graph.rootId(for: leafId)
            leavesByRoot[root, default: []].append(leafId)
        }

        return leavesByRoot
            .map { rootId, leafIds -> ConversationUsage in
                let rootMeta = catalog[rootId]
                var total = CrossSessionAccumulator()
                var agents: [AgentUsage] = []

                let orderedLeaves = leafIds.sorted()
                for leafId in orderedLeaves {
                    guard let leaf = byLeaf[leafId] else { continue }
                    total.merge(leaf)
                    let leafMeta = catalog[leafId]
                    let isMain = leafId == rootId
                    agents.append(
                        AgentUsage(
                            conversationId: leafId,
                            name: isMain ? nil : leafMeta?.name,
                            subagentTypeName: isMain ? nil : leafMeta?.subagentTypeName,
                            isMain: isMain,
                            costCents: leaf.costCents,
                            inputTokens: leaf.inputTokens,
                            outputTokens: leaf.outputTokens,
                            cacheReadTokens: leaf.cacheReadTokens,
                            cacheWriteTokens: leaf.cacheWriteTokens,
                            eventCount: leaf.eventCount,
                            lastTimestampMs: leaf.lastTimestampMs,
                            models: leaf.modelsSorted
                        )
                    )
                }

                // Always include Main row when root is known, even with $0 in window.
                if !agents.contains(where: \.isMain) {
                    agents.insert(
                        AgentUsage(
                            conversationId: rootId,
                            name: nil,
                            subagentTypeName: nil,
                            isMain: true,
                            costCents: 0,
                            inputTokens: 0,
                            outputTokens: 0,
                            cacheReadTokens: 0,
                            cacheWriteTokens: 0,
                            eventCount: 0,
                            lastTimestampMs: 0,
                            models: []
                        ),
                        at: 0
                    )
                }

                let main = agents.first(where: \.isMain)!
                let subagents = agents
                    .filter { !$0.isMain }
                    .sorted { $0.costCents > $1.costCents }

                return ConversationUsage(
                    conversationId: rootId,
                    name: rootMeta?.name,
                    workspaceName: rootMeta?.workspaceName,
                    isCloud: rootMeta?.isCloud ?? rootId.hasPrefix("bc-"),
                    isArchived: rootMeta?.isArchived ?? false,
                    repoName: rootMeta?.repoName,
                    branchName: rootMeta?.branchName,
                    costCents: total.costCents,
                    inputTokens: total.inputTokens,
                    outputTokens: total.outputTokens,
                    cacheReadTokens: total.cacheReadTokens,
                    cacheWriteTokens: total.cacheWriteTokens,
                    eventCount: total.eventCount,
                    lastTimestampMs: total.lastTimestampMs,
                    models: total.modelsSorted,
                    main: main,
                    subagents: subagents
                )
            }
            .sorted(by: conversationSort)
    }

    private static func sessionSort(_ a: SessionUsage, _ b: SessionUsage) -> Bool {
        if a.costCents == b.costCents {
            return a.lastTimestampMs > b.lastTimestampMs
        }
        return a.costCents > b.costCents
    }

    private static func conversationSort(_ a: ConversationUsage, _ b: ConversationUsage) -> Bool {
        if a.costCents == b.costCents {
            return a.lastTimestampMs > b.lastTimestampMs
        }
        return a.costCents > b.costCents
    }

    struct CrossSessionAccumulator: Sendable {
        var costCents: Double = 0
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheReadTokens: Int = 0
        var cacheWriteTokens: Int = 0
        var eventCount: Int = 0
        var lastTimestampMs: Double = 0
        var modelCosts: [String: Double] = [:]

        var modelsSorted: [String] {
            modelCosts.sorted { $0.value > $1.value }.map(\.key)
        }

        mutating func merge(_ other: CrossSessionAccumulator) {
            costCents += other.costCents
            inputTokens += other.inputTokens
            outputTokens += other.outputTokens
            cacheReadTokens += other.cacheReadTokens
            cacheWriteTokens += other.cacheWriteTokens
            eventCount += other.eventCount
            lastTimestampMs = max(lastTimestampMs, other.lastTimestampMs)
            for (model, cost) in other.modelCosts {
                modelCosts[model, default: 0] += cost
            }
        }
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

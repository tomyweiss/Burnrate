import Foundation

enum Aggregator {
    static func snapshot(
        events: [UsageEvent],
        now: Date = Date(),
        window: UsageTimeWindow,
        recentWindowMinutes: Int
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
        var bySession: [String: CrossSessionAccumulator] = [:]
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
            modelAcc.eventCosts.append(cost)
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

        var knownConversationIds = Set(bySession.keys).filter { $0 != "unknown-session" }
        var parentByChild = PromptCatalog.subagentParents(conversationIds: knownConversationIds)

        // Parents discovered only via children may have no events in-window —
        // still materialize them so roots can host the hierarchy.
        let discoveredParents = Set(parentByChild.values)
        let missingParents = discoveredParents.subtracting(knownConversationIds)
        if !missingParents.isEmpty {
            for parentId in missingParents {
                bySession[parentId] = CrossSessionAccumulator()
            }
            knownConversationIds.formUnion(missingParents)
            // Re-scan so we also pick up siblings listed on the parent composer.
            parentByChild = PromptCatalog.subagentParents(conversationIds: knownConversationIds)
            for parentId in Set(parentByChild.values) where bySession[parentId] == nil {
                bySession[parentId] = CrossSessionAccumulator()
                knownConversationIds.insert(parentId)
            }
        }

        let childrenByParent = childrenByParentMap(parentByChild)

        let catalog = SessionCatalog.lookup(conversationIds: knownConversationIds)

        let hierarchicalSessions = buildHierarchicalSessions(
            bySession: bySession,
            parentByChild: parentByChild,
            childrenByParent: childrenByParent,
            catalog: catalog
        )

        let sessionsById = Dictionary(
            uniqueKeysWithValues: hierarchicalSessions.map { ($0.conversationId, $0) }
        )

        let models = byModel
            .map { key, value -> ModelUsage in
                let sessions = rollupModelSessions(
                    modelSessions: value.sessions,
                    modelName: key,
                    parentByChild: parentByChild,
                    childrenByParent: childrenByParent,
                    sessionsById: sessionsById
                )
                return ModelUsage(
                    model: key,
                    costCents: value.costCents,
                    medianCostCents: Stats.median(value.eventCosts),
                    inputTokens: value.inputTokens,
                    outputTokens: value.outputTokens,
                    cacheReadTokens: value.cacheReadTokens,
                    cacheWriteTokens: value.cacheWriteTokens,
                    eventCount: value.eventCount,
                    sessions: sessions
                )
            }
            .sorted { $0.costCents > $1.costCents }

        let (prompts, subagentPrompts, skills) = promptBreakdown(
            events: events,
            conversationIds: knownConversationIds,
            parentByChild: parentByChild,
            catalog: catalog,
            startMs: startMs,
            endMs: endMs
        )

        return UsageSnapshot(
            windowCostCents: windowCost,
            recentCostCents: recentCost,
            models: models,
            sessionsAcrossModels: hierarchicalSessions.sorted(by: sessionSort),
            prompts: prompts,
            subagentPrompts: subagentPrompts,
            skills: skills,
            sparklineCostCents: buckets,
            window: window,
            eventCount: filteredEventCount,
            fetchedAt: now
        )
    }

    // MARK: - Session hierarchy

    private static func childrenByParentMap(_ parentByChild: [String: String]) -> [String: [String]] {
        var childrenByParent: [String: [String]] = [:]
        for (child, parent) in parentByChild {
            childrenByParent[parent, default: []].append(child)
        }
        for key in childrenByParent.keys {
            childrenByParent[key]?.sort()
        }
        return childrenByParent
    }

    private static func rootConversationId(
        _ id: String,
        parentByChild: [String: String]
    ) -> String {
        var current = id
        var hops = 0
        while let parent = parentByChild[current], hops < 8 {
            current = parent
            hops += 1
        }
        return current
    }

    private static func buildHierarchicalSessions(
        bySession: [String: CrossSessionAccumulator],
        parentByChild: [String: String],
        childrenByParent: [String: [String]],
        catalog: [String: SessionMeta]
    ) -> [SessionUsage] {
        bySession.keys.map { sessionID in
            let own = bySession[sessionID] ?? CrossSessionAccumulator()
            let (totalCost, totalInput, totalOutput, totalCacheRead, totalCacheWrite, totalEvents, lastTs, modelCosts) =
                rolledTotals(
                    rootId: sessionID,
                    bySession: bySession,
                    childrenByParent: childrenByParent
                )
            let modelsForSession = modelCosts
                .sorted { $0.value > $1.value }
                .map(\.key)
            return SessionUsage(
                conversationId: sessionID,
                name: nil,
                workspaceName: nil,
                isCloud: sessionID.hasPrefix("bc-"),
                isArchived: false,
                repoName: nil,
                branchName: nil,
                ownCostCents: own.costCents,
                costCents: totalCost,
                inputTokens: totalInput,
                outputTokens: totalOutput,
                cacheReadTokens: totalCacheRead,
                cacheWriteTokens: totalCacheWrite,
                eventCount: totalEvents,
                lastTimestampMs: lastTs,
                models: modelsForSession,
                parentConversationId: parentByChild[sessionID],
                childConversationIds: childrenByParent[sessionID] ?? []
            ).enriched(with: catalog[sessionID])
        }
    }

    /// Own stats plus all descendants (DFS).
    private static func rolledTotals(
        rootId: String,
        bySession: [String: CrossSessionAccumulator],
        childrenByParent: [String: [String]]
    ) -> (Double, Int, Int, Int, Int, Int, Double, [String: Double]) {
        var cost: Double = 0
        var input = 0
        var output = 0
        var cacheRead = 0
        var cacheWrite = 0
        var events = 0
        var lastTs: Double = 0
        var modelCosts: [String: Double] = [:]

        var stack = [rootId]
        var seen: Set<String> = []
        while let id = stack.popLast() {
            guard seen.insert(id).inserted else { continue }
            if let acc = bySession[id] {
                cost += acc.costCents
                input += acc.inputTokens
                output += acc.outputTokens
                cacheRead += acc.cacheReadTokens
                cacheWrite += acc.cacheWriteTokens
                events += acc.eventCount
                lastTs = max(lastTs, acc.lastTimestampMs)
                for (model, modelCost) in acc.modelCosts {
                    modelCosts[model, default: 0] += modelCost
                }
            }
            stack.append(contentsOf: childrenByParent[id] ?? [])
        }
        return (cost, input, output, cacheRead, cacheWrite, events, lastTs, modelCosts)
    }

    /// Per-model session rows: hide subagents, roll their cost into the root session
    /// for this model so model totals still reconcile with the visible breakdown.
    private static func rollupModelSessions(
        modelSessions: [String: SessionAccumulator],
        modelName: String,
        parentByChild: [String: String],
        childrenByParent: [String: [String]],
        sessionsById: [String: SessionUsage]
    ) -> [SessionUsage] {
        var rootAcc: [String: SessionAccumulator] = [:]
        for (sessionID, acc) in modelSessions {
            let rootID = rootConversationId(sessionID, parentByChild: parentByChild)
            var combined = rootAcc[rootID] ?? SessionAccumulator()
            combined.costCents += acc.costCents
            combined.inputTokens += acc.inputTokens
            combined.outputTokens += acc.outputTokens
            combined.cacheReadTokens += acc.cacheReadTokens
            combined.cacheWriteTokens += acc.cacheWriteTokens
            combined.eventCount += acc.eventCount
            combined.lastTimestampMs = max(combined.lastTimestampMs, acc.lastTimestampMs)
            rootAcc[rootID] = combined
        }

        return rootAcc.map { sessionID, session in
            let meta = sessionsById[sessionID]
            return SessionUsage(
                conversationId: sessionID,
                name: meta?.name,
                workspaceName: meta?.workspaceName,
                isCloud: meta?.isCloud ?? sessionID.hasPrefix("bc-"),
                isArchived: meta?.isArchived ?? false,
                repoName: meta?.repoName,
                branchName: meta?.branchName,
                ownCostCents: session.costCents,
                costCents: session.costCents,
                inputTokens: session.inputTokens,
                outputTokens: session.outputTokens,
                cacheReadTokens: session.cacheReadTokens,
                cacheWriteTokens: session.cacheWriteTokens,
                eventCount: session.eventCount,
                lastTimestampMs: session.lastTimestampMs,
                models: [modelName],
                parentConversationId: nil,
                childConversationIds: meta?.childConversationIds ?? childrenByParent[sessionID] ?? []
            )
        }
        .sorted(by: sessionSort)
    }

    // MARK: - Prompt & skill attribution

    /// Attributes each usage event to the latest user prompt in the same conversation
    /// whose timestamp is at or before the event. Everything spent between one prompt
    /// and the next (the direct response, including work billed to the conversation
    /// by tools/subagents in that turn) counts toward that prompt — and toward any
    /// `/skill` it mentions.
    private static func promptBreakdown(
        events: [UsageEvent],
        conversationIds: Set<String>,
        parentByChild: [String: String],
        catalog: [String: SessionMeta],
        startMs: Double,
        endMs: Double
    ) -> (prompts: [PromptUsage], subagentPrompts: [PromptUsage], skills: [SkillUsage]) {
        func effectiveConversationId(_ id: String) -> String {
            rootConversationId(id, parentByChild: parentByChild)
        }

        // Load prompts for roots (folded attribution) and for subagents (native detail).
        let rootIds = conversationIds
            .subtracting(parentByChild.keys)
            .union(parentByChild.values)
        let promptConversationIds = rootIds.union(parentByChild.keys)
        let promptsByConversation = PromptCatalog.lookup(conversationIds: promptConversationIds)
        guard !promptsByConversation.isEmpty else { return ([], [], []) }

        // Allow small clock skew between local bubble timestamps and server event
        // timestamps when the event lands just before the first known prompt.
        let firstPromptSlackMs: Double = 120_000

        var foldedAccumulators: [String: PromptAccumulator] = [:]
        var nativeSubagentAccumulators: [String: PromptAccumulator] = [:]

        func attribute(
            event: UsageEvent,
            conversationId: String,
            into accumulators: inout [String: PromptAccumulator]
        ) {
            guard let prompts = promptsByConversation[conversationId], !prompts.isEmpty
            else { return }
            let ts = event.timestampMs

            var chosen: PromptRecord?
            for prompt in prompts {
                if prompt.createdAtMs <= ts {
                    chosen = prompt
                } else {
                    break
                }
            }
            if chosen == nil, let first = prompts.first,
               ts >= first.createdAtMs - firstPromptSlackMs {
                chosen = first
            }
            guard let prompt = chosen else { return }

            let key = "\(prompt.conversationId):\(prompt.bubbleId)"
            var acc = accumulators[key] ?? PromptAccumulator(prompt: prompt)
            acc.costCents += event.costCents
            acc.eventCount += 1
            acc.totalTokens += event.inputTokens + event.outputTokens
                + event.cacheReadTokens + event.cacheWriteTokens
            acc.lastEventMs = max(acc.lastEventMs, ts)
            if let model = event.model, !model.isEmpty {
                acc.modelCosts[model, default: 0] += event.costCents
            }
            accumulators[key] = acc
        }

        for event in events {
            let ts = event.timestampMs
            guard ts >= startMs, ts <= endMs else { continue }
            let rawId = event.sessionKey
            let rootId = effectiveConversationId(rawId)

            // Parent / root feed: fold subagent events onto the root timeline.
            attribute(event: event, conversationId: rootId, into: &foldedAccumulators)

            // Subagent detail: keep a native attribution on the child itself.
            if parentByChild[rawId] != nil {
                attribute(event: event, conversationId: rawId, into: &nativeSubagentAccumulators)
            }
        }

        // Include zero-cost prompts typed inside the window so the feed shows them,
        // but don't drag in old prompts from long-running conversations.
        for (conversationId, prompts) in promptsByConversation {
            let isSubagent = parentByChild[conversationId] != nil
            for prompt in prompts where prompt.createdAtMs >= startMs && prompt.createdAtMs <= endMs {
                let key = "\(prompt.conversationId):\(prompt.bubbleId)"
                if isSubagent {
                    if nativeSubagentAccumulators[key] == nil {
                        nativeSubagentAccumulators[key] = PromptAccumulator(prompt: prompt)
                    }
                } else if foldedAccumulators[key] == nil {
                    foldedAccumulators[key] = PromptAccumulator(prompt: prompt)
                }
            }
        }

        func toUsages(_ accumulators: [String: PromptAccumulator]) -> [PromptUsage] {
            accumulators.values
                .map { acc in
                    PromptUsage(
                        conversationId: acc.prompt.conversationId,
                        bubbleId: acc.prompt.bubbleId,
                        text: acc.prompt.text,
                        createdAtMs: acc.prompt.createdAtMs,
                        sessionName: catalog[acc.prompt.conversationId]?.name,
                        costCents: acc.costCents,
                        eventCount: acc.eventCount,
                        totalTokens: acc.totalTokens,
                        lastEventMs: acc.lastEventMs,
                        models: acc.modelCosts.sorted { $0.value > $1.value }.map(\.key),
                        skills: acc.prompt.skills
                    )
                }
                .sorted { $0.createdAtMs > $1.createdAtMs }
        }

        let promptUsages = toUsages(foldedAccumulators)
        let subagentPromptUsages = toUsages(nativeSubagentAccumulators)

        var bySkill: [String: SkillAccumulator] = [:]
        for prompt in promptUsages {
            for skill in prompt.skills {
                var acc = bySkill[skill] ?? SkillAccumulator()
                acc.costCents += prompt.costCents
                acc.promptCosts.append(prompt.costCents)
                acc.invocationCount += 1
                acc.eventCount += prompt.eventCount
                acc.lastUsedMs = max(acc.lastUsedMs, prompt.createdAtMs)
                bySkill[skill] = acc
            }
        }

        let skillUsages = bySkill
            .map { skill, acc in
                SkillUsage(
                    skill: skill,
                    costCents: acc.costCents,
                    medianCostCents: Stats.median(acc.promptCosts),
                    invocationCount: acc.invocationCount,
                    eventCount: acc.eventCount,
                    lastUsedMs: acc.lastUsedMs
                )
            }
            .sorted {
                $0.costCents == $1.costCents
                    ? $0.lastUsedMs > $1.lastUsedMs
                    : $0.costCents > $1.costCents
            }

        return (promptUsages, subagentPromptUsages, skillUsages)
    }

    private struct PromptAccumulator {
        let prompt: PromptRecord
        var costCents: Double = 0
        var eventCount: Int = 0
        var totalTokens: Int = 0
        var lastEventMs: Double = 0
        var modelCosts: [String: Double] = [:]
    }

    private struct SkillAccumulator {
        var costCents: Double = 0
        var promptCosts: [Double] = []
        var invocationCount: Int = 0
        var eventCount: Int = 0
        var lastUsedMs: Double = 0
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
        var eventCosts: [Double] = []
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheReadTokens: Int = 0
        var cacheWriteTokens: Int = 0
        var eventCount: Int = 0
        var sessions: [String: SessionAccumulator] = [:]
    }
}

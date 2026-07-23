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
                    models: modelsForSession
                )
            }
            .sorted(by: sessionSort)

        let knownConversationIds = Set(crossSessions.map(\.conversationId))
            .filter { $0 != "unknown-session" }
        let catalog = SessionCatalog.lookup(conversationIds: knownConversationIds)

        let enrichedModels = models.map { model in
            model.withSessions(model.sessions.map { $0.enriched(with: catalog[$0.conversationId]) })
        }
        let enrichedCross = crossSessions.map { $0.enriched(with: catalog[$0.conversationId]) }

        let (prompts, skills) = promptBreakdown(
            events: events,
            conversationIds: knownConversationIds,
            catalog: catalog,
            startMs: startMs,
            endMs: endMs
        )

        return UsageSnapshot(
            windowCostCents: windowCost,
            recentCostCents: recentCost,
            models: enrichedModels,
            sessionsAcrossModels: enrichedCross,
            prompts: prompts,
            skills: skills,
            sparklineCostCents: buckets,
            window: window,
            eventCount: filteredEventCount,
            fetchedAt: now
        )
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
        catalog: [String: SessionMeta],
        startMs: Double,
        endMs: Double
    ) -> (prompts: [PromptUsage], skills: [SkillUsage]) {
        // Subagent conversations bill under their own conversation id; fold their
        // events into the parent conversation's prompt timeline so a prompt's cost
        // includes the subagents spawned while answering it.
        let parentByChild = PromptCatalog.subagentParents(conversationIds: conversationIds)
        let promptConversationIds = conversationIds
            .subtracting(parentByChild.keys)
            .union(parentByChild.values)

        func effectiveConversationId(_ id: String) -> String {
            var current = id
            var hops = 0
            while let parent = parentByChild[current], hops < 4 {
                current = parent
                hops += 1
            }
            return current
        }

        let promptsByConversation = PromptCatalog.lookup(conversationIds: promptConversationIds)
        guard !promptsByConversation.isEmpty else { return ([], []) }

        // Allow small clock skew between local bubble timestamps and server event
        // timestamps when the event lands just before the first known prompt.
        let firstPromptSlackMs: Double = 120_000

        var accumulators: [String: PromptAccumulator] = [:]

        for event in events {
            let ts = event.timestampMs
            guard ts >= startMs, ts <= endMs else { continue }
            let conversationId = effectiveConversationId(event.sessionKey)
            guard let prompts = promptsByConversation[conversationId], !prompts.isEmpty
            else { continue }

            // Latest prompt with createdAtMs <= ts (prompts are sorted ascending).
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
            guard let prompt = chosen else { continue }

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

        // Include zero-cost prompts typed inside the window so the feed shows them,
        // but don't drag in old prompts from long-running conversations.
        for prompts in promptsByConversation.values {
            for prompt in prompts where prompt.createdAtMs >= startMs && prompt.createdAtMs <= endMs {
                let key = "\(prompt.conversationId):\(prompt.bubbleId)"
                if accumulators[key] == nil {
                    accumulators[key] = PromptAccumulator(prompt: prompt)
                }
            }
        }

        let promptUsages = accumulators.values
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

        var bySkill: [String: SkillAccumulator] = [:]
        for prompt in promptUsages {
            for skill in prompt.skills {
                var acc = bySkill[skill] ?? SkillAccumulator()
                acc.costCents += prompt.costCents
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

        return (promptUsages, skillUsages)
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
        var inputTokens: Int = 0
        var outputTokens: Int = 0
        var cacheReadTokens: Int = 0
        var cacheWriteTokens: Int = 0
        var eventCount: Int = 0
        var sessions: [String: SessionAccumulator] = [:]
    }
}

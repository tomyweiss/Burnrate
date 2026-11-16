import Foundation
import TokensCore

struct ClaudeCodeLibrary: Sendable {
    var events: [UsageEvent]
    var library: GrokBotStore.Library
    var meta: [String: SessionMeta]
    var unpricedModels: [String]
}

enum ClaudeCodeEvents {
    static func build(files: [ClaudeSessionFile]) -> ClaudeCodeLibrary {
        var order: [String] = []
        var latest: [String: (record: ClaudeUsageRecord, conversationId: String)] = [:]
        var meta: [String: SessionMeta] = [:]
        var prompts: [String: [PromptRecord]] = [:]
        var parents: [String: String] = [:]

        for file in files {
            let conversationId = file.agentId.map { "\(file.sessionId):\($0)" } ?? file.sessionId
            for record in file.usage where record.model != "<synthetic>" {
                if latest[record.messageId] == nil {
                    order.append(record.messageId)
                }
                latest[record.messageId] = (record, conversationId)
            }

            let name: String?
            if let agentId = file.agentId {
                parents[conversationId] = file.sessionId
                name = subagentName(agentId: agentId, title: file.title)
            } else {
                name = clipped(file.title) ?? firstPromptName(file.prompts)
            }
            meta[conversationId] = mergedMeta(
                meta[conversationId],
                conversationId: conversationId,
                name: name,
                cwd: file.cwd,
                gitBranch: file.gitBranch
            )

            guard !file.prompts.isEmpty else { continue }
            prompts[conversationId, default: []].append(contentsOf: file.prompts.map { prompt in
                PromptRecord(
                    conversationId: conversationId,
                    bubbleId: prompt.uuid,
                    text: prompt.text,
                    createdAtMs: prompt.timestampMs,
                    skills: prompt.skills,
                    turnIndex: nil
                )
            })
        }

        for id in prompts.keys {
            prompts[id]?.sort {
                if $0.createdAtMs != $1.createdAtMs { return $0.createdAtMs < $1.createdAtMs }
                return $0.bubbleId < $1.bubbleId
            }
        }

        var unpriced: Set<String> = []
        let events = order.compactMap { id -> UsageEvent? in
            guard let (record, conversationId) = latest[id] else { return nil }
            let cents = ClaudePricing.costCents(for: record)
            if cents == nil {
                unpriced.insert(record.model)
            }
            return UsageEvent(
                timestamp: String(record.timestampMs),
                model: record.model,
                kind: nil,
                chargedCents: cents,
                cursorTokenFee: nil,
                isTokenBasedCall: nil,
                tokenUsage: TokenUsage(
                    inputTokens: record.inputTokens,
                    outputTokens: record.outputTokens,
                    cacheWriteTokens: record.cacheCreationTokens,
                    cacheReadTokens: record.cacheReadTokens,
                    totalCents: nil,
                    discountPercentOff: nil
                ),
                usageBasedCosts: nil,
                conversationId: conversationId,
                requestsCosts: nil
            )
        }

        var names: [String: String] = [:]
        for (id, session) in meta {
            guard let name = session.name, !name.isEmpty else { continue }
            names[id] = name
        }

        return ClaudeCodeLibrary(
            events: events,
            library: GrokBotStore.Library(
                names: names,
                prompts: prompts,
                subagentParents: parents
            ),
            meta: meta,
            unpricedModels: unpriced.sorted()
        )
    }

    private static func mergedMeta(
        _ existing: SessionMeta?,
        conversationId: String,
        name: String?,
        cwd: String?,
        gitBranch: String?
    ) -> SessionMeta {
        SessionMeta(
            conversationId: conversationId,
            name: name ?? existing?.name,
            workspaceName: workspaceName(from: cwd) ?? existing?.workspaceName,
            workspaceFSPath: nonEmpty(cwd) ?? existing?.workspaceFSPath,
            isCloud: false,
            isArchived: false,
            branchName: nonEmpty(gitBranch) ?? existing?.branchName
        )
    }

    private static func subagentName(agentId: String, title: String?) -> String {
        if let title = clipped(title) { return title }
        return "Subagent \(shortAgentId(agentId))"
    }

    private static func shortAgentId(_ agentId: String) -> String {
        let stripped = agentId.hasPrefix("agent-")
            ? String(agentId.dropFirst("agent-".count))
            : agentId
        return String(stripped.prefix(7))
    }

    private static func firstPromptName(_ prompts: [ClaudePromptRecord]) -> String? {
        let ordered = prompts.sorted {
            if $0.timestampMs != $1.timestampMs { return $0.timestampMs < $1.timestampMs }
            return $0.uuid < $1.uuid
        }
        for prompt in ordered {
            if let name = clipped(prompt.text) { return name }
        }
        return nil
    }

    private static func clipped(_ text: String?) -> String? {
        guard let trimmed = nonEmpty(text) else { return nil }
        if trimmed.count <= 80 { return trimmed }
        return String(trimmed.prefix(80))
    }

    private static func workspaceName(from cwd: String?) -> String? {
        guard let cwd = nonEmpty(cwd) else { return nil }
        return nonEmpty((cwd as NSString).lastPathComponent)
    }

    private static func nonEmpty(_ text: String?) -> String? {
        guard let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines), !trimmed.isEmpty else {
            return nil
        }
        return trimmed
    }
}

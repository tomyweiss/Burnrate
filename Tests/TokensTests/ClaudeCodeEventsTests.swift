import Foundation
import Testing
import TokensCore
@testable import Tokens

@Test func claudeCodeEventsMapSubagentsAndTokenCosts() throws {
    let now = Date()
    let eventMs = now.timeIntervalSince1970 * 1000 - 30_000
    let sessionId = "sess-parent"
    let agentId = "agent-1a2b3c4d5e"
    let childId = "\(sessionId):\(agentId)"
    let parentRecord = claudeUsage(
        id: "msg-parent",
        sessionId: sessionId,
        timestampMs: eventMs,
        input: 1_000_000,
        output: 2_000,
        cacheWrite: 30,
        cacheRead: 40,
        cwd: "/Users/tom/workspace/tokens",
        gitBranch: "feature/claude"
    )
    let childRecord = claudeUsage(
        id: "msg-child",
        sessionId: sessionId,
        model: "claude-haiku-4-5",
        timestampMs: eventMs + 1_000,
        output: 1_000_000
    )
    let built = ClaudeCodeEvents.build(files: [
        claudeSessionFile(
            path: "/tmp/sess-parent.jsonl",
            sessionId: sessionId,
            usage: [parentRecord],
            cwd: "/Users/tom/workspace/tokens",
            gitBranch: "feature/claude"
        ),
        claudeSessionFile(
            path: "/tmp/sess-parent/subagents/agent-1a2b3c4d5e.jsonl",
            sessionId: sessionId,
            agentId: agentId,
            usage: [childRecord]
        ),
    ])

    let parent = try #require(built.events.first { $0.conversationId == sessionId })
    let child = try #require(built.events.first { $0.conversationId == childId })
    #expect(parent.timestampMs == parentRecord.timestampMs)
    #expect(parent.kind == nil)
    #expect(parent.chargedCents == ClaudePricing.costCents(for: parentRecord))
    #expect(parent.inputTokens == 1_000_000)
    #expect(parent.outputTokens == 2_000)
    #expect(parent.cacheWriteTokens == 30)
    #expect(parent.cacheReadTokens == 40)
    #expect(child.model == "claude-haiku-4-5")
    #expect(child.chargedCents == ClaudePricing.costCents(for: childRecord))
    #expect(built.library.subagentParents == [childId: sessionId])
    #expect(built.meta[sessionId]?.workspaceName == "tokens")
    #expect(built.meta[sessionId]?.workspaceFSPath == "/Users/tom/workspace/tokens")
    #expect(built.meta[sessionId]?.branchName == "feature/claude")
    #expect(built.meta[sessionId]?.isCloud == false)
    #expect(built.meta[sessionId]?.isArchived == false)
    #expect(built.meta[childId]?.name == "Subagent 1a2b3c4")
    #expect(built.library.names[childId] == "Subagent 1a2b3c4")
}

@Test func claudeCodeEventsKeepLastUsageLinePerMessage() {
    let ms = Date().timeIntervalSince1970 * 1000
    let built = ClaudeCodeEvents.build(files: [
        claudeSessionFile(
            path: "/tmp/a.jsonl",
            sessionId: "sess",
            usage: [claudeUsage(id: "same", sessionId: "sess", timestampMs: ms, output: 1)]
        ),
        claudeSessionFile(
            path: "/tmp/b.jsonl",
            sessionId: "sess",
            usage: [claudeUsage(id: "same", sessionId: "sess", timestampMs: ms, output: 9)]
        ),
    ])

    #expect(built.events.map(\.outputTokens) == [9])
}

@Test func claudeCodeEventsSkipSyntheticModels() {
    let ms = Date().timeIntervalSince1970 * 1000
    let built = ClaudeCodeEvents.build(files: [
        claudeSessionFile(
            path: "/tmp/s.jsonl",
            sessionId: "sess",
            usage: [
                claudeUsage(id: "syn", sessionId: "sess", model: "<synthetic>", timestampMs: ms, input: 80),
                claudeUsage(id: "real", sessionId: "sess", timestampMs: ms, input: 5),
            ]
        ),
    ])

    #expect(built.events.map(\.model) == ["claude-opus-5-5"])
    #expect(built.unpricedModels.isEmpty)
}

@Test func claudeCodeEventsListUnpricedModelsWithoutACost() throws {
    let ms = Date().timeIntervalSince1970 * 1000
    let mystery = claudeUsage(
        id: "m1",
        sessionId: "sess",
        model: "zeta-unknown",
        timestampMs: ms,
        input: 50
    )
    let again = claudeUsage(
        id: "m2",
        sessionId: "sess",
        model: "alpha-unknown",
        timestampMs: ms,
        output: 7
    )
    let duplicate = claudeUsage(
        id: "m3",
        sessionId: "sess",
        model: "zeta-unknown",
        timestampMs: ms
    )
    let built = ClaudeCodeEvents.build(files: [
        claudeSessionFile(path: "/tmp/s.jsonl", sessionId: "sess", usage: [mystery, again, duplicate]),
    ])

    #expect(built.unpricedModels == ["alpha-unknown", "zeta-unknown"])
    let unpriced = try #require(built.events.first { $0.model == "zeta-unknown" })
    #expect(unpriced.chargedCents == nil)
    #expect(unpriced.inputTokens == 50)
    let priced = built.events.compactMap(\.chargedCents)
    #expect(priced.isEmpty)
}

@Test func claudeCodeEventsPreferTitleOverTheFirstPrompt() {
    let ms = Date().timeIntervalSince1970 * 1000
    let built = ClaudeCodeEvents.build(files: [
        claudeSessionFile(
            path: "/tmp/titled.jsonl",
            sessionId: "titled",
            prompts: [claudePrompt(uuid: "p1", sessionId: "titled", timestampMs: ms, text: "prompt text")],
            title: "  Custom title  "
        ),
        claudeSessionFile(
            path: "/tmp/blank.jsonl",
            sessionId: "blank-title",
            prompts: [claudePrompt(uuid: "p2", sessionId: "blank-title", timestampMs: ms, text: "from prompt")],
            title: "   "
        ),
        claudeSessionFile(
            path: "/tmp/sub.jsonl",
            sessionId: "titled",
            agentId: "agent-scout1234",
            title: "  Scout title  "
        ),
    ])

    #expect(built.meta["titled"]?.name == "Custom title")
    #expect(built.library.names["titled"] == "Custom title")
    #expect(built.meta["blank-title"]?.name == "from prompt")
    #expect(built.meta["titled:agent-scout1234"]?.name == "Scout title")
}

@Test func claudeCodeEventsNameASessionFromTheFirstPrompt() {
    let ms = Date().timeIntervalSince1970 * 1000
    let long = String(repeating: "b", count: 81)
    let built = ClaudeCodeEvents.build(files: [
        claudeSessionFile(
            path: "/tmp/prompts.jsonl",
            sessionId: "prompts",
            prompts: [
                claudePrompt(uuid: "later", sessionId: "prompts", timestampMs: ms + 5_000, text: "second prompt"),
                claudePrompt(uuid: "earlier", sessionId: "prompts", timestampMs: ms, text: "  first prompt text  "),
            ]
        ),
        claudeSessionFile(
            path: "/tmp/long.jsonl",
            sessionId: "long",
            prompts: [claudePrompt(uuid: "long", sessionId: "long", timestampMs: ms, text: " \(long)")]
        ),
        claudeSessionFile(
            path: "/tmp/sub.jsonl",
            sessionId: "prompts",
            agentId: "agent-abcdefXYZ",
            prompts: [claudePrompt(uuid: "sub", sessionId: "prompts", timestampMs: ms, text: "sub prompt")]
        ),
    ])

    #expect(built.meta["prompts"]?.name == "first prompt text")
    #expect(built.meta["long"]?.name == String(repeating: "b", count: 80))
    #expect(built.meta["prompts:agent-abcdefXYZ"]?.name == "Subagent abcdefX")
    #expect(built.library.names["prompts:agent-abcdefXYZ"] == "Subagent abcdefX")
}

@Test func claudeCodeEventsKeyPromptsByConversation() {
    let ms = Date().timeIntervalSince1970 * 1000
    let sessionId = "sess-prompts"
    let agentId = "agent-worker1"
    let childId = "\(sessionId):\(agentId)"
    let built = ClaudeCodeEvents.build(files: [
        claudeSessionFile(
            path: "/tmp/sess.jsonl",
            sessionId: sessionId,
            prompts: [
                claudePrompt(
                    uuid: "parent-prompt",
                    sessionId: sessionId,
                    timestampMs: ms,
                    text: "please /Review this",
                    skills: ["review"]
                ),
            ]
        ),
        claudeSessionFile(
            path: "/tmp/sub.jsonl",
            sessionId: sessionId,
            agentId: agentId,
            prompts: [
                claudePrompt(
                    uuid: "child-prompt",
                    sessionId: sessionId,
                    timestampMs: ms + 10,
                    text: "sub prompt",
                    skills: []
                ),
            ]
        ),
    ])

    let parent = built.library.prompts[sessionId]
    #expect(parent?.map(\.bubbleId) == ["parent-prompt"])
    #expect(parent?.first?.conversationId == sessionId)
    #expect(parent?.first?.text == "please /Review this")
    #expect(parent?.first?.createdAtMs == ms)
    #expect(parent?.first?.skills == ["review"])
    #expect(parent?.first?.turnIndex == nil)
    #expect(built.library.prompts[childId]?.map(\.bubbleId) == ["child-prompt"])
    #expect(built.library.prompts[childId]?.first?.conversationId == childId)
    #expect(built.library.prompts[sessionId]?.contains { $0.bubbleId == "child-prompt" } == false)
}

@Test func claudeCodeSnapshotUsesInjectedNamesWithoutCursorCatalogs() throws {
    let now = Date()
    let eventMs = now.timeIntervalSince1970 * 1000 - 60_000
    let sessionId = "claude-sess-task3-root"
    let agentId = "agent-1a2b3c4d5e"
    let childId = "\(sessionId):\(agentId)"
    let parentRecord = claudeUsage(
        id: "priced-parent",
        sessionId: sessionId,
        timestampMs: eventMs,
        input: 1_000_000,
        cwd: "/Users/tom/workspace/tokens",
        gitBranch: "feature/claude"
    )
    let childRecord = claudeUsage(
        id: "priced-child",
        sessionId: sessionId,
        model: "claude-haiku-4-5",
        timestampMs: eventMs + 2_000,
        output: 1_000_000
    )
    let unpriced = claudeUsage(
        id: "unpriced",
        sessionId: sessionId,
        model: "zeta-unknown",
        timestampMs: eventMs + 3_000,
        input: 50
    )
    let built = ClaudeCodeEvents.build(files: [
        claudeSessionFile(
            path: "/tmp/root.jsonl",
            sessionId: sessionId,
            usage: [parentRecord, unpriced],
            prompts: [
                claudePrompt(
                    uuid: "ask",
                    sessionId: sessionId,
                    timestampMs: eventMs - 1_000,
                    text: "fix the parser"
                ),
            ],
            title: "Ship the parser",
            cwd: "/Users/tom/workspace/tokens",
            gitBranch: "feature/claude"
        ),
        claudeSessionFile(
            path: "/tmp/sub.jsonl",
            sessionId: sessionId,
            agentId: agentId,
            usage: [childRecord],
            cwd: "/tmp/tokens",
            gitBranch: "feature/claude"
        ),
    ])

    let snapshot = Aggregator.snapshot(
        events: built.events,
        now: now,
        window: UsageTimeWindow(preset: .last24Hours, timeZone: .gmt),
        recentWindowMinutes: 60,
        rates: .unavailable,
        grokLibrary: built.library,
        cursorLocalCatalogs: false,
        extraMeta: built.meta
    )

    #expect(snapshot.sessionsAcrossModels.map(\.conversationId).sorted() == [childId, sessionId].sorted())
    let root = try #require(snapshot.rootSessions.first)
    #expect(snapshot.rootSessions.count == 1)
    #expect(root.name == "Ship the parser")
    #expect(root.workspaceName == "tokens")
    #expect(root.branchName == "feature/claude")
    #expect(root.childConversationIds == [childId])
    #expect(root.isCloud == false)
    let child = try #require(snapshot.session(id: childId))
    #expect(child.name == "Subagent 1a2b3c4")
    #expect(child.parentConversationId == sessionId)
    let priced = built.events.compactMap(\.chargedCents).reduce(0, +)
    #expect(priced == (ClaudePricing.costCents(for: parentRecord) ?? 0) + (ClaudePricing.costCents(for: childRecord) ?? 0))
    #expect(priced > 0)
    #expect(abs(snapshot.windowCostCents - priced) < 0.000_001)
    #expect(snapshot.prompts.map(\.text) == ["fix the parser"])
    let mystery = try #require(snapshot.models.first { $0.model == "zeta-unknown" })
    #expect(mystery.costCents == 0)
    #expect(mystery.inputTokens == 50)
}

private func claudeUsage(
    id: String,
    sessionId: String,
    model: String = "claude-opus-5-5",
    timestampMs: Double,
    input: Int = 0,
    output: Int = 0,
    cacheWrite: Int = 0,
    cacheRead: Int = 0,
    cwd: String? = nil,
    gitBranch: String? = nil
) -> ClaudeUsageRecord {
    ClaudeUsageRecord(
        messageId: id,
        timestampMs: timestampMs,
        sessionId: sessionId,
        model: model,
        inputTokens: input,
        outputTokens: output,
        cacheCreationTokens: cacheWrite,
        cacheCreation1hTokens: 0,
        cacheReadTokens: cacheRead,
        isSidechain: false,
        cwd: cwd,
        gitBranch: gitBranch
    )
}

private func claudePrompt(
    uuid: String,
    sessionId: String,
    timestampMs: Double,
    text: String,
    skills: [String] = []
) -> ClaudePromptRecord {
    ClaudePromptRecord(
        uuid: uuid,
        sessionId: sessionId,
        timestampMs: timestampMs,
        text: text,
        skills: skills
    )
}

private func claudeSessionFile(
    path: String,
    sessionId: String,
    agentId: String? = nil,
    usage: [ClaudeUsageRecord] = [],
    prompts: [ClaudePromptRecord] = [],
    title: String? = nil,
    cwd: String? = nil,
    gitBranch: String? = nil
) -> ClaudeSessionFile {
    ClaudeSessionFile(
        path: path,
        sessionId: sessionId,
        agentId: agentId,
        offset: 1,
        mtime: Date(),
        size: 1,
        usage: usage,
        prompts: prompts,
        title: title,
        cwd: cwd,
        gitBranch: gitBranch
    )
}

import Foundation
import Testing
@testable import Tokens
@testable import TokensCore

@Test func grokBotRosterReadsAgentNames() throws {
    let names = GrokBotTranscript.agentNames(fromRosterJSON: Data("""
    {
      "value": {
        "rows": [
          { "id": "agent-personal", "name": "Personal" },
          { "id": "agent-blank", "name": "  " },
          { "id": "agent-general", "name": "General" }
        ]
      }
    }
    """.utf8))

    #expect(names == ["agent-personal": "Personal", "agent-general": "General"])
}

@Test func grokBotTranscriptReadsUserPromptsInOrder() throws {
    let prompts = GrokBotTranscript.prompts(fromTranscriptJSON: Data("""
    {
      "value": {
        "entries": [
          { "kind": "send-message", "id": "out", "role": "user", "content": "skip me", "timestampMs": 1 },
          { "kind": "message", "id": "m2", "role": "user", "content": " second ", "timestampMs": 20 },
          { "kind": "message", "id": "m1", "role": "user", "content": "first", "timestampMs": 10 },
          { "kind": "message", "id": "bot", "role": "assistant", "content": "reply", "timestampMs": 30 },
          { "kind": "message", "id": "empty", "role": "user", "content": "  ", "timestampMs": 40 }
        ]
      }
    }
    """.utf8))

    #expect(prompts.map(\.id) == ["m1", "m2"])
    #expect(prompts.map(\.text) == ["first", "second"])
    #expect(prompts.map(\.timestampMs) == [10, 20])
}

@Test func grokBotTranscriptFindsSubagentParentInsideAStringPayload() {
    let text = """
    {"content":"{\\"subagent\\": {\\"id\\": \\"sand-subagent-dc85941c-ed14-1190-d1f1-c7b45f61edd0\\", \\"parentAgentId\\": \\"f6e32069-526e-4d34-b627-4addb1759dc7\\"}"}
    """
    let parents = GrokBotTranscript.subagentParents(in: text)
    #expect(parents == [
        "sand-subagent-dc85941c-ed14-1190-d1f1-c7b45f61edd0": "f6e32069-526e-4d34-b627-4addb1759dc7"
    ])
}

@Test func grokBotLinksASandTaskToTheAgentBilledWithinTenMinutes() {
    let personal = "f6e32069-526e-4d34-b627-4addb1759dc7"
    let sand = "sand-subagent-dc85941c-ed14-1190-d1f1-c7b45f61edd0"
    let parents = GrokBotTranscript.linkSubagents(
        events: [
            (conversationId: personal, timestampMs: 1_000_000),
            (conversationId: sand, timestampMs: 1_000_000 + 30_000),
            (conversationId: sand, timestampMs: 1_000_000 + 45_000)
        ],
        agentIds: [personal]
    )
    #expect(parents == [sand: personal])
}

@Test func grokBotLeavesASandTaskUnlinkedWhenTheNearestAgentIsFarOrDisputed() {
    let personal = "agent-personal"
    let general = "agent-general"
    let far = "sand-subagent-11111111-1111-1111-1111-111111111111"
    let split = "sand-subagent-22222222-2222-2222-2222-222222222222"
    let parents = GrokBotTranscript.linkSubagents(
        events: [
            (conversationId: personal, timestampMs: 0),
            (conversationId: far, timestampMs: 30 * 60 * 1000),
            (conversationId: general, timestampMs: 100_000),
            (conversationId: split, timestampMs: 100_000),
            (conversationId: personal, timestampMs: 200_000),
            (conversationId: split, timestampMs: 200_000)
        ],
        agentIds: [personal, general]
    )
    #expect(parents[far] == nil)
    #expect(parents[split] == nil)
}

@Test func grokBotStoreReadsRosterAndTranscriptBlobs() throws {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("grok-bot-store-\(UUID().uuidString)", isDirectory: true)
    try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: directory) }

    let rosterKey = "sand.client.slice.account.user.roster.last-roster"
    let transcriptKey = "sand.client.slice.account.user.transcript.replicas.agent-personal"
    try Data("""
    {"value":{"rows":[{"id":"agent-personal","name":"Personal"}]}}
    """.utf8).write(to: directory.appendingPathComponent(GrokBotStore.blobName(for: rosterKey)))
    try Data("""
    {"value":{"entries":[
      {"kind":"message","id":"m1","role":"user","content":"fix the drilldown","timestampMs":50},
      {"kind":"message","id":"tool","role":"assistant","content":"{\\"id\\":\\"sand-subagent-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee\\",\\"parentAgentId\\":\\"agent-personal\\"}","timestampMs":60}
    ]}}
    """.utf8).write(to: directory.appendingPathComponent(GrokBotStore.blobName(for: transcriptKey)))

    #expect(
        GrokBotStore.blobName(for: rosterKey)
            == "onqw4zbomnwgszlooqxhg3djmnss4yldmnxxk3tufz2xgzlsfzzg643umvzc43dbon2c24tpon2gk4q.blob"
    )

    let library = GrokBotStore.load(directory: directory)
    #expect(library.names == ["agent-personal": "Personal"])
    #expect(library.prompts["agent-personal"]?.map(\.text) == ["fix the drilldown"])
    #expect(library.subagentParents == [
        "sand-subagent-aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee": "agent-personal"
    ])
}

@Test func sandSubagentWithoutANameDisplaysAsGrokBotTask() {
    let session = SessionUsage(
        conversationId: "sand-subagent-dc85941c-ed14-1190-d1f1-c7b45f61edd0",
        name: nil,
        workspaceName: nil,
        isCloud: false,
        isArchived: false,
        repoName: nil,
        branchName: nil,
        ownCostCents: 45,
        costCents: 45,
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        eventCount: 1,
        lastTimestampMs: 1,
        models: ["grok-bot-default"],
        parentConversationId: nil,
        childConversationIds: []
    )
    #expect(session.displayName == "Grok Bot task")
}

@Test func grokBotDrilldownOpensTheParentAgentAndItsPrompts() throws {
    let now = Date()
    let parentMs = now.timeIntervalSince1970 * 1000 - 60_000
    let personal = "f6e32069-526e-4d34-b627-4addb1759dc7"
    let sand = "sand-subagent-dc85941c-ed14-1190-d1f1-c7b45f61edd0"
    let prompt = PromptRecord(
        conversationId: personal,
        bubbleId: "m1",
        text: "fix the drilldown",
        createdAtMs: parentMs - 1_000,
        skills: [],
        turnIndex: nil
    )
    let library = GrokBotStore.Library(
        names: [personal: "Personal"],
        prompts: [personal: [prompt]],
        subagentParents: [:]
    )
    let snapshot = Aggregator.snapshot(
        events: [
            UsageEvent(
                timestamp: String(parentMs),
                model: "grok-bot-default",
                kind: nil,
                chargedCents: 20,
                cursorTokenFee: nil,
                isTokenBasedCall: nil,
                tokenUsage: nil,
                usageBasedCosts: nil,
                conversationId: personal,
                requestsCosts: nil
            ),
            UsageEvent(
                timestamp: String(parentMs + 5_000),
                model: "grok-bot-default",
                kind: nil,
                chargedCents: 33,
                cursorTokenFee: nil,
                isTokenBasedCall: nil,
                tokenUsage: nil,
                usageBasedCosts: nil,
                conversationId: sand,
                requestsCosts: nil
            )
        ],
        now: now,
        window: UsageTimeWindow(preset: .last24Hours, timeZone: .gmt),
        recentWindowMinutes: 60,
        grokLibrary: library
    )

    let roots = snapshot.rootSessions
    #expect(roots.map(\.conversationId) == [personal])
    #expect(roots.first?.displayName == "Personal")
    #expect(roots.first?.childConversationIds == [sand])
    let prompts = snapshot.prompts(for: roots[0])
    #expect(prompts.map(\.text) == ["fix the drilldown"])
    #expect(prompts.first?.costCents == 53)

    let modelSessions = snapshot.models.first { $0.model == "grok-bot-default" }?.sessions ?? []
    #expect(modelSessions.map(\.conversationId) == [personal])
    #expect(modelSessions.first?.displayName == "Personal")
}

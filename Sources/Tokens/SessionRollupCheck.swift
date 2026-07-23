import Foundation

/// ponytail: one runnable rollup check (no XCTest target on executable package).
enum SessionRollupCheck {
    static func run() {
        let parent = "parent-1"
        let childA = "child-a"
        let childB = "child-b"
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let ts = String(Int64(now.timeIntervalSince1970 * 1000))

        let events = [
            event(id: parent, model: "main-model", cents: 100, input: 10, output: 20, ts: ts),
            event(id: childA, model: "explore-model", cents: 250, input: 100, output: 50, ts: ts),
            event(id: childB, model: "shell-model", cents: 50, input: 5, output: 5, ts: ts)
        ]

        let graph = SessionGraph(
            meta: [
                parent: SessionMeta(conversationId: parent, name: "Helm render"),
                childA: SessionMeta(
                    conversationId: childA,
                    name: "Explore codebase",
                    subagentTypeName: "explore",
                    isSubagent: true
                ),
                childB: SessionMeta(
                    conversationId: childB,
                    name: "Run shell",
                    subagentTypeName: "shell",
                    isSubagent: true
                )
            ],
            rootIdByChild: [childA: parent, childB: parent],
            childrenByRoot: [parent: [childA, childB]]
        )

        let snapshot = Aggregator.snapshot(
            events: events,
            now: now,
            window: UsageTimeWindow(preset: .today, timeZone: TimeZone(secondsFromGMT: 0)!),
            recentWindowMinutes: 60,
            graph: graph
        )

        assert(snapshot.sessionsAcrossModels.count == 1, "expected one rolled session")
        let session = snapshot.sessionsAcrossModels[0]
        assert(session.conversationId == parent)
        assert(session.costCents == 400, "expected rolled cost 400, got \(session.costCents)")
        assert(session.subagentCount == 2)
        assert(session.displayName == "Helm render")

        guard let conversation = snapshot.conversation(id: parent) else {
            assertionFailure("missing conversation detail")
            return
        }
        assert(conversation.main.costCents == 100)
        assert(conversation.main.isMain)
        assert(conversation.subagents.count == 2)
        assert(conversation.subagents[0].conversationId == childA)
        assert(conversation.subagents[0].costCents == 250)
        assert(conversation.subagents[0].subagentTypeName == "explore")
        assert(conversation.subagents[1].conversationId == childB)
        assert(conversation.subagents[1].costCents == 50)
        assert(conversation.main.inputTokens == 10)
        assert(conversation.subagents[0].inputTokens == 100)
        assert(snapshot.rootId(for: childA) == parent)

        fputs("OK session rollup\n", stdout)
    }

    private static func event(
        id: String,
        model: String,
        cents: Double,
        input: Int,
        output: Int,
        ts: String
    ) -> UsageEvent {
        UsageEvent(
            timestamp: ts,
            model: model,
            kind: nil,
            chargedCents: cents,
            cursorTokenFee: nil,
            isTokenBasedCall: true,
            tokenUsage: TokenUsage(
                inputTokens: input,
                outputTokens: output,
                cacheWriteTokens: 0,
                cacheReadTokens: 0,
                totalCents: cents,
                discountPercentOff: nil
            ),
            usageBasedCosts: nil,
            conversationId: id
        )
    }
}

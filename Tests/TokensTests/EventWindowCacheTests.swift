import Foundation
import Testing
@testable import Tokens

@Test func eventWindowCacheRejectsEmpty() {
    let cache = EventWindowCache()
    #expect(!cache.covers(startMs: 0, endMs: 1_000))
}

@Test func eventWindowCacheCoversNestedWindow() {
    let cache = EventWindowCache(
        events: [UsageEvent.fixture(timestamp: "1000")],
        startMs: 0,
        endMs: 10_000
    )
    #expect(cache.covers(startMs: 1_000, endMs: 9_000))
    #expect(!cache.covers(startMs: -5_000, endMs: 9_000))
}

@Test func eventWindowCacheAllowsEndSlack() {
    let cache = EventWindowCache(
        events: [UsageEvent.fixture(timestamp: "1000")],
        startMs: 0,
        endMs: 10_000
    )
    #expect(cache.covers(startMs: 0, endMs: 10_000 + 60_000))
    #expect(!cache.covers(startMs: 0, endMs: 10_000 + 10 * 60_000))
}

@Test func aggregatorSkipsPromptLookupWhenAsked() {
    let window = UsageTimeWindow(preset: .today, timeZone: .gmt)
    let snapshot = Aggregator.snapshot(
        events: [],
        window: window,
        recentWindowMinutes: 10,
        includePrompts: false
    )
    #expect(snapshot.prompts.isEmpty)
    #expect(snapshot.skills.isEmpty)
    #expect(snapshot.eventCount == 0)
}

private extension UsageEvent {
    static func fixture(timestamp: String) -> UsageEvent {
        UsageEvent(
            timestamp: timestamp,
            model: "test",
            kind: nil,
            chargedCents: 1,
            cursorTokenFee: nil,
            isTokenBasedCall: nil,
            tokenUsage: nil,
            usageBasedCosts: nil,
            conversationId: "c1",
            requestsCosts: nil
        )
    }
}

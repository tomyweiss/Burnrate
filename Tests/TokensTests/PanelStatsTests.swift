import Foundation
import Testing
@testable import Tokens

@Test func panelStatsShowsTheSixDashboardFigures() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let snapshot = panelSnapshot(
        windowCostCents: 9_840,
        models: [
            panelModel("gpt-5.4", cents: 6_100.8, input: 0, cacheRead: 50),
            panelModel("composer-2.5", cents: 3_739.2, input: 9, cacheRead: 41)
        ],
        sessions: [
            panelSession("root-a"),
            panelSession("root-b"),
            panelSession("child", parent: "root-a")
        ],
        eventCount: 3_291,
        window: UsageTimeWindow(preset: .last24Hours, timeZone: TimeZone(secondsFromGMT: 0)!),
        fetchedAt: now
    )

    let stats = PanelStats.make(snapshot: snapshot, style: .billed, now: now)

    #expect(stats.map(\.title) == [
        "Sessions", "Events", "Top model", "Cache read", "Per hour", "Avg / session"
    ])
    #expect(stats.map(\.value) == ["2", "3,291", "gpt-5.4", "91%", "$4.10", "$49.20"])
    #expect(stats.map(\.detail) == [nil, nil, "62%", nil, nil, nil])
}

@Test func panelStatsUsesDashesBeforeDataExists() {
    let stats = PanelStats.make(snapshot: .empty, style: .billed, now: Date(timeIntervalSince1970: 1_700_000_000))

    #expect(stats.map(\.title) == [
        "Sessions", "Events", "Top model", "Cache read", "Per hour", "Avg / session"
    ])
    #expect(stats.map(\.value) == ["0", "0", "—", "—", "—", "—"])
    #expect(stats.map(\.detail) == [nil, nil, nil, nil, nil, nil])
}

@Test func panelStatsPrefixesClaudeMoneyWithATilde() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let snapshot = panelSnapshot(
        windowCostCents: 9_840,
        models: [panelModel("claude-opus-4-6", cents: 9_840, input: 10, cacheRead: 0)],
        sessions: [panelSession("root-a"), panelSession("root-b")],
        eventCount: 4,
        window: UsageTimeWindow(preset: .last24Hours, timeZone: TimeZone(secondsFromGMT: 0)!),
        fetchedAt: now
    )

    let stats = PanelStats.make(snapshot: snapshot, style: .estimated, now: now)
    let perHour = stats.first { $0.title == "Per hour" }
    let average = stats.first { $0.title == "Avg / session" }

    #expect(perHour?.value == "~$4.10")
    #expect(average?.value == "~$49.20")
    #expect(perHour?.accessibilityLabel == "Per hour, estimated $4.10")
    #expect(average?.accessibilityLabel == "Avg / session, estimated $49.20")
}

@Test func panelStatsPerHourUsesAtLeastOneHour() {
    let timeZone = TimeZone(secondsFromGMT: 0)!
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = timeZone
    let start = calendar.date(from: DateComponents(year: 2026, month: 11, day: 15))!
    let window = UsageTimeWindow(preset: .today, timeZone: timeZone)

    func perHour(at now: Date) -> String? {
        let snapshot = panelSnapshot(
            windowCostCents: 410,
            models: [],
            sessions: [],
            eventCount: 1,
            window: window,
            fetchedAt: now
        )
        return PanelStats.make(snapshot: snapshot, style: .billed, now: now)
            .first { $0.title == "Per hour" }?
            .value
    }

    #expect(perHour(at: start) == "$4.10")
    #expect(perHour(at: start.addingTimeInterval(30 * 60)) == "$4.10")
    #expect(perHour(at: start.addingTimeInterval(2 * 60 * 60)) == "$2.05")
}

@Test func panelStatsRoundsTheTopModelShare() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let window = UsageTimeWindow(preset: .last24Hours, timeZone: TimeZone(secondsFromGMT: 0)!)

    func top(cents: Double, windowCents: Double, other: Double) -> PanelStat? {
        let snapshot = panelSnapshot(
            windowCostCents: windowCents,
            models: [
                panelModel("claude-sonnet-4-6", cents: cents),
                panelModel("claude-haiku-4-5", cents: other)
            ],
            sessions: [panelSession("root")],
            eventCount: 2,
            window: window,
            fetchedAt: now
        )
        return PanelStats.make(snapshot: snapshot, style: .billed, now: now)
            .first { $0.title == "Top model" }
    }

    let roundedUp = top(cents: 615, windowCents: 1_000, other: 385)
    #expect(roundedUp?.value == "claude-sonnet-4-6")
    #expect(roundedUp?.detail == "62%")

    let roundedDown = top(cents: 100, windowCents: 300, other: 90)
    #expect(roundedDown?.detail == "33%")

    let twoThirds = top(cents: 200, windowCents: 300, other: 50)
    #expect(twoThirds?.detail == "67%")
}

private func panelSnapshot(
    windowCostCents: Double,
    models: [ModelUsage],
    sessions: [SessionUsage],
    eventCount: Int,
    window: UsageTimeWindow,
    fetchedAt: Date
) -> UsageSnapshot {
    UsageSnapshot(
        windowCostCents: windowCostCents,
        recentCostCents: 0,
        models: models,
        sessionsAcrossModels: sessions,
        prompts: [],
        subagentPrompts: [],
        skills: [],
        sparklineCostCents: [],
        window: window,
        eventCount: eventCount,
        fetchedAt: fetchedAt
    )
}

private func panelModel(
    _ name: String,
    cents: Double,
    input: Int = 0,
    cacheRead: Int = 0
) -> ModelUsage {
    ModelUsage(
        model: name,
        costCents: cents,
        medianCostCents: 0,
        inputTokens: input,
        outputTokens: 0,
        cacheReadTokens: cacheRead,
        cacheWriteTokens: 0,
        eventCount: 1,
        sessions: []
    )
}

private func panelSession(_ id: String, parent: String? = nil) -> SessionUsage {
    SessionUsage(
        conversationId: id,
        name: id,
        workspaceName: nil,
        isCloud: false,
        isArchived: false,
        repoName: nil,
        branchName: nil,
        ownCostCents: 0,
        costCents: 0,
        inputTokens: 0,
        outputTokens: 0,
        cacheReadTokens: 0,
        cacheWriteTokens: 0,
        eventCount: 1,
        lastTimestampMs: 0,
        models: [],
        parentConversationId: parent,
        childConversationIds: []
    )
}

import Foundation
import Testing
@testable import Tokens

@Test func cursorAlertDoesNotSuppressClaudeCodeAlert() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    let cooldown: TimeInterval = 15 * 60
    var last: [UsageSource: Date] = [:]

    #expect(AnomalyMonitor.shouldNotify(
        source: .cursor,
        recentCostCents: 2_000,
        thresholdCents: 1_000,
        lastNotificationAt: last,
        now: now,
        cooldown: cooldown
    ))

    last[.cursor] = now

    #expect(!AnomalyMonitor.shouldNotify(
        source: .cursor,
        recentCostCents: 2_000,
        thresholdCents: 1_000,
        lastNotificationAt: last,
        now: now.addingTimeInterval(60),
        cooldown: cooldown
    ))
    #expect(AnomalyMonitor.shouldNotify(
        source: .claudeCode,
        recentCostCents: 2_000,
        thresholdCents: 1_000,
        lastNotificationAt: last,
        now: now.addingTimeInterval(60),
        cooldown: cooldown
    ))
}

@Test func spikeDecisionStaysQuietBelowThresholdAndFiresWhenCooldownElapses() {
    let now = Date(timeIntervalSince1970: 1_800_000_000)
    #expect(!AnomalyMonitor.shouldNotify(
        source: .claudeCode,
        recentCostCents: 999,
        thresholdCents: 1_000,
        lastNotificationAt: [:],
        now: now,
        cooldown: 60
    ))

    let last: [UsageSource: Date] = [.claudeCode: now]
    #expect(!AnomalyMonitor.shouldNotify(
        source: .claudeCode,
        recentCostCents: 1_000,
        thresholdCents: 1_000,
        lastNotificationAt: last,
        now: now.addingTimeInterval(59),
        cooldown: 60
    ))
    #expect(AnomalyMonitor.shouldNotify(
        source: .claudeCode,
        recentCostCents: 1_000,
        thresholdCents: 1_000,
        lastNotificationAt: last,
        now: now.addingTimeInterval(60),
        cooldown: 60
    ))
}

@Test func claudeCodeSpikeCopyIsEstimatedAndCursorCopyStaysBilled() {
    let claude = AnomalyMonitor.notificationContent(
        source: .claudeCode,
        recentDollars: 12.4,
        windowMinutes: 10
    )
    #expect(claude.title == "Burnrate spike · Claude Code")
    #expect(claude.body == "~$12.40 estimated in the last 10 minutes")

    let cursor = AnomalyMonitor.notificationContent(
        source: .cursor,
        recentDollars: 12.4,
        windowMinutes: 10
    )
    #expect(cursor.title == "Burnrate spike")
    #expect(cursor.body == "$12.40 in the last 10 minutes")
}

@Test func usageSourceDisplayNames() {
    #expect(UsageSource.cursor.displayName == "Cursor")
    #expect(UsageSource.claudeCode.displayName == "Claude Code")
    #expect(UsageSource.allCases == [.cursor, .claudeCode])
}

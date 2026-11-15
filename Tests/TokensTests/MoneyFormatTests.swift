import Foundation
import Testing
@testable import Tokens

@Test func estimatedMoneyPrefixesATilde() {
    #expect(MoneyFormat.estimated(31.2) == "~$31.20")
    #expect(MoneyFormat.estimated(0) == "~$0.00")
}

@Test func billedMoneyStyleMatchesTheExistingFormatter() {
    #expect(MoneyFormat.string(12.4, style: .billed) == MoneyFormat.dollars(12.4))
    #expect(MoneyFormat.string(12.4, style: .billed) == "$12.40")
    #expect(MoneyFormat.string(0, style: .billed) == "$0.00")
}

@Test func estimatedMoneyStyleUsesTheTildePrefix() {
    #expect(MoneyFormat.string(31.2, style: .estimated) == "~$31.20")
    #expect(MoneyFormat.string(31.2, style: .estimated) == MoneyFormat.estimated(31.2))
}

@Test func claudeTokenLineAbbreviatesTotalAndRoundsCacheRead() {
    #expect(
        ClaudeTokenLine.string(totalTokens: 48_200_000, cacheReadTokens: 43_862_000)
            == "48.2M tokens · 91% cache read"
    )
    #expect(ClaudeTokenLine.string(totalTokens: 0, cacheReadTokens: 0) == "0 tokens · 0% cache read")
    #expect(ClaudeTokenLine.string(totalTokens: 3, cacheReadTokens: 2) == "3 tokens · 67% cache read")
    #expect(ClaudeTokenLine.string(totalTokens: 1_500, cacheReadTokens: 750) == "1.5K tokens · 50% cache read")
}

@Test func unpricedModelCaptionJoinsModels() {
    #expect(ClaudeTokenLine.unpricedCaption([]) == nil)
    #expect(
        ClaudeTokenLine.unpricedCaption(["claude-mystery"])
            == "No price for claude-mystery. Tokens shown, cost excluded"
    )
    #expect(
        ClaudeTokenLine.unpricedCaption(["claude-a", "claude-b"])
            == "No price for claude-a, claude-b. Tokens shown, cost excluded"
    )
}

@Test func emptyStateCopyDependsOnSource() {
    let window = UsageTimeWindow(preset: .today, timeZone: .current)
    #expect(window.emptyStateMessage(for: .cursor) == "No spend since midnight")
    #expect(window.emptyStateMessage(for: .claudeCode) == "No usage since midnight")

    let day = UsageTimeWindow(preset: .last24Hours, timeZone: .current)
    #expect(day.emptyStateMessage(for: .claudeCode) == "No usage in the last 24 hours")

    let week = UsageTimeWindow(preset: .last7Days, timeZone: .current)
    #expect(week.emptyStateMessage(for: .claudeCode) == "No usage in the last 7 days")

    let billing = UsageTimeWindow(preset: .thisBilling, timeZone: .current)
    #expect(billing.emptyStateMessage(for: .claudeCode) == "No usage this billing cycle")

    let custom = UsageTimeWindow(preset: .custom, timeZone: .current)
    #expect(custom.emptyStateMessage(for: .claudeCode) == "No usage in this date range")
    #expect(custom.emptyStateMessage(for: .cursor) == "No spend in this date range")
}

import Foundation
import Testing
@testable import Tokens

@Test func settingsSummaryNamesTheEnabledSources() {
    #expect(SettingsSummary.sources(cursorEnabled: true, claudeEnabled: true) == "Cursor, Claude Code")
    #expect(SettingsSummary.sources(cursorEnabled: true, claudeEnabled: false) == "Cursor")
    #expect(SettingsSummary.sources(cursorEnabled: false, claudeEnabled: true) == "Claude Code")
    #expect(SettingsSummary.sources(cursorEnabled: false, claudeEnabled: false) == "None")
}

@Test func settingsSummaryNamesUpToTwoMenuBarFigures() {
    #expect(SettingsSummary.menuBar(StatusBarFigures.Input(showsWindowSpend: false)) == "Flame only")
    #expect(SettingsSummary.menuBar(StatusBarFigures.Input(showsWindowSpend: true)) == "Spend")
    #expect(
        SettingsSummary.menuBar(StatusBarFigures.Input(showsWindowSpend: true, showsClaudeSpend: true))
            == "Spend, Claude spend"
    )
    #expect(
        SettingsSummary.menuBar(StatusBarFigures.Input(
            showsWindowSpend: true,
            showsCursorModels: true,
            showsClaudeWeekly: true
        )) == "3 figures"
    )
    #expect(
        SettingsSummary.menuBar(StatusBarFigures.Input(
            showsWindowSpend: false,
            showsOtherModels: true,
            showsGrokBot: true
        )) == "Other models, Grok Bot"
    )
    #expect(
        SettingsSummary.menuBar(StatusBarFigures.Input(showsWindowSpend: false, showsClaudeFiveHour: true))
            == "5h limit"
    )
}

@Test func settingsSummaryDescribesTheSpikeRule() {
    #expect(SettingsSummary.spikeAlert(thresholdDollars: 10, windowMinutes: 10) == "$10.00 in 10 min")
    #expect(SettingsSummary.spikeAlert(thresholdDollars: 25, windowMinutes: 5) == "$25.00 in 5 min")
}

@Test func settingsSummaryCountsVisibleTabs() {
    #expect(SettingsSummary.panel(visibleTabCount: 1) == "1 tab")
    #expect(SettingsSummary.panel(visibleTabCount: 4) == "4 tabs")
}

@Test func settingsSummaryShowsPollAndTimezone() {
    #expect(
        SettingsSummary.data(refreshIntervalSeconds: 60, timezoneIdentifier: nil)
            == "Poll 1m · System timezone"
    )
    #expect(
        SettingsSummary.data(refreshIntervalSeconds: 15, timezoneIdentifier: "Asia/Jerusalem")
            == "Poll 15s · Asia/Jerusalem"
    )
}

@Test func settingsSummaryPrefersAWaitingUpdate() {
    #expect(SettingsSummary.updates(versionLabel: "0.60.14", pendingTitle: nil) == "0.60.14")
    #expect(
        SettingsSummary.updates(versionLabel: "0.60.14", pendingTitle: "Burnrate 0.60.15 is available")
            == "Burnrate 0.60.15 is available"
    )
}

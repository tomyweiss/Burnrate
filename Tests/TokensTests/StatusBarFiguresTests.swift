import Testing
@testable import Tokens

private func figures(
    spend: Bool = false,
    cursor: Bool = false,
    other: Bool = false,
    grok: Bool = false,
    windowDollars: Double = 12.40,
    spendIsPlaceholder: Bool = false,
    cursorPercent: Double? = 72.4,
    otherPercent: Double? = 45,
    grokPercent: Double? = 10.2,
    claudeSpend: Bool = false,
    claudeDollars: Double? = 31.20,
    claudeSpendIsPlaceholder: Bool = false,
    claudeFiveHour: Bool = false,
    claudeFiveHourPercent: Double? = 62,
    claudeWeekly: Bool = false,
    claudeWeeklyPercent: Double? = 34
) -> StatusBarFigures.Input {
    StatusBarFigures.Input(
        showsWindowSpend: spend,
        showsCursorModels: cursor,
        showsOtherModels: other,
        showsGrokBot: grok,
        windowDollars: windowDollars,
        spendIsPlaceholder: spendIsPlaceholder,
        cursorModelsPercent: cursorPercent,
        otherModelsPercent: otherPercent,
        grokBotPercent: grokPercent,
        showsClaudeSpend: claudeSpend,
        claudeDollars: claudeDollars,
        claudeSpendIsPlaceholder: claudeSpendIsPlaceholder,
        showsClaudeFiveHour: claudeFiveHour,
        claudeFiveHourPercent: claudeFiveHourPercent,
        showsClaudeWeekly: claudeWeekly,
        claudeWeeklyPercent: claudeWeeklyPercent
    )
}

@Test func statusBarSpendOnly() {
    let input = figures(spend: true)
    #expect(StatusBarFigures.statusText(input) == "$12.40")
    #expect(StatusBarFigures.accessibilityLabel(input) == "Window spend $12.40")
}

@Test func statusBarCursorPercentOnly() {
    let input = figures(cursor: true)
    #expect(StatusBarFigures.statusText(input) == "72%")
    #expect(StatusBarFigures.accessibilityLabel(input) == "Cursor models 72 percent used")
}

@Test func statusBarOtherPercentOnly() {
    let input = figures(other: true)
    #expect(StatusBarFigures.statusText(input) == "45%")
    #expect(StatusBarFigures.accessibilityLabel(input) == "Other models 45 percent used")
}

@Test func statusBarSpendPlusOnePoolOmitsLetter() {
    let input = figures(spend: true, other: true)
    #expect(StatusBarFigures.statusText(input) == "$12.40 · 45%")
}

@Test func statusBarBothPoolsUseLetters() {
    let input = figures(cursor: true, other: true)
    #expect(StatusBarFigures.statusText(input) == "C 72% · O 45%")
}

@Test func statusBarAllThree() {
    let input = figures(spend: true, cursor: true, other: true)
    #expect(StatusBarFigures.statusText(input) == "$12.40 · C 72% · O 45%")
    #expect(
        StatusBarFigures.accessibilityLabel(input)
            == "Window spend $12.40, Cursor models 72 percent used, Other models 45 percent used"
    )
}

@Test func statusBarAllOffIsNil() {
    let input = figures()
    #expect(StatusBarFigures.statusText(input) == nil)
    #expect(StatusBarFigures.accessibilityLabel(input) == nil)
}

@Test func statusBarZeroPercentAndAboveOneHundred() {
    let zero = figures(cursor: true, cursorPercent: 0, otherPercent: nil)
    #expect(StatusBarFigures.statusText(zero) == "0%")

    let over = figures(other: true, cursorPercent: nil, otherPercent: 120.2)
    #expect(StatusBarFigures.statusText(over) == "120%")
}

@Test func statusBarMissingPool() {
    let one = figures(cursor: true, cursorPercent: nil)
    #expect(StatusBarFigures.statusText(one) == "—")
    #expect(StatusBarFigures.accessibilityLabel(one) == "Cursor models not loaded")

    let both = figures(cursor: true, other: true, cursorPercent: nil, otherPercent: 45)
    #expect(StatusBarFigures.statusText(both) == "C — · O 45%")
    #expect(
        StatusBarFigures.accessibilityLabel(both)
            == "Cursor models not loaded, Other models 45 percent used"
    )
}

@Test func statusBarSpendPlaceholder() {
    let input = figures(spend: true, windowDollars: 0, spendIsPlaceholder: true)
    #expect(StatusBarFigures.statusText(input) == "$—.——")
    #expect(StatusBarFigures.accessibilityLabel(input) == "Window spend $—.——")
}

@Test func statusBarGrokBotAloneOmitsLetter() {
    let input = figures(grok: true)
    #expect(StatusBarFigures.statusText(input) == "10%")
    #expect(StatusBarFigures.accessibilityLabel(input) == "Grok Bot 10 percent used")
}

@Test func statusBarGrokBotWithAnotherPoolUsesLetters() {
    let input = figures(cursor: true, grok: true)
    #expect(StatusBarFigures.statusText(input) == "C 72% · GB 10%")
    #expect(
        StatusBarFigures.accessibilityLabel(input)
            == "Cursor models 72 percent used, Grok Bot 10 percent used"
    )
}

@Test func statusBarSpendPlusGrokBotOmitsLetter() {
    let input = figures(spend: true, grok: true)
    #expect(StatusBarFigures.statusText(input) == "$12.40 · 10%")
}

@Test func statusBarAllFiguresIncludeGrokBot() {
    let input = figures(spend: true, cursor: true, other: true, grok: true)
    #expect(StatusBarFigures.statusText(input) == "$12.40 · C 72% · O 45% · GB 10%")
    #expect(
        StatusBarFigures.accessibilityLabel(input)
            == "Window spend $12.40, Cursor models 72 percent used, Other models 45 percent used, Grok Bot 10 percent used"
    )
}

@Test func statusBarMissingGrokBot() {
    let input = figures(grok: true, grokPercent: nil)
    #expect(StatusBarFigures.statusText(input) == "—")
    #expect(StatusBarFigures.accessibilityLabel(input) == "Grok Bot not loaded")
}

@Test func statusBarCursorSpendOnly() {
    let input = figures(spend: true)
    #expect(StatusBarFigures.statusText(input) == "$12.40")
}

@Test func statusBarCursorSpendAndClaudeSpend() {
    let input = figures(spend: true, claudeSpend: true)
    #expect(StatusBarFigures.statusText(input) == "$12.40 · CC ~$31.20")
    #expect(
        StatusBarFigures.accessibilityLabel(input)
            == "Window spend $12.40, Claude Code estimated $31.20"
    )
}

@Test func statusBarClaudeSpendOnlyOmitsTag() {
    let input = figures(claudeSpend: true)
    #expect(StatusBarFigures.statusText(input) == "~$31.20")
    #expect(StatusBarFigures.accessibilityLabel(input) == "Claude Code estimated $31.20")
}

@Test func statusBarCursorSpendFiveHourAndWeekly() {
    let input = figures(spend: true, claudeFiveHour: true, claudeWeekly: true)
    #expect(StatusBarFigures.statusText(input) == "$12.40 · 5h 62% · wk 34%")
    #expect(
        StatusBarFigures.accessibilityLabel(input)
            == "Window spend $12.40, 5-hour limit 62 percent used, Weekly limit 34 percent used"
    )
}

@Test func statusBarClaudeSpendPlaceholder() {
    let input = figures(claudeSpend: true, claudeDollars: nil, claudeSpendIsPlaceholder: true)
    #expect(StatusBarFigures.statusText(input) == "~$—")
    #expect(StatusBarFigures.accessibilityLabel(input) == "Claude Code estimated $—")
}

@Test func statusBarClaudeSpendOmitsTagWithoutCursorSpend() {
    let input = figures(cursor: true, claudeSpend: true)
    #expect(StatusBarFigures.statusText(input) == "72% · ~$31.20")
}

@Test func statusBarClaudeFiguresFollowGrokBot() {
    let input = figures(
        spend: true,
        cursor: true,
        other: true,
        grok: true,
        claudeSpend: true,
        claudeFiveHour: true,
        claudeWeekly: true
    )
    #expect(
        StatusBarFigures.statusText(input)
            == "$12.40 · C 72% · O 45% · GB 10% · CC ~$31.20 · 5h 62% · wk 34%"
    )
}

@Test func statusBarMissingClaudeLimits() {
    let input = figures(
        claudeFiveHour: true,
        claudeFiveHourPercent: nil,
        claudeWeekly: true,
        claudeWeeklyPercent: nil
    )
    #expect(StatusBarFigures.statusText(input) == "5h — · wk —")
    #expect(
        StatusBarFigures.accessibilityLabel(input)
            == "5-hour limit not loaded, Weekly limit not loaded"
    )
}

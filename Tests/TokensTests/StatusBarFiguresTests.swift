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
    grokPercent: Double? = 10.2
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
        grokBotPercent: grokPercent
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

@Test func statusBarHeaderSpendOnly() {
    let header = StatusBarFigures.header(figures(spend: true))
    #expect(header.hero == "$12.40")
    #expect(header.companions.isEmpty)
    #expect(header.caption == nil)
    #expect(header.showsTimelineSpendBelow == false)
}

@Test func statusBarHeaderAllOffMatchesSpend() {
    let header = StatusBarFigures.header(figures(windowDollars: 0, spendIsPlaceholder: true))
    #expect(header.hero == "$—.——")
    #expect(header.companions.isEmpty)
    #expect(header.caption == nil)
    #expect(header.showsTimelineSpendBelow == false)
    #expect(header.accessibilityLabel == "Window spend $—.——")
}

@Test func statusBarHeaderPercentOnlyKeepsTimelineSpendBelow() {
    let header = StatusBarFigures.header(figures(cursor: true))
    #expect(header.hero == "72%")
    #expect(header.companions.isEmpty)
    #expect(header.caption == "Cursor models used this cycle")
    #expect(header.showsTimelineSpendBelow == true)
    #expect(header.timelineSpend == "$12.40")
}

@Test func statusBarHeaderBothPercents() {
    let header = StatusBarFigures.header(figures(cursor: true, other: true))
    #expect(header.hero == "C 72%")
    #expect(header.companions == ["O 45%"])
    #expect(header.caption == "Cursor models used this cycle · Other models used this cycle")
    #expect(header.showsTimelineSpendBelow == true)
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

@Test func statusBarHeaderGrokBotWeekCaption() {
    let header = StatusBarFigures.header(figures(grok: true))
    #expect(header.hero == "10%")
    #expect(header.caption == "Grok Bot used this week")
    #expect(header.showsTimelineSpendBelow == true)
}

@Test func statusBarHeaderSpendStaysHero() {
    let header = StatusBarFigures.header(figures(spend: true, cursor: true, other: true))
    #expect(header.hero == "$12.40")
    #expect(header.companions == ["C 72%", "O 45%"])
    #expect(header.caption == "Cursor models used this cycle · Other models used this cycle")
    #expect(header.showsTimelineSpendBelow == false)
    #expect(header.timelineSpend == "$12.40")
}

import Testing
@testable import Tokens

private func cursorSource(
    enabled: Bool = true,
    available: Bool = true,
    burnLevel: BurnLevel = .calm,
    spend: Bool = false,
    cursor: Bool = false,
    other: Bool = false,
    grok: Bool = false,
    windowDollars: Double = 12.40,
    spendIsPlaceholder: Bool = false
) -> MenuBarState.Cursor {
    MenuBarState.Cursor(
        enabled: enabled,
        available: available,
        burnLevel: burnLevel,
        showsWindowSpend: spend,
        showsCursorModels: cursor,
        showsOtherModels: other,
        showsGrokBot: grok,
        windowDollars: windowDollars,
        spendIsPlaceholder: spendIsPlaceholder,
        cursorModelsPercent: 72.4,
        otherModelsPercent: 45,
        grokBotPercent: 10.2
    )
}

private func claudeSource(
    installed: Bool = true,
    enabled: Bool = true,
    burnLevel: BurnLevel = .calm,
    spend: Bool = false,
    dollars: Double? = 31.20,
    spendIsPlaceholder: Bool = false,
    fiveHour: Bool = false,
    fiveHourPercent: Double? = nil,
    weekly: Bool = false,
    weeklyPercent: Double? = nil,
    limitsEnabled: Bool = false
) -> MenuBarState.Claude {
    MenuBarState.Claude(
        installed: installed,
        enabled: enabled,
        burnLevel: burnLevel,
        showsSpend: spend,
        dollars: dollars,
        spendIsPlaceholder: spendIsPlaceholder,
        showsFiveHour: fiveHour,
        fiveHourPercent: fiveHourPercent,
        showsWeekly: weekly,
        weeklyPercent: weeklyPercent,
        limitsEnabled: limitsEnabled
    )
}

@Test func menuBarClaudeSpendOnly() {
    let presentation = MenuBarState.presentation(
        cursor: cursorSource(),
        claude: claudeSource(spend: true)
    )
    #expect(presentation.statusText == "~$31.20")
    #expect(presentation.accessibilityText == "Claude Code estimated $31.20")
    #expect(presentation.burnLevel == .calm)
}

@Test func menuBarHidesClaudeWhenNotInstalledOrDisabled() {
    let notInstalled = MenuBarState.presentation(
        cursor: cursorSource(spend: true),
        claude: claudeSource(installed: false, burnLevel: .critical, spend: true)
    )
    #expect(notInstalled.statusText == "$12.40")
    #expect(notInstalled.burnLevel == .calm)

    let disabled = MenuBarState.presentation(
        cursor: cursorSource(spend: true),
        claude: claudeSource(enabled: false, burnLevel: .error, spend: true, fiveHour: true, limitsEnabled: true)
    )
    #expect(disabled.statusText == "$12.40")
    #expect(disabled.burnLevel == .calm)
}

@Test func menuBarUsesTheMoreSevereBurnLevel() {
    let critical = MenuBarState.presentation(
        cursor: cursorSource(burnLevel: .elevated),
        claude: claudeSource(burnLevel: .critical)
    )
    #expect(critical.burnLevel == .critical)

    let error = MenuBarState.presentation(
        cursor: cursorSource(burnLevel: .critical),
        claude: claudeSource(burnLevel: .error)
    )
    #expect(error.burnLevel == .error)

    let cursorError = MenuBarState.presentation(
        cursor: cursorSource(burnLevel: .error),
        claude: claudeSource(burnLevel: .elevated)
    )
    #expect(cursorError.burnLevel == .error)
}

@Test func menuBarIgnoresADisabledSourceError() {
    let presentation = MenuBarState.presentation(
        cursor: cursorSource(enabled: false, burnLevel: .error),
        claude: claudeSource(burnLevel: .elevated)
    )
    #expect(presentation.burnLevel == .elevated)
}

@Test func menuBarLimitsStayHiddenUntilEnabled() {
    let hidden = MenuBarState.presentation(
        cursor: cursorSource(spend: true),
        claude: claudeSource(fiveHour: true, fiveHourPercent: 62, weekly: true, weeklyPercent: 34)
    )
    #expect(hidden.statusText == "$12.40")

    let shown = MenuBarState.presentation(
        cursor: cursorSource(spend: true),
        claude: claudeSource(
            fiveHour: true,
            fiveHourPercent: 62,
            weekly: true,
            weeklyPercent: 34,
            limitsEnabled: true
        )
    )
    #expect(shown.statusText == "$12.40 · 5h 62% · wk 34%")
}

@Test func menuBarClaudeOnlyDropsCursorWindowSpend() {
    let presentation = MenuBarState.presentation(
        cursor: cursorSource(available: false, spend: true, cursor: true, other: true, grok: true),
        claude: claudeSource(spend: true)
    )
    #expect(presentation.statusText == "~$31.20")
}

@Test func menuBarDisabledCursorDropsCursorFigures() {
    let presentation = MenuBarState.presentation(
        cursor: cursorSource(enabled: false, spend: true),
        claude: claudeSource(spend: true)
    )
    #expect(presentation.statusText == "~$31.20")
}

@Test func menuBarClaudeOnlyPlaceholder() {
    let presentation = MenuBarState.presentation(
        cursor: cursorSource(available: false, spend: true, spendIsPlaceholder: true),
        claude: claudeSource(spend: true, dollars: nil, spendIsPlaceholder: true)
    )
    #expect(presentation.statusText == "~$—")
}

@Test func menuBarKeepsCursorFiguresWhenClaudeCannotReplaceIt() {
    let unavailable = MenuBarState.presentation(
        cursor: cursorSource(available: false, spend: true),
        claude: claudeSource(enabled: false, spend: true)
    )
    #expect(unavailable.statusText == "$12.40")

    let missing = MenuBarState.presentation(
        cursor: cursorSource(available: false, spend: true),
        claude: claudeSource(installed: false, spend: true)
    )
    #expect(missing.statusText == "$12.40")
}

@Test func menuBarClaudePlaceholderBeforeFirstIndex() {
    let presentation = MenuBarState.presentation(
        cursor: cursorSource(),
        claude: claudeSource(spend: true, dollars: nil, spendIsPlaceholder: true)
    )
    #expect(presentation.statusText == "~$—")
}

@Test func claudeCodeHintShowsOnceWhileSpendIsOff() {
    #expect(
        ClaudeCodeHint.shouldShow(
            claudeInstalled: true,
            claudeEnabled: true,
            cursorAvailable: true,
            showsClaudeSpend: false,
            hintDismissed: false
        )
    )
    #expect(
        !ClaudeCodeHint.shouldShow(
            claudeInstalled: true,
            claudeEnabled: false,
            cursorAvailable: true,
            showsClaudeSpend: false,
            hintDismissed: false
        )
    )
    #expect(
        !ClaudeCodeHint.shouldShow(
            claudeInstalled: false,
            claudeEnabled: true,
            cursorAvailable: true,
            showsClaudeSpend: false,
            hintDismissed: false
        )
    )
    #expect(
        !ClaudeCodeHint.shouldShow(
            claudeInstalled: true,
            claudeEnabled: true,
            cursorAvailable: false,
            showsClaudeSpend: false,
            hintDismissed: false
        )
    )
    #expect(
        !ClaudeCodeHint.shouldShow(
            claudeInstalled: true,
            claudeEnabled: true,
            cursorAvailable: true,
            showsClaudeSpend: true,
            hintDismissed: false
        )
    )
    #expect(
        !ClaudeCodeHint.shouldShow(
            claudeInstalled: true,
            claudeEnabled: true,
            cursorAvailable: true,
            showsClaudeSpend: false,
            hintDismissed: true
        )
    )
}

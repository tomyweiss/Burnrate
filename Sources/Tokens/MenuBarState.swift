import Foundation

/// Menu-bar text and icon from the Cursor and Claude Code stores.
/// Dollar figures stay separate; this only decides which parts are visible.
enum MenuBarState {
    struct Cursor: Equatable, Sendable {
        var enabled: Bool
        /// False after a missing Cursor login. Figures stay up until Claude Code can replace them.
        var available: Bool
        var burnLevel: BurnLevel
        var showsWindowSpend: Bool
        var showsCursorModels: Bool
        var showsOtherModels: Bool
        var showsGrokBot: Bool
        var windowDollars: Double
        var spendIsPlaceholder: Bool
        var cursorModelsPercent: Double?
        var otherModelsPercent: Double?
        var grokBotPercent: Double?
    }

    struct Claude: Equatable, Sendable {
        var installed: Bool
        var enabled: Bool
        var burnLevel: BurnLevel
        var showsSpend: Bool
        var dollars: Double?
        var spendIsPlaceholder: Bool
        var showsFiveHour: Bool
        var fiveHourPercent: Double?
        var showsWeekly: Bool
        var weeklyPercent: Double?
        /// Plan-limit figures stay hidden until this is on.
        var limitsEnabled: Bool
    }

    struct Presentation: Equatable, Sendable {
        var input: StatusBarFigures.Input
        var burnLevel: BurnLevel
        var statusText: String?
        var accessibilityText: String?
    }

    /// Cursor window spend, pool percents, and Grok Bot are omitted when Cursor
    /// is switched off, and when Cursor is signed out while Claude Code is on.
    static func showsCursorParts(cursor: Cursor, claude: Claude) -> Bool {
        guard cursor.enabled else { return false }
        if !cursor.available, claude.installed, claude.enabled { return false }
        return true
    }

    static func presentation(cursor: Cursor, claude: Claude) -> Presentation {
        let claudeVisible = claude.installed && claude.enabled
        let showLimits = claudeVisible && claude.limitsEnabled
        let cursorVisible = showsCursorParts(cursor: cursor, claude: claude)
        let input = StatusBarFigures.Input(
            showsWindowSpend: cursorVisible && cursor.showsWindowSpend,
            showsCursorModels: cursorVisible && cursor.showsCursorModels,
            showsOtherModels: cursorVisible && cursor.showsOtherModels,
            showsGrokBot: cursorVisible && cursor.showsGrokBot,
            windowDollars: cursor.windowDollars,
            spendIsPlaceholder: cursor.spendIsPlaceholder,
            cursorModelsPercent: cursor.cursorModelsPercent,
            otherModelsPercent: cursor.otherModelsPercent,
            grokBotPercent: cursor.grokBotPercent,
            showsClaudeSpend: claudeVisible && claude.showsSpend,
            claudeDollars: claude.dollars,
            claudeSpendIsPlaceholder: claude.spendIsPlaceholder,
            showsClaudeFiveHour: showLimits && claude.showsFiveHour,
            claudeFiveHourPercent: claude.fiveHourPercent,
            showsClaudeWeekly: showLimits && claude.showsWeekly,
            claudeWeeklyPercent: claude.weeklyPercent
        )
        return Presentation(
            input: input,
            burnLevel: combinedBurn(cursor: cursor, claude: claude, claudeVisible: claudeVisible),
            statusText: StatusBarFigures.statusText(input),
            accessibilityText: StatusBarFigures.accessibilityLabel(input)
        )
    }

    /// What the menu bar shows right now, read from the live stores.
    /// A generic limits failure keeps the last percents. Sign-in problems hide them.
    @MainActor
    static func presentation(
        settings: SettingsStore,
        store: UsageStore,
        claudeCode: ClaudeCodeStore
    ) -> Presentation {
        let limitsError = claudeCode.limitsError
        let limitFiguresVisible = limitsError == nil || limitsError == ClaudeLimitsClient.unavailable
        return presentation(
            cursor: Cursor(
                enabled: settings.cursorEnabled,
                available: store.isCursorAvailable,
                burnLevel: store.burnLevel,
                showsWindowSpend: settings.statusBarShowsWindowSpend,
                showsCursorModels: settings.statusBarShowsCursorModels,
                showsOtherModels: settings.statusBarShowsOtherModels,
                showsGrokBot: settings.statusBarShowsGrokBot,
                windowDollars: store.snapshot.windowDollars,
                spendIsPlaceholder: !store.hasCompletedFetch && store.lastError == nil,
                cursorModelsPercent: store.includedPools?.cursorModelsPercent,
                otherModelsPercent: store.includedPools?.otherModelsPercent,
                grokBotPercent: store.grokBotUsage?.percentUsed
            ),
            claude: Claude(
                installed: claudeCode.isInstalled,
                enabled: settings.claudeCodeEnabled,
                burnLevel: claudeCode.burnLevel,
                showsSpend: settings.showsClaudeSpend(
                    cursorAvailable: store.isCursorAvailable,
                    claudeInstalled: claudeCode.isInstalled
                ),
                dollars: claudeCode.snapshot.windowDollars,
                spendIsPlaceholder: !claudeCode.hasCompletedFetch && claudeCode.lastError == nil,
                showsFiveHour: settings.statusBarShowsClaudeFiveHour,
                fiveHourPercent: limitFiguresVisible ? claudeCode.limits?.fiveHour?.percentUsed : nil,
                showsWeekly: settings.statusBarShowsClaudeWeekly,
                weeklyPercent: limitFiguresVisible ? claudeCode.limits?.weekly?.percentUsed : nil,
                limitsEnabled: settings.claudeLimitsEnabled
            )
        )
    }

    /// The worse of the enabled sources. A disabled or missing source does not
    /// contribute its flame or its warning triangle.
    private static func combinedBurn(cursor: Cursor, claude: Claude, claudeVisible: Bool) -> BurnLevel {
        var level = BurnLevel.calm
        if cursor.enabled {
            level = BurnLevel.moreSevere(level, cursor.burnLevel)
        }
        if claudeVisible {
            level = BurnLevel.moreSevere(level, claude.burnLevel)
        }
        return level
    }
}

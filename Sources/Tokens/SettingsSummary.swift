import Foundation

/// Current value shown beside each row on the Settings list.
enum SettingsSummary {
    static func sources(cursorEnabled: Bool, claudeEnabled: Bool) -> String {
        switch (cursorEnabled, claudeEnabled) {
        case (true, true): "Cursor, Claude Code"
        case (true, false): "Cursor"
        case (false, true): "Claude Code"
        case (false, false): "None"
        }
    }

    /// Names up to two menu bar figures, and counts them past that.
    static func menuBar(_ input: StatusBarFigures.Input) -> String {
        var names: [String] = []
        if input.showsWindowSpend { names.append("Spend") }
        if input.showsCursorModels { names.append("Cursor models") }
        if input.showsOtherModels { names.append("Other models") }
        if input.showsGrokBot { names.append("Grok Bot") }
        if input.showsClaudeSpend { names.append("Claude spend") }
        if input.showsClaudeFiveHour { names.append("5h limit") }
        if input.showsClaudeWeekly { names.append("Weekly limit") }
        switch names.count {
        case 0: return "Flame only"
        case 1, 2: return names.joined(separator: ", ")
        default: return "\(names.count) figures"
        }
    }

    static func spikeAlert(thresholdDollars: Double, windowMinutes: Int) -> String {
        "\(MoneyFormat.dollars(thresholdDollars)) in \(windowMinutes) min"
    }

    static func stopClaude(isArmed: Bool, isTripped: Bool) -> String {
        if isTripped { return "Stopped" }
        return isArmed ? "Armed" : "Off"
    }

    static func panel(visibleTabCount: Int) -> String {
        visibleTabCount == 1 ? "1 tab" : "\(visibleTabCount) tabs"
    }

    static func data(refreshIntervalSeconds: Double, timezoneIdentifier: String?) -> String {
        let poll = SettingsStore.intervalLabel(refreshIntervalSeconds)
        return "Poll \(poll) · \(timezoneIdentifier ?? "System timezone")"
    }

    /// The waiting update when there is one, otherwise the installed version.
    static func updates(versionLabel: String, pendingTitle: String?) -> String {
        pendingTitle ?? versionLabel
    }
}

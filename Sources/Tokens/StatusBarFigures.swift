import Foundation

enum StatusBarFigures {
    struct Input: Equatable, Sendable {
        var showsWindowSpend: Bool
        var showsCursorModels: Bool
        var showsOtherModels: Bool
        var showsGrokBot: Bool
        var windowDollars: Double
        var spendIsPlaceholder: Bool
        var cursorModelsPercent: Double?
        var otherModelsPercent: Double?
        var grokBotPercent: Double?
        var showsClaudeSpend: Bool
        var claudeDollars: Double?
        var claudeSpendIsPlaceholder: Bool
        var showsClaudeFiveHour: Bool
        var claudeFiveHourPercent: Double?
        var showsClaudeWeekly: Bool
        var claudeWeeklyPercent: Double?

        init(
            showsWindowSpend: Bool,
            showsCursorModels: Bool = false,
            showsOtherModels: Bool = false,
            showsGrokBot: Bool = false,
            windowDollars: Double = 12.40,
            spendIsPlaceholder: Bool = false,
            cursorModelsPercent: Double? = nil,
            otherModelsPercent: Double? = nil,
            grokBotPercent: Double? = nil,
            showsClaudeSpend: Bool = false,
            claudeDollars: Double? = nil,
            claudeSpendIsPlaceholder: Bool = false,
            showsClaudeFiveHour: Bool = false,
            claudeFiveHourPercent: Double? = nil,
            showsClaudeWeekly: Bool = false,
            claudeWeeklyPercent: Double? = nil
        ) {
            self.showsWindowSpend = showsWindowSpend
            self.showsCursorModels = showsCursorModels
            self.showsOtherModels = showsOtherModels
            self.showsGrokBot = showsGrokBot
            self.windowDollars = windowDollars
            self.spendIsPlaceholder = spendIsPlaceholder
            self.cursorModelsPercent = cursorModelsPercent
            self.otherModelsPercent = otherModelsPercent
            self.grokBotPercent = grokBotPercent
            self.showsClaudeSpend = showsClaudeSpend
            self.claudeDollars = claudeDollars
            self.claudeSpendIsPlaceholder = claudeSpendIsPlaceholder
            self.showsClaudeFiveHour = showsClaudeFiveHour
            self.claudeFiveHourPercent = claudeFiveHourPercent
            self.showsClaudeWeekly = showsClaudeWeekly
            self.claudeWeeklyPercent = claudeWeeklyPercent
        }
    }

    struct Header: Equatable, Sendable {
        var hero: String
        var companions: [String]
        var caption: String?
        var showsTimelineSpendBelow: Bool
        var timelineSpend: String
        var accessibilityLabel: String
    }

    static func statusText(_ input: Input) -> String? {
        let flags = Flags(input)
        guard flags.showsAny else { return nil }
        return tokens(input, flags: flags).joined(separator: " · ")
    }

    static func accessibilityLabel(_ input: Input) -> String? {
        let flags = Flags(input)
        guard flags.showsAny else { return nil }
        return labeled(input, flags: flags)
    }

    static func header(_ input: Input) -> Header {
        var flags = Flags(input)
        if !flags.showsAny {
            flags.spend = true
        }
        let parts = tokens(input, flags: flags)
        return Header(
            hero: parts[0],
            companions: Array(parts.dropFirst()),
            caption: poolCaption(flags),
            showsTimelineSpendBelow: !flags.spend,
            timelineSpend: spendText(input),
            accessibilityLabel: labeled(input, flags: flags)
        )
    }

    private struct Flags: Equatable {
        var spend: Bool
        var cursor: Bool
        var other: Bool
        var grok: Bool
        var claudeSpend: Bool
        var fiveHour: Bool
        var weekly: Bool

        var showsAny: Bool {
            spend || cursor || other || grok || claudeSpend || fiveHour || weekly
        }

        /// Cursor-family percents only. Claude limits always carry their own prefix.
        var percentCount: Int {
            [cursor, other, grok].filter { $0 }.count
        }

        init(_ input: Input) {
            spend = input.showsWindowSpend
            cursor = input.showsCursorModels
            other = input.showsOtherModels
            grok = input.showsGrokBot
            claudeSpend = input.showsClaudeSpend
            fiveHour = input.showsClaudeFiveHour
            weekly = input.showsClaudeWeekly
        }
    }

    private static func tokens(_ input: Input, flags: Flags) -> [String] {
        var parts: [String] = []
        let tagPercents = flags.percentCount > 1
        if flags.spend {
            parts.append(spendText(input))
        }
        if flags.cursor {
            parts.append(percentToken(input.cursorModelsPercent, prefix: tagPercents ? "C" : nil))
        }
        if flags.other {
            parts.append(percentToken(input.otherModelsPercent, prefix: tagPercents ? "O" : nil))
        }
        if flags.grok {
            parts.append(percentToken(input.grokBotPercent, prefix: tagPercents ? "GB" : nil))
        }
        if flags.claudeSpend {
            let text = claudeSpendText(input)
            // `CC` only when Cursor window spend is also on, same idea as `C` / `O`.
            parts.append(flags.spend ? "CC \(text)" : text)
        }
        if flags.fiveHour {
            parts.append(percentToken(input.claudeFiveHourPercent, prefix: "5h"))
        }
        if flags.weekly {
            parts.append(percentToken(input.claudeWeeklyPercent, prefix: "wk"))
        }
        return parts
    }

    private static func spendText(_ input: Input) -> String {
        if input.spendIsPlaceholder { return "$—.——" }
        return MoneyFormat.dollars(input.windowDollars)
    }

    private static func claudeSpendText(_ input: Input) -> String {
        guard !input.claudeSpendIsPlaceholder, let dollars = input.claudeDollars else {
            return "~$—"
        }
        return MoneyFormat.estimated(dollars)
    }

    private static func percentToken(_ percent: Double?, prefix: String?) -> String {
        let number = percent.map { "\(IncludedPools.displayPercent($0))%" } ?? "—"
        guard let prefix else { return number }
        return "\(prefix) \(number)"
    }

    private static func poolCaption(_ flags: Flags) -> String? {
        var parts: [String] = []
        if flags.cursor { parts.append("Cursor models used this cycle") }
        if flags.other { parts.append("Other models used this cycle") }
        if flags.grok { parts.append("Grok Bot used this week") }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func labeled(_ input: Input, flags: Flags) -> String {
        var parts: [String] = []
        if flags.spend {
            parts.append("Window spend \(spendText(input))")
        }
        if flags.cursor {
            parts.append(percentAccess("Cursor models", input.cursorModelsPercent))
        }
        if flags.other {
            parts.append(percentAccess("Other models", input.otherModelsPercent))
        }
        if flags.grok {
            parts.append(percentAccess("Grok Bot", input.grokBotPercent))
        }
        if flags.claudeSpend {
            parts.append(claudeSpendAccess(input))
        }
        if flags.fiveHour {
            parts.append(percentAccess("5-hour limit", input.claudeFiveHourPercent))
        }
        if flags.weekly {
            parts.append(percentAccess("Weekly limit", input.claudeWeeklyPercent))
        }
        return parts.joined(separator: ", ")
    }

    private static func claudeSpendAccess(_ input: Input) -> String {
        guard !input.claudeSpendIsPlaceholder, let dollars = input.claudeDollars else {
            return "Claude Code estimated $—"
        }
        return "Claude Code estimated \(MoneyFormat.dollars(dollars))"
    }

    private static func percentAccess(_ name: String, _ percent: Double?) -> String {
        guard let percent else { return "\(name) not loaded" }
        return "\(name) \(IncludedPools.displayPercent(percent)) percent used"
    }
}

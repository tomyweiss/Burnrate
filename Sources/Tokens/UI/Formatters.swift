import Foundation

enum CostStyle: Sendable {
    case billed
    case estimated
}

enum MoneyFormat {
    static func dollars(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func dollarsFromCents(_ cents: Double) -> String {
        dollars(cents / 100.0)
    }

    /// Claude Code estimates, always prefixed so they are not read as a bill.
    static func estimated(_ value: Double) -> String {
        "~\(dollars(value))"
    }

    static func string(_ dollars: Double, style: CostStyle) -> String {
        switch style {
        case .billed: self.dollars(dollars)
        case .estimated: estimated(dollars)
        }
    }

    static func stringFromCents(_ cents: Double, style: CostStyle) -> String {
        string(cents / 100.0, style: style)
    }
}

enum ClaudeTokenLine {
    /// `48.2M tokens · 91% cache read`. Percent is cache read over total, rounded.
    static func string(totalTokens: Int, cacheReadTokens: Int) -> String {
        let percent: Int
        if totalTokens > 0 {
            percent = Int((Double(cacheReadTokens) / Double(totalTokens) * 100).rounded())
        } else {
            percent = 0
        }
        return "\(TokenFormat.compact(totalTokens)) tokens · \(percent)% cache read"
    }

    static func string(snapshot: UsageSnapshot) -> String {
        let total = snapshot.models.reduce(0) { $0 + $1.totalTokens }
        let cacheRead = snapshot.models.reduce(0) { $0 + $1.cacheReadTokens }
        return string(totalTokens: total, cacheReadTokens: cacheRead)
    }

    /// `No price for <model>. Tokens shown, cost excluded`, models joined with ", ".
    static func unpricedCaption(_ models: [String]) -> String? {
        let names = models.filter { !$0.isEmpty }
        guard !names.isEmpty else { return nil }
        return "No price for \(names.joined(separator: ", ")). Tokens shown, cost excluded"
    }
}

enum TokenFormat {
    static func compact(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

enum RelativeTimeFormat {
    static func string(from date: Date, relativeTo now: Date = Date()) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return formatter.localizedString(for: date, relativeTo: now)
    }

    static func string(fromTimestampMs ms: Double, relativeTo now: Date = Date()) -> String {
        let date = Date(timeIntervalSince1970: ms / 1000)
        return string(from: date, relativeTo: now)
    }

    static func clockTime(_ date: Date) -> String {
        date.formatted(date: .omitted, time: .shortened)
    }
}

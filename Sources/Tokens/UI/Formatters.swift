import Foundation

enum MoneyFormat {
    static func dollars(_ value: Double) -> String {
        String(format: "$%.2f", value)
    }

    static func dollarsFromCents(_ cents: Double) -> String {
        dollars(cents / 100.0)
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

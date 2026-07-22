import Foundation

enum UsageTimelinePreset: String, CaseIterable, Codable, Identifiable {
    case today
    case last24Hours
    case last7Days
    case thisBilling

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: "Today"
        case .last24Hours: "Last 24h"
        case .last7Days: "Last 7d"
        case .thisBilling: "This billing"
        }
    }
}

struct UsageTimeWindow: Sendable, Hashable {
    let preset: UsageTimelinePreset
    let timeZone: TimeZone
    let billingDayOfMonth: Int

    init(
        preset: UsageTimelinePreset,
        timeZone: TimeZone,
        billingDayOfMonth: Int = 1
    ) {
        self.preset = preset
        self.timeZone = timeZone
        self.billingDayOfMonth = min(max(billingDayOfMonth, 1), 31)
    }

    var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        return calendar
    }

    func dateRange(now: Date = Date()) -> (start: Date, end: Date) {
        let end = now
        let start: Date
        switch preset {
        case .today:
            start = calendar.startOfDay(for: now)
        case .last24Hours:
            start = now.addingTimeInterval(-24 * 60 * 60)
        case .last7Days:
            start = now.addingTimeInterval(-7 * 24 * 60 * 60)
        case .thisBilling:
            start = billingCycleStart(before: now)
        }
        return (start, end)
    }

    func billingCycleStart(before date: Date) -> Date {
        let components = calendar.dateComponents([.year, .month, .day], from: date)
        guard let year = components.year, let month = components.month, let day = components.day else {
            return calendar.startOfDay(for: date)
        }

        let effectiveDayThisMonth = effectiveBillingDay(year: year, month: month)
        if day >= effectiveDayThisMonth {
            return billingDate(year: year, month: month, day: effectiveDayThisMonth)
        }

        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: date) else {
            return billingDate(year: year, month: month, day: effectiveDayThisMonth)
        }
        let prevComponents = calendar.dateComponents([.year, .month], from: previousMonth)
        guard let prevYear = prevComponents.year, let prevMonth = prevComponents.month else {
            return billingDate(year: year, month: month, day: effectiveDayThisMonth)
        }
        let effectiveDayPrevMonth = effectiveBillingDay(year: prevYear, month: prevMonth)
        return billingDate(year: prevYear, month: prevMonth, day: effectiveDayPrevMonth)
    }

    func bucketCount(now: Date = Date()) -> Int {
        switch preset {
        case .today, .last24Hours:
            return 24
        case .last7Days:
            return 7
        case .thisBilling:
            let range = dateRange(now: now)
            let days = calendar.dateComponents([.day], from: range.start, to: now).day ?? 0
            return min(max(days + 1, 1), 31)
        }
    }

    func bucketIndex(for eventDate: Date, now: Date = Date()) -> Int? {
        let range = dateRange(now: now)
        guard eventDate >= range.start, eventDate <= range.end else { return nil }

        switch preset {
        case .today:
            let hour = calendar.component(.hour, from: eventDate)
            return (0..<24).contains(hour) ? hour : nil
        case .last24Hours:
            let elapsed = eventDate.timeIntervalSince(range.start)
            let index = Int(elapsed / 3600)
            return (0..<24).contains(index) ? index : nil
        case .last7Days:
            let elapsed = eventDate.timeIntervalSince(range.start)
            let index = Int(elapsed / (24 * 3600))
            return (0..<7).contains(index) ? index : nil
        case .thisBilling:
            let startDay = calendar.startOfDay(for: range.start)
            let eventDay = calendar.startOfDay(for: eventDate)
            let days = calendar.dateComponents([.day], from: startDay, to: eventDay).day ?? 0
            let count = bucketCount(now: now)
            return (0..<count).contains(days) ? days : nil
        }
    }

    func currentBucketIndex(now: Date = Date()) -> Int {
        switch preset {
        case .today:
            return calendar.component(.hour, from: now)
        case .last24Hours:
            return 23
        case .last7Days:
            return 6
        case .thisBilling:
            return bucketCount(now: now) - 1
        }
    }

    func shouldDimBucket(_ index: Int, now: Date = Date()) -> Bool {
        switch preset {
        case .today:
            return index > currentBucketIndex(now: now)
        default:
            return false
        }
    }

    func sparklineStartLabel(now: Date = Date()) -> String {
        let range = dateRange(now: now)
        switch preset {
        case .today:
            return "12am"
        case .last24Hours:
            return "-24h"
        case .last7Days:
            return "-7d"
        case .thisBilling:
            return Self.shortDateFormatter(timeZone: timeZone).string(from: range.start)
        }
    }

    var sparklineEndLabel: String { "now" }

    var emptyStateMessage: String {
        switch preset {
        case .today:
            return "No spend since midnight"
        case .last24Hours:
            return "No spend in the last 24 hours"
        case .last7Days:
            return "No spend in the last 7 days"
        case .thisBilling:
            return "No spend this billing cycle"
        }
    }

    var displayName: String { preset.displayName }

    private func effectiveBillingDay(year: Int, month: Int) -> Int {
        guard let range = calendar.range(of: .day, in: .month, for: billingDate(year: year, month: month, day: 1)) else {
            return billingDayOfMonth
        }
        return min(billingDayOfMonth, range.count)
    }

    private func billingDate(year: Int, month: Int, day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 0
        components.minute = 0
        components.second = 0
        return calendar.date(from: components) ?? Date()
    }

    private static func shortDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.dateFormat = "MMM d"
        return formatter
    }
}

import Foundation

enum UsageTimelinePreset: String, CaseIterable, Codable, Identifiable {
    case today
    case last24Hours
    case last7Days
    case thisBilling
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .today: "Today"
        case .last24Hours: "Last 24h"
        case .last7Days: "Last 7d"
        case .thisBilling: "This billing"
        case .custom: "Custom"
        }
    }
}

struct UsageTimeWindow: Sendable, Hashable {
    let preset: UsageTimelinePreset
    let timeZone: TimeZone
    let billingDayOfMonth: Int
    /// Day-granularity bounds for the `.custom` preset; both days are inclusive.
    let customStart: Date
    let customEnd: Date

    init(
        preset: UsageTimelinePreset,
        timeZone: TimeZone,
        billingDayOfMonth: Int = 1,
        customStart: Date = Date(),
        customEnd: Date = Date()
    ) {
        self.preset = preset
        self.timeZone = timeZone
        self.billingDayOfMonth = min(max(billingDayOfMonth, 1), 31)
        self.customStart = min(customStart, customEnd)
        self.customEnd = max(customStart, customEnd)
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
        case .custom:
            let startDay = calendar.startOfDay(for: customStart)
            let endDay = calendar.startOfDay(for: customEnd)
            let endOfEndDay = calendar.date(byAdding: .day, value: 1, to: endDay)?
                .addingTimeInterval(-1) ?? now
            return (min(startDay, now), min(endOfEndDay, now))
        }
        return (start, end)
    }

    /// Number of inclusive days spanned by the `.custom` range.
    var customDayCount: Int {
        let startDay = calendar.startOfDay(for: customStart)
        let endDay = calendar.startOfDay(for: customEnd)
        let days = calendar.dateComponents([.day], from: startDay, to: endDay).day ?? 0
        return max(days, 0) + 1
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
        case .custom:
            // Single day gets hourly resolution; longer ranges get one bar per
            // day, capped so the sparkline bars stay readable.
            let days = customDayCount
            return days == 1 ? 24 : min(days, 60)
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
        case .custom:
            let dayCount = customDayCount
            if dayCount == 1 {
                let hour = calendar.component(.hour, from: eventDate)
                return (0..<24).contains(hour) ? hour : nil
            }
            let startDay = calendar.startOfDay(for: range.start)
            let eventDay = calendar.startOfDay(for: eventDate)
            let dayIndex = calendar.dateComponents([.day], from: startDay, to: eventDay).day ?? 0
            let count = bucketCount(now: now)
            // When the range is longer than the bar cap, several days share a bar.
            let index = dayCount <= count ? dayIndex : dayIndex * count / dayCount
            return (0..<count).contains(index) ? index : nil
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
        case .custom:
            // Only highlight a "current" bar when now falls inside the range.
            return bucketIndex(for: now, now: now) ?? -1
        }
    }

    func shouldDimBucket(_ index: Int, now: Date = Date()) -> Bool {
        switch preset {
        case .today:
            return index > currentBucketIndex(now: now)
        case .custom:
            // A single-day range that is today behaves like Today: dim hours
            // that haven't happened yet.
            guard customDayCount == 1, calendar.isDate(now, inSameDayAs: customEnd) else {
                return false
            }
            return index > calendar.component(.hour, from: now)
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
        case .thisBilling, .custom:
            return Self.shortDateFormatter(timeZone: timeZone).string(from: range.start)
        }
    }

    var sparklineEndLabel: String {
        if preset == .custom, !calendar.isDateInToday(customEnd) {
            return Self.shortDateFormatter(timeZone: timeZone).string(from: customEnd)
        }
        return "now"
    }

    func sparklineBucketLabel(index: Int, now: Date = Date()) -> String {
        let range = dateRange(now: now)
        switch preset {
        case .today:
            return hourLabel(hour: index)
        case .last24Hours:
            let bucketStart = range.start.addingTimeInterval(TimeInterval(index) * 3600)
            return hourLabel(for: bucketStart)
        case .last7Days:
            let dayStart = calendar.date(
                byAdding: .day,
                value: index,
                to: calendar.startOfDay(for: range.start)
            ) ?? range.start
            return Self.shortDateFormatter(timeZone: timeZone).string(from: dayStart)
        case .thisBilling:
            let dayStart = calendar.date(
                byAdding: .day,
                value: index,
                to: calendar.startOfDay(for: range.start)
            ) ?? range.start
            return Self.shortDateFormatter(timeZone: timeZone).string(from: dayStart)
        case .custom:
            if customDayCount == 1 {
                return hourLabel(hour: index)
            }
            let count = bucketCount(now: now)
            let dayCount = customDayCount
            // When several days share a bar, label the bar with its first day.
            let dayIndex = dayCount <= count ? index : index * dayCount / count
            let dayStart = calendar.date(
                byAdding: .day,
                value: dayIndex,
                to: calendar.startOfDay(for: range.start)
            ) ?? range.start
            return Self.shortDateFormatter(timeZone: timeZone).string(from: dayStart)
        }
    }

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
        case .custom:
            return "No spend in this date range"
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

    private func hourLabel(hour: Int) -> String {
        let normalized = ((hour % 24) + 24) % 24
        switch normalized {
        case 0: return "12am"
        case 1..<12: return "\(normalized)am"
        case 12: return "12pm"
        default: return "\(normalized - 12)pm"
        }
    }

    private func hourLabel(for date: Date) -> String {
        hourLabel(hour: calendar.component(.hour, from: date))
    }
}

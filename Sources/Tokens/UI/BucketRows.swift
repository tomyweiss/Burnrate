import SwiftUI
import TokensCore

/// One included bucket or plan limit: a name, how much is used, and an optional note such as a reset time.
struct BucketMeter: Equatable, Sendable {
    var title: String
    /// Nil until the source reports it.
    var percent: Double?
    var detail: String?
    /// Tooltip saying what the percent is a share of.
    var help = ""

    var accessibilityLabel: String {
        guard let percent else { return "\(title), not loaded" }
        let base = "\(title), \(IncludedPools.displayPercent(percent)) percent used"
        guard let detail else { return base }
        return "\(base), \(detail)"
    }
}

enum CursorBucketMeters {
    /// Cursor models is always shown. Other models stays up while pools are
    /// loading and comes down once a period reports no separate bucket.
    /// Grok Bot is left out when the account has no weekly allowance.
    static func make(
        pools: IncludedPools?,
        grokBot: GrokBotUsage?,
        timeZone: TimeZone = .current
    ) -> [BucketMeter] {
        var meters = [BucketMeter(
            title: "Cursor models",
            percent: pools?.cursorModelsPercent,
            detail: nil,
            help: "Share of the Cursor models pool used this billing cycle"
        )]
        if pools?.hasOtherModelsBucket ?? true {
            meters.append(BucketMeter(
                title: "Other models",
                percent: pools?.otherModelsPercent,
                detail: nil,
                help: "Share of the Other models pool used this billing cycle"
            ))
        }
        if let grokBot {
            meters.append(BucketMeter(
                title: "Grok Bot",
                percent: grokBot.percentUsed,
                detail: grokBot.resetCaption(timeZone: timeZone).map { "resets \($0)" },
                help: "Share of the Grok Bot weekly included pool used"
            ))
        }
        return meters
    }
}

enum ClaudeLimitGauges {
    private static let help = "Share of this Claude plan limit used"

    /// Shown until limits load, so the rows don't appear from nothing.
    static let placeholders = [
        BucketMeter(title: "5h limit", percent: nil, detail: nil, help: help),
        BucketMeter(title: "Weekly limit", percent: nil, detail: nil, help: help)
    ]

    /// Text that replaces the limit rows, or nil to show the rows. A generic
    /// failure keeps the last rows and only shows when there are none.
    static func note(error: String?, hasLimits: Bool) -> String? {
        guard let error else { return nil }
        if error == ClaudeLimitsClient.unavailable, hasLimits { return nil }
        return error
    }

    /// Panel order. The 5h and weekly rows come as a pair once either loads, with
    /// "—" for a window the response left out. Per-model windows and a disabled
    /// extra-usage pool are left out when absent, the same way an absent Other
    /// models bucket hides its row.
    static func make(
        fiveHour: ClaudeLimitWindow?,
        weekly: ClaudeLimitWindow?,
        weeklyOpus: ClaudeLimitWindow?,
        weeklySonnet: ClaudeLimitWindow?,
        extraUsage: ClaudeExtraUsage?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [BucketMeter] {
        var meters: [BucketMeter] = []
        if fiveHour != nil || weekly != nil {
            meters.append(meter("5h limit", window: fiveHour, now: now, calendar: calendar))
            meters.append(meter("Weekly limit", window: weekly, now: now, calendar: calendar))
        }
        if let weeklyOpus {
            meters.append(meter("Opus weekly", window: weeklyOpus, now: now, calendar: calendar))
        }
        if let weeklySonnet {
            meters.append(meter("Sonnet weekly", window: weeklySonnet, now: now, calendar: calendar))
        }
        if let extraUsage {
            meters.append(BucketMeter(
                title: "Extra usage",
                percent: extraUsage.percentUsed,
                detail: extraUsage.amountDetail,
                help: help
            ))
        }
        return meters
    }

    private static func meter(
        _ title: String,
        window: ClaudeLimitWindow?,
        now: Date,
        calendar: Calendar
    ) -> BucketMeter {
        BucketMeter(
            title: title,
            percent: window?.percentUsed,
            detail: window?.resetsDetail(now: now, calendar: calendar),
            help: help
        )
    }
}

extension ClaudeLimitWindow {
    /// "resets 3:40pm" when it is today, "resets Thu" during the coming week,
    /// otherwise "resets Nov 20".
    func resetsDetail(now: Date = .now, calendar: Calendar = .current) -> String? {
        guard let resetsAt else { return nil }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = calendar.timeZone
        if calendar.isDate(resetsAt, inSameDayAs: now) {
            formatter.dateFormat = "h:mma"
            formatter.amSymbol = "am"
            formatter.pmSymbol = "pm"
            return "resets \(formatter.string(from: resetsAt))"
        }
        let start = calendar.startOfDay(for: now)
        let resetDay = calendar.startOfDay(for: resetsAt)
        if let day = calendar.dateComponents([.day], from: start, to: resetDay).day, (1...6).contains(day) {
            formatter.dateFormat = "EEE"
            return "resets \(formatter.string(from: resetsAt))"
        }
        formatter.dateFormat = "MMM d"
        return "resets \(formatter.string(from: resetsAt))"
    }
}

/// Column widths and row heights shared by every bucket row, so the bars line
/// up and both sources can reserve the same space.
enum BucketLayout {
    static let labelWidth: CGFloat = 104
    static let valueWidth: CGFloat = 44
    static let detailWidth: CGFloat = 92
    static let columnSpacing: CGFloat = 12
    static let rowHeight: CGFloat = 20
    static let rowSpacing: CGFloat = 9

    /// Height of `rows` stacked meter rows.
    static func metersHeight(rows: Int) -> CGFloat {
        guard rows > 0 else { return 0 }
        return CGFloat(rows) * rowHeight + CGFloat(rows - 1) * rowSpacing
    }
}

private struct BucketLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .font(.subheadline.weight(.medium))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .frame(width: BucketLayout.labelWidth, alignment: .leading)
    }
}

/// Name, bar, percent, and reset note for one bucket.
struct BucketMeterRow: View {
    let meter: BucketMeter

    var body: some View {
        HStack(spacing: BucketLayout.columnSpacing) {
            BucketLabel(title: meter.title)

            SpendBar(segments: [SpendBar.Segment(fraction: fraction, tint: tint)])

            Text(meter.percent.map { "\(IncludedPools.displayPercent($0))%" } ?? "—")
                .font(.callout.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .frame(width: BucketLayout.valueWidth, alignment: .trailing)

            Text(meter.detail ?? "")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(width: BucketLayout.detailWidth, alignment: .leading)
        }
        .frame(height: BucketLayout.rowHeight)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(meter.accessibilityLabel)
        .help(meter.help)
    }

    private var fraction: Double {
        guard let percent = meter.percent else { return 0 }
        return min(max(percent, 0), 100) / 100
    }

    /// Orange once the bucket is used up, because usage past that point
    /// flows into on-demand spend (also orange).
    private var tint: Color {
        (meter.percent ?? 0) >= 100 ? .orange : .accentColor
    }
}

/// A labelled row holding something other than a meter, such as the button that turns plan limits on.
struct BucketNoteRow<Content: View>: View {
    let title: String
    @ViewBuilder var content: () -> Content

    var body: some View {
        HStack(spacing: BucketLayout.columnSpacing) {
            BucketLabel(title: title)
            content()
            Spacer(minLength: 0)
        }
        .frame(minHeight: BucketLayout.rowHeight)
    }
}

/// This cycle's spend: a bar on the same columns as the buckets, the total, and a legend under the bar.
struct CycleSpendRow<Legend: View>: View {
    /// Nil until the source reports it.
    let total: String?
    let segments: [SpendBar.Segment]
    let accessibilityLabel: String
    let help: String
    @ViewBuilder var legend: () -> Legend

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: BucketLayout.columnSpacing) {
                BucketLabel(title: "This cycle")

                SpendBar(segments: segments)

                Text(total ?? "—")
                    .font(.callout.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .frame(
                        width: BucketLayout.valueWidth + BucketLayout.columnSpacing + BucketLayout.detailWidth,
                        alignment: .trailing
                    )
            }
            .frame(height: BucketLayout.rowHeight)

            HStack(spacing: 14) {
                legend()
            }
            .padding(.leading, BucketLayout.labelWidth + BucketLayout.columnSpacing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel)
        .help(help)
    }
}

import SwiftUI
import TokensCore

struct ClaudeLimitGauge: Equatable, Sendable {
    var title: String
    var percent: Double?
    var detail: String?
}

enum ClaudeLimitGauges {
    /// Present buckets only, in panel order. A missing window or a disabled
    /// extra-usage pool is left out, the same way an absent Other models bucket
    /// hides its ring.
    static func make(
        fiveHour: ClaudeLimitWindow?,
        weekly: ClaudeLimitWindow?,
        weeklyOpus: ClaudeLimitWindow?,
        weeklySonnet: ClaudeLimitWindow?,
        extraUsage: ClaudeExtraUsage?,
        now: Date = .now,
        calendar: Calendar = .current
    ) -> [ClaudeLimitGauge] {
        var gauges: [ClaudeLimitGauge] = []
        if let fiveHour {
            gauges.append(gauge("5h", window: fiveHour, now: now, calendar: calendar))
        }
        if let weekly {
            gauges.append(gauge("Weekly", window: weekly, now: now, calendar: calendar))
        }
        if let weeklyOpus {
            gauges.append(gauge("Opus wk", window: weeklyOpus, now: now, calendar: calendar))
        }
        if let weeklySonnet {
            gauges.append(gauge("Sonnet wk", window: weeklySonnet, now: now, calendar: calendar))
        }
        if let extraUsage {
            gauges.append(ClaudeLimitGauge(
                title: "Extra",
                percent: extraUsage.percentUsed,
                detail: extraUsage.amountDetail
            ))
        }
        return gauges
    }

    private static func gauge(
        _ title: String,
        window: ClaudeLimitWindow,
        now: Date,
        calendar: Calendar
    ) -> ClaudeLimitGauge {
        ClaudeLimitGauge(
            title: title,
            percent: window.percentUsed,
            detail: window.resetsDetail(now: now, calendar: calendar)
        )
    }
}

/// Claude Code panel header: estimated hero, sparkline, plan-limit rings, then the
/// stats grid and the token line.
struct ClaudeCodeHeader<WindowChrome: View, Trailing: View>: View {
    let hero: String
    let isLoading: Bool
    let burnText: String?
    let burnTint: Color
    let sparklineCostCents: [Double]
    let window: UsageTimeWindow
    let tokenLine: String
    var showsPlanLimits: Bool = false
    var fiveHour: ClaudeLimitWindow?
    var weekly: ClaudeLimitWindow?
    var weeklyOpus: ClaudeLimitWindow?
    var weeklySonnet: ClaudeLimitWindow?
    var extraUsage: ClaudeExtraUsage?
    /// Estimated list-price cents since the billing cycle started. Nil until indexed.
    var cycleSpendCents: Double? = nil
    var limitsMessage: String?
    var onEnablePlanLimits: (() -> Void)? = nil
    var stats: [PanelStat] = []
    let unpricedCaption: String?
    let statusCaption: String?
    let statusIsWarning: Bool
    @ViewBuilder var windowChrome: () -> WindowChrome
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .center, spacing: 8) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(hero)
                            .font(.system(size: 34, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                            .lineLimit(1)
                            .minimumScaleFactor(0.65)
                            .contentTransition(reduceMotion ? .identity : .numericText())
                            .animation(reduceMotion ? nil : .snappy, value: hero)
                            .accessibilityElement(children: .ignore)
                            .accessibilityLabel("Estimated window spend \(hero)")
                            .help(PanelSourceResolver.estimatedHelp)

                        Color.clear
                            .frame(width: 16, height: 16)
                            .overlay {
                                if isLoading {
                                    ProgressView()
                                        .controlSize(.small)
                                }
                            }
                            .accessibilityHidden(!isLoading)

                        if let burnText {
                            Text(burnText)
                                .font(.subheadline.weight(.semibold).monospacedDigit())
                                .lineLimit(1)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 5)
                                .glassEffect(.regular.tint(burnTint))
                                .clipShape(Capsule())
                                .help(PanelSourceResolver.estimatedHelp)
                        }
                    }

                    Text(PanelSourceResolver.estimatedCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .layoutPriority(1)

                Spacer(minLength: 4)

                trailing()
                    .layoutPriority(0)
            }
            .fixedSize(horizontal: false, vertical: true)

            windowChrome()
                .fixedSize(horizontal: false, vertical: true)

            SparklineView(
                sparklineCostCents: sparklineCostCents,
                window: window,
                now: Date()
            )
            .fixedSize(horizontal: false, vertical: true)

            VStack(alignment: .leading, spacing: 4) {
                planLimitRings
                    .fixedSize(horizontal: false, vertical: true)

                cycleSpend
                    .fixedSize(horizontal: false, vertical: true)

                if !stats.isEmpty {
                    PanelStatsGrid(stats: stats)
                        .layoutPriority(0)
                }

                Text(tokenLine)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                    .fixedSize(horizontal: false, vertical: true)

                if let unpricedCaption {
                    Text(unpricedCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                        .truncationMode(.tail)
                        .help(unpricedCaption)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let statusCaption {
                Text(statusCaption)
                    .font(.caption)
                    .foregroundStyle(statusIsWarning ? Color.orange : Color.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static var ringSpacing: CGFloat { 12 }
    private static var noteWidth: CGFloat { 150 }
    private static var estimatedTint: Color { .accentColor }
    private static var extraTint: Color { .orange }

    /// Extra usage is Anthropic's billed on-demand amount. It is shown beside the
    /// estimate and is not added to it.
    private var extraSpendDollars: Double? {
        guard showsPlanLimits, limitsMessage == nil else { return nil }
        return extraUsage?.usedDollars
    }

    private var cycleSpend: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text("Spend this cycle")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer(minLength: 8)
                Text(cycleSpendCents.map { MoneyFormat.estimated($0 / 100) } ?? "—")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
            }

            cycleSpendBar

            HStack(spacing: 14) {
                cycleLegend(
                    "Estimated",
                    text: cycleSpendCents.map { MoneyFormat.estimated($0 / 100) } ?? "—",
                    tint: Self.estimatedTint,
                    loaded: cycleSpendCents != nil
                )
                if let extraSpendDollars {
                    cycleLegend(
                        "Extra",
                        text: MoneyFormat.dollars(extraSpendDollars),
                        tint: Self.extraTint,
                        loaded: true
                    )
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(cycleSpendAccessibility)
        .help("Estimated list-price spend since this billing cycle started. Extra is on-demand usage Anthropic has billed this month, and is not included in the total.")
    }

    private var cycleSpendBar: some View {
        Capsule()
            .fill((cycleSpendCents ?? 0) > 0 ? Self.estimatedTint : Color.secondary.opacity(0.25))
            .frame(height: 10)
    }

    private func cycleLegend(_ title: String, text: String, tint: Color, loaded: Bool) -> some View {
        HStack(spacing: 5) {
            Circle()
                .fill(loaded ? tint : Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            Text(text)
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .font(.caption)
        .lineLimit(1)
    }

    private var cycleSpendAccessibility: String {
        guard let cycleSpendCents else { return "Spend this cycle, not loaded" }
        let estimated = MoneyFormat.estimated(cycleSpendCents / 100)
        guard let extraSpendDollars else { return "Spend this cycle \(estimated)" }
        return "Spend this cycle \(estimated). Extra \(MoneyFormat.dollars(extraSpendDollars))"
    }

    /// Placeholder `5h` / `Weekly` rings stand in until limits load, and while
    /// plan limits are off or unavailable, so the header always has its gauges.
    private var shownGauges: [ClaudeLimitGauge] {
        let placeholders = [
            ClaudeLimitGauge(title: "5h", percent: nil, detail: nil),
            ClaudeLimitGauge(title: "Weekly", percent: nil, detail: nil)
        ]
        guard showsPlanLimits, limitsMessage == nil else { return placeholders }
        let gauges = ClaudeLimitGauges.make(
            fiveHour: fiveHour,
            weekly: weekly,
            weeklyOpus: weeklyOpus,
            weeklySonnet: weeklySonnet,
            extraUsage: extraUsage
        )
        return gauges.isEmpty ? placeholders : gauges
    }

    private var planLimitRings: some View {
        let gauges = shownGauges
        let showsEnable = !showsPlanLimits && onEnablePlanLimits != nil
        let showsUnavailable = showsPlanLimits && limitsMessage != nil
        let diameter = PercentGauge.fittedDiameter(
            count: gauges.count,
            spacing: Self.ringSpacing,
            reserving: showsEnable || showsUnavailable ? Self.noteWidth : 0
        )
        return VStack(alignment: .leading, spacing: 4) {
            Text("Plan limits")
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)

            GaugeWrapLayout(spacing: Self.ringSpacing) {
                ForEach(gauges, id: \.title) { gauge in
                    PercentGauge(
                        title: gauge.title,
                        percent: gauge.percent,
                        detail: gauge.detail,
                        diameter: diameter
                    )
                }

                if showsEnable, let onEnablePlanLimits {
                    VStack(alignment: .leading, spacing: 4) {
                        Button("Show plan limits", action: onEnablePlanLimits)
                            .controlSize(.small)
                        Text("Reads your Claude Code login from Keychain. macOS may ask once.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(width: Self.noteWidth, height: diameter, alignment: .leading)
                } else if showsUnavailable {
                    Text(limitsMessage ?? ClaudeLimitsClient.unavailable)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(width: Self.noteWidth, height: diameter, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity)
        }
    }
}

/// Keeps each gauge at its own size, spreads each row so the gaps between
/// gauges and at both edges are equal (at least `spacing`), and wraps onto a
/// second row when the panel is too narrow for one row.
struct GaugeWrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let packed = rows(fitting: proposal.width ?? .greatestFiniteMagnitude, subviews: subviews)
        let natural = packed.map { $0.width + spacing * 2 }.max() ?? 0
        let width = proposal.width.map { $0.isFinite ? $0 : natural } ?? natural
        let gaps = spacing * CGFloat(max(packed.count - 1, 0))
        let height = packed.reduce(CGFloat(0)) { $0 + $1.height } + gaps
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let packed = rows(fitting: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in packed {
            let itemsWidth = row.items.reduce(CGFloat(0)) { $0 + $1.size.width }
            let gap = max(spacing, (bounds.width - itemsWidth) / CGFloat(row.items.count + 1))
            var x = bounds.minX + gap
            for item in row.items {
                item.view.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + gap
            }
            y += row.height + spacing
        }
    }

    private struct Placed {
        var view: LayoutSubview
        var size: CGSize
    }

    private struct Row {
        var items: [Placed]
        var width: CGFloat
        var height: CGFloat
    }

    private func rows(fitting maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var result: [Row] = []
        var items: [Placed] = []
        var width: CGFloat = 0
        var height: CGFloat = 0

        func flush() {
            guard !items.isEmpty else { return }
            result.append(Row(items: items, width: width, height: height))
            items = []
            width = 0
            height = 0
        }

        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            let needed = (items.isEmpty ? size.width : width + spacing + size.width) + spacing * 2
            if !items.isEmpty, needed > maxWidth {
                flush()
            }
            items.append(Placed(view: view, size: size))
            width = items.count == 1 ? size.width : width + spacing + size.width
            height = max(height, size.height)
        }
        flush()
        return result
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

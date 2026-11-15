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
    var limitsUnavailable: Bool = false
    var stats: [PanelStat] = []
    let unpricedCaption: String?
    let statusCaption: String?
    let statusIsWarning: Bool
    @ViewBuilder var windowChrome: () -> WindowChrome
    @ViewBuilder var trailing: () -> Trailing

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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

            windowChrome()

            SparklineView(
                sparklineCostCents: sparklineCostCents,
                window: window,
                now: Date()
            )

            VStack(alignment: .leading, spacing: 4) {
                if showsPlanLimits {
                    if limitsUnavailable {
                        Text(ClaudeLimitsClient.unavailable)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        let gauges = ClaudeLimitGauges.make(
                            fiveHour: fiveHour,
                            weekly: weekly,
                            weeklyOpus: weeklyOpus,
                            weeklySonnet: weeklySonnet,
                            extraUsage: extraUsage
                        )
                        if !gauges.isEmpty {
                            GaugeWrapLayout(spacing: 16) {
                                ForEach(gauges, id: \.title) { gauge in
                                    PercentGauge(
                                        title: gauge.title,
                                        percent: gauge.percent,
                                        detail: gauge.detail,
                                        diameter: 88
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                if !stats.isEmpty {
                    PanelStatsGrid(stats: stats)
                }

                Text(tokenLine)
                    .font(.subheadline.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                if let unpricedCaption {
                    Text(unpricedCaption)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let statusCaption {
                Text(statusCaption)
                    .font(.caption)
                    .foregroundStyle(statusIsWarning ? Color.orange : Color.secondary)
            }
        }
    }
}

/// Keeps each gauge at its own size and wraps onto a second row when the
/// panel is too narrow for one row.
private struct GaugeWrapLayout: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let packed = rows(fitting: proposal.width ?? .greatestFiniteMagnitude, subviews: subviews)
        let width = packed.map(\.width).max() ?? 0
        let gaps = spacing * CGFloat(max(packed.count - 1, 0))
        let height = packed.reduce(CGFloat(0)) { $0 + $1.height } + gaps
        return CGSize(width: width, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let packed = rows(fitting: bounds.width, subviews: subviews)
        var y = bounds.minY
        for row in packed {
            var x = bounds.minX
            for item in row.items {
                item.view.place(
                    at: CGPoint(x: x, y: y),
                    anchor: .topLeading,
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
                x += item.size.width + spacing
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
            let needed = items.isEmpty ? size.width : width + spacing + size.width
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

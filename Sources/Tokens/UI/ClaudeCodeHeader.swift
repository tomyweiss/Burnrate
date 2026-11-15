import SwiftUI
import TokensCore

/// Claude Code panel header: estimated hero, sparkline, and the token line that
/// plan-limit gauges replace when those limits are enabled.
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
    var limitsUnavailable: Bool = false
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
                        HStack(alignment: .top, spacing: 16) {
                            PercentGauge(
                                title: "5h",
                                percent: fiveHour?.percentUsed,
                                detail: fiveHour?.resetsDetail(),
                                diameter: 72
                            )
                            PercentGauge(
                                title: "Weekly",
                                percent: weekly?.percentUsed,
                                detail: weekly?.resetsDetail(),
                                diameter: 72
                            )
                        }
                    }
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

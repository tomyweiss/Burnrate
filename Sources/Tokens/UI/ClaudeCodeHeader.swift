import SwiftUI

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

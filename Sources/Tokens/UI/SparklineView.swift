import SwiftUI

struct SparklineView: View {
    let sparklineCostCents: [Double]
    let window: UsageTimeWindow
    let now: Date

    @State private var hoveredIndex: Int?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var currentBucket: Int {
        window.currentBucketIndex(now: now)
    }

    private var maxCents: Double {
        max(sparklineCostCents.max() ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let count = sparklineCostCents.count
                let spacing: CGFloat = 2
                let barWidth = max(
                    (geo.size.width - spacing * CGFloat(max(count - 1, 0))) / CGFloat(max(count, 1)),
                    1
                )

                ZStack(alignment: .bottomLeading) {
                    HStack(alignment: .bottom, spacing: spacing) {
                        ForEach(0..<count, id: \.self) { index in
                            let value = index < sparklineCostCents.count ? sparklineCostCents[index] : 0
                            let isDimmed = window.shouldDimBucket(index, now: now)
                            let height = max(2, CGFloat(value / maxCents) * geo.size.height)
                            VStack {
                                Spacer(minLength: 0)
                                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                                    .fill(barColor(for: index))
                                    .frame(width: barWidth, height: isDimmed ? 2 : height)
                                    .opacity(isDimmed ? 0.25 : 1)
                            }
                            .frame(width: barWidth, height: geo.size.height, alignment: .bottom)
                        }
                    }
                    .frame(maxHeight: .infinity, alignment: .bottom)

                    if let hoveredIndex {
                        tooltip(for: hoveredIndex)
                            .position(
                                x: barCenterX(
                                    index: hoveredIndex,
                                    barWidth: barWidth,
                                    spacing: spacing
                                ),
                                y: 10
                            )
                            .allowsHitTesting(false)
                            .transition(reduceMotion ? .identity : .opacity)
                    }

                    Rectangle()
                        .fill(Color.clear)
                        .contentShape(Rectangle())
                        .onContinuousHover { phase in
                            switch phase {
                            case .active(let location):
                                hoveredIndex = barIndex(
                                    at: location,
                                    barWidth: barWidth,
                                    spacing: spacing,
                                    count: count
                                )
                            case .ended:
                                hoveredIndex = nil
                            }
                        }
                }
            }
            .frame(height: 36)
            .animation(reduceMotion ? nil : .snappy, value: hoveredIndex)

            HStack {
                Text(window.sparklineStartLabel(now: now))
                Spacer()
                Text(window.sparklineEndLabel)
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func barColor(for index: Int) -> Color {
        if index == currentBucket {
            return Color.accentColor
        }
        return Color.secondary.opacity(0.5)
    }

    private func barIndex(
        at location: CGPoint,
        barWidth: CGFloat,
        spacing: CGFloat,
        count: Int
    ) -> Int? {
        guard count > 0, location.x >= 0 else { return nil }
        let step = barWidth + spacing
        let index = Int(location.x / step)
        guard (0..<count).contains(index) else { return nil }
        let xInStep = location.x - CGFloat(index) * step
        guard xInStep <= barWidth else { return nil }
        return index
    }

    private func barCenterX(index: Int, barWidth: CGFloat, spacing: CGFloat) -> CGFloat {
        let step = barWidth + spacing
        return CGFloat(index) * step + barWidth / 2
    }

    private func tooltip(for index: Int) -> some View {
        let value = index < sparklineCostCents.count ? sparklineCostCents[index] : 0
        return Text(barTooltip(index: index, valueCents: value))
            .font(.caption2.weight(.medium).monospacedDigit())
            .foregroundStyle(.primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 4)
            .background(.regularMaterial, in: Capsule())
            .overlay {
                Capsule()
                    .strokeBorder(.quaternary.opacity(0.8), lineWidth: 0.5)
            }
            .fixedSize()
    }

    private func barTooltip(index: Int, valueCents: Double) -> String {
        let timeLabel = window.sparklineBucketLabel(index: index, now: now)
        guard valueCents > 0 else { return timeLabel }
        return "\(timeLabel) · \(MoneyFormat.dollarsFromCents(valueCents))"
    }
}

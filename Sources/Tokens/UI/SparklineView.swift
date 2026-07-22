import SwiftUI

struct SparklineView: View {
    let sparklineCostCents: [Double]
    let window: UsageTimeWindow
    let now: Date

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
                let barWidth = max((geo.size.width - spacing * CGFloat(max(count - 1, 0))) / CGFloat(max(count, 1)), 1)

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<count, id: \.self) { index in
                        let value = index < sparklineCostCents.count ? sparklineCostCents[index] : 0
                        let isDimmed = window.shouldDimBucket(index, now: now)
                        let height = max(2, CGFloat(value / maxCents) * geo.size.height)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(barColor(for: index))
                            .frame(width: barWidth, height: isDimmed ? 2 : height)
                            .opacity(isDimmed ? 0.25 : 1)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 36)

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
}

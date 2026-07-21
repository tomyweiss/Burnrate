import SwiftUI

struct SparklineView: View {
    let hourlyCostCents: [Double]
    let now: Date

    private var currentHour: Int {
        Calendar.current.component(.hour, from: now)
    }

    private var maxCents: Double {
        max(hourlyCostCents.max() ?? 0, 1)
    }

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let count = 24
                let spacing: CGFloat = 2
                let barWidth = max((geo.size.width - spacing * CGFloat(count - 1)) / CGFloat(count), 1)

                HStack(alignment: .bottom, spacing: spacing) {
                    ForEach(0..<count, id: \.self) { hour in
                        let value = hour < hourlyCostCents.count ? hourlyCostCents[hour] : 0
                        let height = max(2, CGFloat(value / maxCents) * geo.size.height)
                        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                            .fill(barColor(for: hour))
                            .frame(width: barWidth, height: hour <= currentHour ? height : 2)
                            .opacity(hour <= currentHour ? 1 : 0.25)
                    }
                }
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .frame(height: 36)

            HStack {
                Text("12am")
                Spacer()
                Text("now")
            }
            .font(.caption2)
            .foregroundStyle(.tertiary)
        }
    }

    private func barColor(for hour: Int) -> Color {
        if hour == currentHour {
            return Color.accentColor
        }
        return Color.secondary.opacity(0.5)
    }
}

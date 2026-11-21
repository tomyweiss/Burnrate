import SwiftUI

/// Building blocks shared by the Cursor and Claude Code halves of the panel
/// header, so the two sources keep the same type, spacing, and colors.

/// Rounded spend figure on a source card.
struct PanelHeroText: View {
    let text: String
    let accessibilityLabel: String

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Text(text)
            .font(.system(size: 26, weight: .semibold, design: .rounded))
            .monospacedDigit()
            .lineLimit(1)
            .minimumScaleFactor(0.65)
            .contentTransition(reduceMotion ? .identity : .numericText())
            .animation(reduceMotion ? nil : .snappy, value: text)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(accessibilityLabel)
    }
}

/// Fixed slot on a source card so the title row doesn't shift when loading starts.
struct PanelLoadingSlot: View {
    let isLoading: Bool

    var body: some View {
        Color.clear
            .frame(width: 14, height: 14)
            .overlay {
                if isLoading {
                    ProgressView()
                        .controlSize(.mini)
                }
            }
            .accessibilityHidden(!isLoading)
    }
}

/// Spend in the spike window, tinted by burn level.
struct BurnPill: View {
    let text: String
    let tint: Color
    let help: String

    var body: some View {
        Text(text)
            .font(.caption.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .glassEffect(.regular.tint(tint))
            .clipShape(Capsule())
            .help(help)
    }
}

/// `48.2M tokens · 91% cache read` under the stats grid.
struct PanelTokenLine: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.subheadline.monospacedDigit())
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// Capsule track filled left to right by colored segments.
struct SpendBar: View {
    struct Segment {
        var fraction: Double
        var tint: Color
    }

    let segments: [Segment]

    var body: some View {
        GeometryReader { proxy in
            let widths = segments.map { proxy.size.width * max(0, $0.fraction) }
            let shown = zip(segments, widths).filter { $0.1 > 0 }

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.secondary.opacity(0.25))
                HStack(spacing: shown.count > 1 ? 2 : 0) {
                    ForEach(Array(shown.enumerated()), id: \.offset) { _, item in
                        Rectangle().fill(item.0.tint).frame(width: item.1)
                    }
                }
                .clipShape(Capsule())
            }
        }
        .frame(height: 10)
    }
}

/// Colored dot, title, and an optional amount under a spend bar.
struct SpendLegendItem: View {
    let title: String
    var value: String? = nil
    let tint: Color
    let loaded: Bool

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(loaded ? tint : Color.secondary.opacity(0.45))
                .frame(width: 7, height: 7)
            Text(title)
                .foregroundStyle(.secondary)
            if let value {
                Text(value)
                    .fontWeight(.medium)
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .lineLimit(1)
    }
}

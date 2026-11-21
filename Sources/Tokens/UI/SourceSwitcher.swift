import SwiftUI

private struct CostStyleKey: EnvironmentKey {
    static let defaultValue = CostStyle.billed
}

extension EnvironmentValues {
    /// Billed Cursor dollars, or estimated Claude Code dollars. Set from the active panel source.
    var costStyle: CostStyle {
        get { self[CostStyleKey.self] }
        set { self[CostStyleKey.self] = newValue }
    }
}

/// What one source shows on its card: window spend, the spike-window pill, and the sparkline.
struct SourceCard: Identifiable {
    let source: UsageSource
    let figure: String
    let isLoading: Bool
    /// Nil when nothing was spent in the spike window.
    let burnText: String?
    let burnTint: Color
    let burnHelp: String
    let sparklineCostCents: [Double]
    let window: UsageTimeWindow

    var id: UsageSource { source }

    var accessibilityLabel: String {
        switch source {
        case .cursor: "Cursor, window spend \(figure)"
        case .claudeCode: "Claude Code, estimated window spend \(figure.replacingOccurrences(of: "~", with: ""))"
        }
    }
}

/// One card per visible source. With both sources the cards switch the panel
/// between them, and each keeps showing its own spend. A single source gets
/// one full-width card that is not a button.
struct SourceSwitcher: View {
    @Binding var selection: UsageSource
    let cards: [SourceCard]

    var body: some View {
        HStack(spacing: 8) {
            ForEach(cards) { card in
                if cards.count > 1 {
                    Button {
                        selection = card.source
                    } label: {
                        cardBody(card, isSelected: selection == card.source)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(card.accessibilityLabel)
                    .accessibilityAddTraits(selection == card.source ? .isSelected : [])
                } else {
                    cardBody(card, isSelected: false)
                        .accessibilityElement(children: .ignore)
                        .accessibilityLabel(card.accessibilityLabel)
                }
            }
        }
    }

    private func cardBody(_ card: SourceCard, isSelected: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: 12, style: .continuous)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(PanelSourceResolver.cardTitle(for: card.source))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .lineLimit(1)
                Spacer(minLength: 0)
                PanelLoadingSlot(isLoading: card.isLoading)
            }

            HStack(alignment: .center, spacing: 8) {
                PanelHeroText(text: card.figure, accessibilityLabel: card.accessibilityLabel)
                if let burnText = card.burnText {
                    BurnPill(text: burnText, tint: card.burnTint, help: card.burnHelp)
                }
                Spacer(minLength: 0)
            }

            SparklineView(
                sparklineCostCents: card.sparklineCostCents,
                window: card.window,
                now: Date(),
                chartHeight: 20,
                showsAxisLabels: false
            )
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(isSelected ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.05)))
        .overlay {
            if isSelected {
                shape.strokeBorder(Color.accentColor, lineWidth: 1.5)
            }
        }
        .contentShape(shape)
        .environment(\.costStyle, card.source.costStyle)
        .help(card.source == .claudeCode ? PanelSourceResolver.estimatedHelp : "")
    }
}

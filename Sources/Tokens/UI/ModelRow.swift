import SwiftUI

struct ShareBar: View {
    let fraction: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.accentColor.opacity(0.25))
                Capsule()
                    .fill(Color.accentColor.opacity(0.8))
                    .frame(width: max(4, geo.size.width * CGFloat(min(max(fraction, 0), 1))))
            }
        }
        .frame(height: 4)
    }
}

struct ModelRowView: View {
    let model: ModelUsage
    let windowCostCents: Double
    let isExpanded: Bool
    let reduceMotion: Bool
    var showLocationSubtitle: Bool = false
    var hideArchivedSessions: Bool = false
    let onToggle: () -> Void
    var onOpenSession: ((String) -> Void)? = nil

    @State private var hovering = false

    private var share: Double {
        guard windowCostCents > 0 else { return 0 }
        return model.costCents / windowCostCents
    }

    private var visibleSessions: [SessionUsage] {
        guard hideArchivedSessions else { return model.sessions }
        return model.sessions.filter { !$0.isArchived }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: onToggle) {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(model.model)
                                .font(.callout.weight(.medium))
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Spacer(minLength: 8)
                            Text(MoneyFormat.dollars(model.costDollars))
                                .font(.callout.monospacedDigit().weight(.semibold))
                                .contentTransition(.numericText())
                        }

                        ShareBar(fraction: share)

                        Text(
                            "\(model.sessions.count) sessions · \(model.eventCount) events · \(TokenFormat.compact(model.totalTokens)) tok"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }

                    Image(systemName: "chevron.right")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.tertiary)
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                        .padding(.top, 4)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 8) {
                    Text(tokenDetail)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 4)

                    ForEach(visibleSessions) { session in
                        SessionRowView(
                            session: session,
                            windowCostCents: windowCostCents,
                            showModelChips: false,
                            showShareBar: false,
                            showLocationSubtitle: showLocationSubtitle,
                            onSelect: onOpenSession.map { open in
                                { open(session.conversationId) }
                            }
                        )
                    }
                }
                .padding(.leading, 4)
                .padding(.bottom, 8)
            }
        }
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : .snappy, value: isExpanded)
    }

    private var tokenDetail: String {
        var parts = [
            "in \(TokenFormat.compact(model.inputTokens))",
            "out \(TokenFormat.compact(model.outputTokens))"
        ]
        if model.cacheReadTokens > 0 {
            parts.append("cache read \(TokenFormat.compact(model.cacheReadTokens))")
        }
        if model.cacheWriteTokens > 0 {
            parts.append("cache write \(TokenFormat.compact(model.cacheWriteTokens))")
        }
        return parts.joined(separator: " · ")
    }
}

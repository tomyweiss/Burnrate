import SwiftUI

struct SessionRowView: View {
    let session: SessionUsage
    let todayCostCents: Double
    var showModelChips: Bool = true
    var showShareBar: Bool = true

    @State private var hovering = false

    private var share: Double {
        guard todayCostCents > 0 else { return 0 }
        return session.costCents / todayCostCents
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(session.displayName)
                    .font(.callout.weight(.medium))
                    .lineLimit(2)
                Spacer(minLength: 8)
                Text(MoneyFormat.dollars(session.costDollars))
                    .font(.callout.monospacedDigit().weight(.semibold))
                    .contentTransition(.numericText())
            }

            if showShareBar {
                ShareBar(fraction: share)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(hovering ? Color.primary.opacity(0.06) : Color.clear)
        )
        .onHover { hovering = $0 }
        .help("Conversation \(session.conversationId)")
    }

    private var subtitle: String {
        var parts: [String] = []
        if let workspace = session.workspaceName, !workspace.isEmpty {
            parts.append(workspace)
        }
        if showModelChips, let top = session.models.first {
            if session.models.count > 1 {
                parts.append("\(top) +\(session.models.count - 1)")
            } else {
                parts.append(top)
            }
        }
        if session.lastTimestampMs > 0 {
            parts.append(RelativeTimeFormat.string(fromTimestampMs: session.lastTimestampMs))
        }
        return parts.joined(separator: " · ")
    }
}

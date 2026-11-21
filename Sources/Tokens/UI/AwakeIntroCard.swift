import SwiftUI

/// One-time note that introduces the keep-awake button.
struct AwakeIntroCard: View {
    var onDismiss: () -> Void

    static let title = "New: Keep awake"
    static let message = "The cup in the top row keeps this Mac awake with the lid closed for 30, 45, or 90 minutes, so agents keep running in your bag. Sleep returns when the timer ends, or if the Mac gets hot or the battery runs low."

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: AwakeButtonState.idle.symbolName)
                    .foregroundStyle(AwakeButtonPalette.idle(colorScheme))
                    .accessibilityHidden(true)
                Text(Self.title)
                    .font(.callout.weight(.medium))
            }
            Text(Self.message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Button("Got it", action: onDismiss)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .accessibilityLabel("Dismiss keep awake introduction")
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
        .accessibilityElement(children: .contain)
    }

    /// Shown until the user dismisses the card or starts a trip. The Claude Code
    /// hint goes first, so the header never stacks both notes.
    nonisolated static func shouldShow(dismissed: Bool, claudeCodeHintShowing: Bool) -> Bool {
        !dismissed && !claudeCodeHintShowing
    }
}

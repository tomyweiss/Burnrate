import SwiftUI

/// One-time note that Claude Code can appear in the menu bar.
struct ClaudeCodeHint: View {
    var onShowInMenuBar: () -> Void
    var onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Burnrate now tracks Claude Code")
                .font(.callout.weight(.medium))
            HStack(spacing: 8) {
                Button("Show in menu bar", action: onShowInMenuBar)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    /// Shown once Cursor is signed in, Claude Code is installed and enabled, and
    /// its spend figure is still off. Claude-only installs already default that figure on.
    static func shouldShow(
        claudeInstalled: Bool,
        claudeEnabled: Bool,
        cursorAvailable: Bool,
        showsClaudeSpend: Bool,
        hintDismissed: Bool
    ) -> Bool {
        claudeInstalled && claudeEnabled && cursorAvailable && !showsClaudeSpend && !hintDismissed
    }
}

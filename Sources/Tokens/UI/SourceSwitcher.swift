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

/// Segmented Cursor / Claude Code control. Shown only when both sources are visible.
struct SourceSwitcher: View {
    @Binding var selection: UsageSource
    let cursorTitle: String
    let claudeTitle: String

    var body: some View {
        PillPicker(
            selection: $selection,
            options: [
                PillPicker.Option(value: .cursor, title: cursorTitle),
                PillPicker.Option(value: .claudeCode, title: claudeTitle),
            ],
            size: .controlBar,
            fillsWidth: true
        )
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

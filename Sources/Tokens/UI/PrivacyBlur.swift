import SwiftUI

private struct BlurSensitiveContentKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// When true, session titles and prompt text are visually blurred for screen sharing.
    var blurSensitiveContent: Bool {
        get { self[BlurSensitiveContentKey.self] }
        set { self[BlurSensitiveContentKey.self] = newValue }
    }
}

extension View {
    /// Soft-blurs text/content so it stays unreadable in recordings while preserving layout.
    func privacyBlurred(_ enabled: Bool = true, radius: CGFloat = 7) -> some View {
        self
            .blur(radius: enabled ? radius : 0)
            .accessibilityHidden(enabled)
    }
}

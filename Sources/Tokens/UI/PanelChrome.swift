import SwiftUI

enum PanelChrome {
    static let cornerRadius: CGFloat = 20
}

/// MenuBarExtra `.window` panels are fully transparent at the AppKit layer so
/// floating glass controls can composite correctly. Unlike `NSPopover`, the
/// system does not paint Liquid Glass behind the whole surface — add a material
/// shell here so content stays readable on busy wallpapers (macOS 26+).
private struct PanelSurfaceBackground: ViewModifier {
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: PanelChrome.cornerRadius, style: .continuous)
        content
            .background {
                if reduceTransparency {
                    shape.fill(Color(nsColor: .windowBackgroundColor))
                } else {
                    shape.fill(.thickMaterial)
                }
            }
            .overlay {
                shape.strokeBorder(.quaternary.opacity(0.55), lineWidth: 0.5)
            }
    }
}

extension View {
    func panelSurfaceBackground() -> some View {
        modifier(PanelSurfaceBackground())
    }
}

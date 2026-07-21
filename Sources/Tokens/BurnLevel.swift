import AppKit
import SwiftUI

enum BurnLevel: Equatable, Sendable {
    /// Recent spend &lt; 25% of threshold.
    case calm
    /// Recent spend ≥ 25% of threshold.
    case elevated
    /// Recent spend ≥ threshold (alert level).
    case critical
    case error

    static func level(recentDollars: Double, thresholdDollars: Double, hasError: Bool) -> BurnLevel {
        if hasError { return .error }
        let threshold = max(thresholdDollars, 0.01)
        let ratio = recentDollars / threshold
        if ratio >= 1 { return .critical }
        if ratio >= 0.25 { return .elevated }
        return .calm
    }

    var symbolName: String {
        switch self {
        case .calm: "flame"
        case .elevated, .critical: "flame.fill"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var swiftUIColor: Color {
        switch self {
        case .calm: .secondary
        case .elevated: .orange
        case .critical: .red
        case .error: .yellow
        }
    }

    var nsColor: NSColor {
        switch self {
        case .calm: .secondaryLabelColor
        case .elevated: .systemOrange
        case .critical: .systemRed
        case .error: .systemYellow
        }
    }

    /// Colored menu-bar image (`isTemplate = false` so tint is preserved).
    func menuBarImage(pointSize: CGFloat = 15) -> NSImage {
        let base = NSImage(systemSymbolName: symbolName, accessibilityDescription: "Burnrate")
            ?? NSImage(size: NSSize(width: pointSize, height: pointSize))
        let sizeConfig = NSImage.SymbolConfiguration(pointSize: pointSize, weight: .semibold)
        let colorConfig = NSImage.SymbolConfiguration(paletteColors: [nsColor])
        let configured = base
            .withSymbolConfiguration(sizeConfig)?
            .withSymbolConfiguration(colorConfig)
            ?? base
        let copy = configured.copy() as? NSImage ?? configured
        copy.isTemplate = false
        return copy
    }
}

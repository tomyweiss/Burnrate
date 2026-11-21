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

    /// Menu-bar severity. A warning triangle outranks a filled flame.
    var severity: Int {
        switch self {
        case .calm: 0
        case .elevated: 1
        case .critical: 2
        case .error: 3
        }
    }

    static func moreSevere(_ lhs: BurnLevel, _ rhs: BurnLevel) -> BurnLevel {
        lhs.severity >= rhs.severity ? lhs : rhs
    }

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

    /// Menu-bar flame for this level. Burnrate-dev adds the gray dot.
    static func menuBarImage(for level: BurnLevel) -> NSImage {
        menuBarImage(for: level, markingAwake: false)
    }

    static func menuBarImage(for level: BurnLevel, markingAwake awake: Bool) -> NSImage {
        let base = AppIdentity.isDevBuild ? level.menuBarImageWithDevDot() : level.menuBarImage()
        guard awake else { return base }
        return base.withTrailingSymbol("bolt.fill")
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

    /// Flame plus a small gray dot so -dev is distinct without replacing the $ amount.
    func menuBarImageWithDevDot(pointSize: CGFloat = 15) -> NSImage {
        let flame = menuBarImage(pointSize: pointSize)
        let gap: CGFloat = 3
        let dotSize: CGFloat = 5
        let width = flame.size.width + gap + dotSize
        let height = max(flame.size.height, dotSize)
        let image = NSImage(size: NSSize(width: width, height: height))
        image.lockFocus()
        defer { image.unlockFocus() }

        let flameY = (height - flame.size.height) / 2
        flame.draw(
            in: NSRect(x: 0, y: flameY, width: flame.size.width, height: flame.size.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )

        let dotRect = NSRect(
            x: flame.size.width + gap,
            y: (height - dotSize) / 2,
            width: dotSize,
            height: dotSize
        )
        NSColor.secondaryLabelColor.setFill()
        NSBezierPath(ovalIn: dotRect).fill()

        image.isTemplate = false
        return image
    }
}

private extension NSImage {
    func withTrailingSymbol(_ name: String) -> NSImage {
        let gap: CGFloat = 2
        let markSize = NSSize(width: size.height * 0.55, height: size.height * 0.55)
        let width = size.width + gap + markSize.width
        let image = NSImage(size: NSSize(width: width, height: size.height))
        image.lockFocus()
        defer { image.unlockFocus() }
        draw(
            in: NSRect(x: 0, y: 0, width: size.width, height: size.height),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        let mark = NSImage(systemSymbolName: name, accessibilityDescription: "Awake")?
            .withSymbolConfiguration(NSImage.SymbolConfiguration(pointSize: markSize.height, weight: .bold))
        mark?.isTemplate = false
        mark?.draw(
            in: NSRect(
                x: size.width + gap,
                y: (size.height - markSize.height) / 2,
                width: markSize.width,
                height: markSize.height
            ),
            from: .zero,
            operation: .sourceOver,
            fraction: 1
        )
        image.isTemplate = false
        return image
    }
}

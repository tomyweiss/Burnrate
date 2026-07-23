import AppKit

/// MenuBarExtra `.window` panels dismiss when controls cause deactivation.
/// Keep ours visible while interacting.
@MainActor
enum MenuBarPanelKeeper {
    static func keepOpen() {
        for window in NSApp.windows where isMenuBarPanel(window) {
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            if let panel = window as? NSPanel {
                panel.hidesOnDeactivate = false
                panel.becomesKeyOnlyIfNeeded = false
            }
            window.makeKeyAndOrderFront(nil)
        }
        NSApp.activate()
        clampPanelsToScreen()
        // With an auto-hiding menu bar the system can shift the panel up again
        // right after the interaction; re-clamp once things settle.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            clampPanelsToScreen()
        }
    }

    /// When the macOS menu bar auto-hides, the system can move the panel up so
    /// its top edge ends up above the visible screen and gets cropped. Push it
    /// back down so the whole panel stays on screen.
    private static func clampPanelsToScreen() {
        for window in NSApp.windows where isMenuBarPanel(window) && window.isVisible {
            guard let screen = window.screen ?? NSScreen.main else { continue }
            let allowedTop = screen.visibleFrame.maxY
            if window.frame.maxY > allowedTop + 0.5 {
                var origin = window.frame.origin
                origin.y = allowedTop - window.frame.height
                window.setFrameOrigin(origin)
            }
        }
    }

    private static func isMenuBarPanel(_ window: NSWindow) -> Bool {
        if window is NSPanel { return true }
        if window.styleMask.contains(.borderless), window.frame.height < 900 {
            return true
        }
        return false
    }
}

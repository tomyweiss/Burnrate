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
    }

    private static func isMenuBarPanel(_ window: NSWindow) -> Bool {
        if window is NSPanel { return true }
        if window.styleMask.contains(.borderless), window.frame.height < 900 {
            return true
        }
        return false
    }
}

import AppKit

/// MenuBarExtra `.window` panels dismiss when controls cause deactivation, and
/// macOS can nudge the window on re-activation (auto-hiding menu bar, status
/// item relayout). Keep the panel visible and pinned where it first appeared.
@MainActor
enum MenuBarPanelKeeper {
    /// Top-left anchor per window number, recorded shortly after the panel
    /// opens (once the system has settled the initial placement).
    private static var anchors: [Int: CGPoint] = [:]
    private static var anchorTask: Task<Void, Never>?
    private static var moveObserver: NSObjectProtocol?
    private static var resizeObserver: NSObjectProtocol?

    /// Call when the panel content appears: drop stale anchors, keep the panel
    /// open, and record a fresh anchor once initial placement settles.
    static func panelDidShow() {
        anchors.removeAll()
        preparePanels()
        for window in panelWindows where window.isVisible {
            // Key the panel once on open so keyboard shortcuts work; skip app
            // activation so we don't yank the user out of a fullscreen space.
            window.makeKeyAndOrderFront(nil)
        }
        anchorTask?.cancel()
        anchorTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(250))
            guard !Task.isCancelled else { return }
            recordAnchors()
        }
    }

    /// Call when the panel closes so the next open re-anchors under the
    /// (possibly moved) status item.
    static func panelDidHide() {
        anchorTask?.cancel()
        anchorTask = nil
        anchors.removeAll()
        for window in panelWindows {
            flushStaleCompositorState(window)
        }
    }

    static func keepOpen() {
        preparePanels()
        for window in panelWindows where window.isVisible {
            // Re-front without activating the app or stealing key from the
            // frontmost fullscreen app — NSApp.activate() was pulling users
            // back to the main desktop on every control click.
            window.orderFront(nil)
            pin(window)
        }
    }

    /// Sparkle update alerts sit behind floating menu bar panels unless we
    /// temporarily hide them before the modal is shown.
    static func hidePanelsForModalAlert() {
        for window in panelWindows where window.isVisible {
            window.orderOut(nil)
        }
    }

    static func restorePanelsAfterModalAlert() {
        for window in panelWindows where anchors[window.windowNumber] != nil {
            window.orderFront(nil)
            pin(window)
        }
    }

    private static func preparePanels() {
        installMoveObserverIfNeeded()
        for window in panelWindows {
            configurePanelWindow(window)
            window.hidesOnDeactivate = false
            window.isReleasedWhenClosed = false
            if let panel = window as? NSPanel {
                panel.hidesOnDeactivate = false
                panel.becomesKeyOnlyIfNeeded = true
            }
        }
    }

    // MARK: - Positioning

    private static var panelWindows: [NSWindow] {
        NSApp.windows.filter { isMenuBarPanel($0) }
    }

    private static func recordAnchors() {
        for window in panelWindows where window.isVisible {
            let topLeft = CGPoint(x: window.frame.minX, y: window.frame.maxY)
            anchors[window.windowNumber] = clampedTopLeft(topLeft, for: window)
            pin(window)
        }
    }

    /// Snap the window back to its anchor. Before an anchor exists, only make
    /// sure the window isn't cropped by the edges of the screen.
    private static func pin(_ window: NSWindow) {
        let current = CGPoint(x: window.frame.minX, y: window.frame.maxY)
        let target = clampedTopLeft(anchors[window.windowNumber] ?? current, for: window)
        if abs(current.x - target.x) > 0.5 || abs(current.y - target.y) > 0.5 {
            window.setFrameTopLeftPoint(target)
        }
    }

    /// Keep the whole panel inside the screen's visible area (below an
    /// auto-hiding menu bar reveal, never above the top edge).
    private static func clampedTopLeft(_ topLeft: CGPoint, for window: NSWindow) -> CGPoint {
        guard let screen = window.screen ?? NSScreen.main else { return topLeft }
        let visible = screen.visibleFrame
        var point = topLeft
        point.x = max(min(point.x, visible.maxX - window.frame.width), visible.minX)
        point.y = min(point.y, visible.maxY)
        return point
    }

    /// The system moves the panel while re-activating; snap it back as soon as
    /// that happens instead of letting it drift click after click. Re-pin on
    /// resize too, so content growth extends the panel downward from its
    /// anchored top edge (e.g. the taller Bench tab).
    private static func installMoveObserverIfNeeded() {
        guard moveObserver == nil else { return }
        let handler: @Sendable (Notification) -> Void = { notification in
            guard let window = notification.object as? NSWindow else { return }
            MainActor.assumeIsolated {
                guard window.isVisible,
                      isMenuBarPanel(window),
                      anchors[window.windowNumber] != nil
                else { return }
                pin(window)
            }
        }
        moveObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didMoveNotification,
            object: nil,
            queue: .main,
            using: handler
        )
        resizeObserver = NotificationCenter.default.addObserver(
            forName: NSWindow.didResizeNotification,
            object: nil,
            queue: .main,
            using: handler
        )
    }

    private static func isMenuBarPanel(_ window: NSWindow) -> Bool {
        if window is NSPanel { return true }
        if window.styleMask.contains(.borderless), window.frame.height < 900 {
            return true
        }
        return false
    }

    /// MenuBarExtra panels must stay transparent so glass controls composite
    /// against the desktop instead of leaving opaque rectangles behind.
    private static func configurePanelWindow(_ window: NSWindow) {
        window.isOpaque = false
        window.backgroundColor = .clear
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        if let panel = window as? NSPanel {
            panel.isFloatingPanel = true
        }
        guard let contentView = window.contentView else { return }
        contentView.wantsLayer = true
        contentView.layer?.backgroundColor = NSColor.clear.cgColor
    }

    /// Liquid Glass layers can outlive a dismissed panel; force the window server
    /// to redraw the panel region before the window goes off-screen.
    private static func flushStaleCompositorState(_ window: NSWindow) {
        guard let contentView = window.contentView else { return }
        contentView.setNeedsDisplay(contentView.bounds)
        contentView.displayIfNeeded()
        window.invalidateShadow()
    }
}

import Foundation

/// Which panel source is visible, and how a missing Cursor login is treated.
enum PanelSourceResolver {
    static let estimatedCaption = "Estimated at API list prices · not your bill"
    static let estimatedHelp = "Estimated from local token counts × Anthropic list prices. Claude Code doesn't record charges. On Pro and Max you pay a flat rate; this is what the same usage would cost on the API."
    static let neitherSourceMessage = "No Cursor session or Claude Code data found. Sign in to Cursor, or run Claude Code once."

    static func visibleSources(
        cursorAvailable: Bool,
        cursorEnabled: Bool,
        claudeInstalled: Bool,
        claudeEnabled: Bool
    ) -> [UsageSource] {
        var sources: [UsageSource] = []
        if cursorAvailable && cursorEnabled {
            sources.append(.cursor)
        }
        if claudeInstalled && claudeEnabled {
            sources.append(.claudeCode)
        }
        return sources
    }

    /// Stored selection when it is still visible; otherwise the first visible source.
    static func activeSource(stored: UsageSource?, visible: [UsageSource]) -> UsageSource? {
        guard !visible.isEmpty else { return nil }
        if let stored, visible.contains(stored) { return stored }
        return visible.first
    }

    /// Source the panel body renders. When Claude Code cannot stand in, a Cursor
    /// login failure still renders the Cursor panel so the existing error stays.
    static func displayedSource(
        stored: UsageSource?,
        cursorAvailable: Bool,
        cursorEnabled: Bool,
        claudeInstalled: Bool,
        claudeEnabled: Bool
    ) -> UsageSource? {
        let visible = visibleSources(
            cursorAvailable: cursorAvailable,
            cursorEnabled: cursorEnabled,
            claudeInstalled: claudeInstalled,
            claudeEnabled: claudeEnabled
        )
        if let active = activeSource(stored: stored, visible: visible) {
            return active
        }
        let claudeCanReplace = claudeInstalled && claudeEnabled
        if cursorEnabled && !claudeCanReplace {
            return .cursor
        }
        return nil
    }

    static let placeholderBilled = "$—.——"
    static let placeholderEstimated = "~$—.——"

    static func segmentTitle(source: UsageSource, windowDollars: Double, isPlaceholder: Bool) -> String {
        let amount = isPlaceholder
            ? (source == .claudeCode ? placeholderEstimated : placeholderBilled)
            : MoneyFormat.string(windowDollars, style: source.costStyle)
        return "\(source.displayName)  \(amount)"
    }

    static func indexingCaption(done: Int, total: Int) -> String {
        "Indexing Claude Code · \(done) of \(total) sessions"
    }

    static func cursorSettingsLabel(signedIn: Bool) -> String {
        signedIn ? "Cursor · Signed in" : "Cursor · Not signed in"
    }

    static func claudeSettingsLabel(installed: Bool, sessionCount: Int) -> String {
        guard installed else { return "Claude Code · Not found" }
        let sessions = sessionCount == 1 ? "1 session" : "\(sessionCount) sessions"
        return "Claude Code · \(sessions) in ~/.claude"
    }

    static func isStale(
        hasCompletedFetch: Bool,
        fetchedAt: Date,
        refreshIntervalSeconds: Double,
        now: Date = Date()
    ) -> Bool {
        guard hasCompletedFetch, fetchedAt != .distantPast else { return false }
        let limit = max(15, refreshIntervalSeconds) * 3
        return now.timeIntervalSince(fetchedAt) > limit
    }

    static func statusCaption(
        indexing: (done: Int, total: Int)?,
        fetchedAt: Date,
        isShowingCachedData: Bool,
        isStale: Bool
    ) -> String? {
        if let indexing {
            return indexingCaption(done: indexing.done, total: indexing.total)
        }
        if fetchedAt == .distantPast {
            return "Not refreshed yet"
        }
        if isShowingCachedData {
            return "Offline · data from \(RelativeTimeFormat.clockTime(fetchedAt))"
        }
        if isStale {
            return "Data from \(RelativeTimeFormat.clockTime(fetchedAt)) (stale)"
        }
        return nil
    }
}

enum CursorCredentialStatus {
    /// False only for a missing Cursor session. Other failures leave availability as it was.
    static func isAvailable(after error: Error) -> Bool {
        guard let tokens = error as? TokensError else { return true }
        if case .tokenNotFound = tokens { return false }
        return true
    }

    /// A missing Cursor login stays quiet when Claude Code is installed and enabled.
    /// Disabling Cursor also hides its error.
    static func shouldSurfaceError(
        isCursorAvailable: Bool,
        cursorEnabled: Bool,
        claudeInstalled: Bool,
        claudeEnabled: Bool
    ) -> Bool {
        guard cursorEnabled else { return false }
        if !isCursorAvailable, claudeInstalled, claudeEnabled { return false }
        return true
    }
}

import Foundation
import Testing
@testable import Tokens

@Test func visibleSourcesWhenBothAreOn() {
    let sources = PanelSourceResolver.visibleSources(
        cursorAvailable: true,
        cursorEnabled: true,
        claudeInstalled: true,
        claudeEnabled: true
    )
    #expect(sources == [.cursor, .claudeCode])
}

@Test func visibleSourcesClaudeOnlyWhenCursorIsMissingOrOff() {
    #expect(
        PanelSourceResolver.visibleSources(
            cursorAvailable: false,
            cursorEnabled: true,
            claudeInstalled: true,
            claudeEnabled: true
        ) == [.claudeCode]
    )
    #expect(
        PanelSourceResolver.visibleSources(
            cursorAvailable: true,
            cursorEnabled: false,
            claudeInstalled: true,
            claudeEnabled: true
        ) == [.claudeCode]
    )
}

@Test func visibleSourcesCursorOnly() {
    #expect(
        PanelSourceResolver.visibleSources(
            cursorAvailable: true,
            cursorEnabled: true,
            claudeInstalled: false,
            claudeEnabled: true
        ) == [.cursor]
    )
    #expect(
        PanelSourceResolver.visibleSources(
            cursorAvailable: true,
            cursorEnabled: true,
            claudeInstalled: true,
            claudeEnabled: false
        ) == [.cursor]
    )
}

@Test func visibleSourcesEmptyWhenNeitherIsUsable() {
    #expect(
        PanelSourceResolver.visibleSources(
            cursorAvailable: false,
            cursorEnabled: true,
            claudeInstalled: false,
            claudeEnabled: true
        ).isEmpty
    )
    #expect(
        PanelSourceResolver.visibleSources(
            cursorAvailable: true,
            cursorEnabled: false,
            claudeInstalled: true,
            claudeEnabled: false
        ).isEmpty
    )
}

@Test func activeSourceFallsBackWhenStoredSourceIsHidden() {
    let both = PanelSourceResolver.visibleSources(
        cursorAvailable: true,
        cursorEnabled: true,
        claudeInstalled: true,
        claudeEnabled: true
    )
    #expect(PanelSourceResolver.activeSource(stored: nil, visible: both) == .cursor)
    #expect(PanelSourceResolver.activeSource(stored: .claudeCode, visible: both) == .claudeCode)
    #expect(PanelSourceResolver.activeSource(stored: .cursor, visible: both) == .cursor)

    let claudeOnly: [UsageSource] = [.claudeCode]
    #expect(PanelSourceResolver.activeSource(stored: .cursor, visible: claudeOnly) == .claudeCode)
    #expect(PanelSourceResolver.activeSource(stored: nil, visible: claudeOnly) == .claudeCode)

    #expect(PanelSourceResolver.activeSource(stored: .cursor, visible: []) == nil)
    #expect(PanelSourceResolver.activeSource(stored: nil, visible: []) == nil)
}

@Test func displayedSourceKeepsCursorErrorPanelWhenClaudeCannotReplaceIt() {
    #expect(
        PanelSourceResolver.displayedSource(
            stored: .claudeCode,
            cursorAvailable: false,
            cursorEnabled: true,
            claudeInstalled: false,
            claudeEnabled: true
        ) == .cursor
    )
    #expect(
        PanelSourceResolver.displayedSource(
            stored: nil,
            cursorAvailable: false,
            cursorEnabled: true,
            claudeInstalled: true,
            claudeEnabled: true
        ) == .claudeCode
    )
    #expect(
        PanelSourceResolver.displayedSource(
            stored: nil,
            cursorAvailable: false,
            cursorEnabled: false,
            claudeInstalled: false,
            claudeEnabled: false
        ) == nil
    )
}

@Test func sourceSwitcherTitlesUseEachSourceStyle() {
    #expect(
        PanelSourceResolver.segmentTitle(source: .cursor, windowDollars: 12.4, isPlaceholder: false)
            == "Cursor  $12.40"
    )
    #expect(
        PanelSourceResolver.segmentTitle(source: .claudeCode, windowDollars: 31.2, isPlaceholder: false)
            == "Claude Code  ~$31.20"
    )
    #expect(
        PanelSourceResolver.segmentTitle(source: .claudeCode, windowDollars: 0, isPlaceholder: true)
            == "Claude Code  ~$—.——"
    )
}

@Test func indexingCaptionMatchesTheStatusSlotCopy() {
    #expect(
        PanelSourceResolver.indexingCaption(done: 12, total: 71)
            == "Indexing Claude Code · 12 of 71 sessions"
    )
}

@Test func settingsSourceLabels() {
    #expect(PanelSourceResolver.cursorSettingsLabel(signedIn: true) == "Cursor · Signed in")
    #expect(PanelSourceResolver.cursorSettingsLabel(signedIn: false) == "Cursor · Not signed in")
    #expect(
        PanelSourceResolver.claudeSettingsLabel(installed: false, sessionCount: 4)
            == "Claude Code · Not found"
    )
    #expect(
        PanelSourceResolver.claudeSettingsLabel(installed: true, sessionCount: 164)
            == "Claude Code · 164 sessions in ~/.claude"
    )
    #expect(
        PanelSourceResolver.claudeSettingsLabel(installed: true, sessionCount: 1)
            == "Claude Code · 1 session in ~/.claude"
    )
}

@Test func transcriptPathsKeySubagentsSeparately() {
    let parent = ClaudeSessionFile(
        path: "/Users/tom/.claude/projects/escaped/sess.jsonl",
        sessionId: "sess",
        agentId: nil,
        offset: 0,
        mtime: .distantPast,
        size: 0,
        usage: [],
        prompts: [],
        title: nil,
        cwd: "/tmp/demo",
        gitBranch: "main"
    )
    let child = ClaudeSessionFile(
        path: "/Users/tom/.claude/projects/escaped/sess/subagents/agent-abc.jsonl",
        sessionId: "sess",
        agentId: "agent-abc",
        offset: 0,
        mtime: .distantPast,
        size: 0,
        usage: [],
        prompts: [],
        title: nil,
        cwd: "/tmp/demo",
        gitBranch: "main"
    )
    let paths = ClaudeCodeStore.transcriptPaths(in: [parent, child])
    #expect(paths["sess"] == parent.path)
    #expect(paths["sess:agent-abc"] == child.path)
}

@Test func cursorEnabledDefaultsToOn() {
    let suite = "com.burnrate.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let settings = SettingsStore(defaults: defaults, persistMembershipSecretInKeychain: false)
    #expect(settings.cursorEnabled)
    settings.cursorEnabled = false
    #expect(defaults.bool(forKey: "cursorEnabled") == false)

    let reloaded = SettingsStore(defaults: defaults, persistMembershipSecretInKeychain: false)
    #expect(reloaded.cursorEnabled == false)
}

@Test func missingCursorTokenMarksCredentialsUnavailable() {
    #expect(CursorCredentialStatus.isAvailable(after: TokensError.tokenNotFound) == false)
    #expect(CursorCredentialStatus.isAvailable(after: TokensError.databaseNotFound) == true)
    #expect(CursorCredentialStatus.isAvailable(after: TokensError.httpStatus(500)) == true)
    #expect(CursorCredentialStatus.isAvailable(after: URLError(.notConnectedToInternet)) == true)
}

@Test func cursorErrorStaysQuietOnlyWhenClaudeCodeCanReplaceIt() {
    #expect(
        CursorCredentialStatus.shouldSurfaceError(
            isCursorAvailable: false,
            cursorEnabled: true,
            claudeInstalled: true,
            claudeEnabled: true
        ) == false
    )
    #expect(
        CursorCredentialStatus.shouldSurfaceError(
            isCursorAvailable: false,
            cursorEnabled: true,
            claudeInstalled: false,
            claudeEnabled: true
        ) == true
    )
    #expect(
        CursorCredentialStatus.shouldSurfaceError(
            isCursorAvailable: false,
            cursorEnabled: true,
            claudeInstalled: true,
            claudeEnabled: false
        ) == true
    )
    #expect(
        CursorCredentialStatus.shouldSurfaceError(
            isCursorAvailable: true,
            cursorEnabled: true,
            claudeInstalled: true,
            claudeEnabled: true
        ) == true
    )
    #expect(
        CursorCredentialStatus.shouldSurfaceError(
            isCursorAvailable: false,
            cursorEnabled: false,
            claudeInstalled: false,
            claudeEnabled: false
        ) == false
    )
}

@Test @MainActor func usageStoreCursorAvailabilityWithoutNetwork() async {
    let suite = "com.burnrate.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = SettingsStore(defaults: defaults, persistMembershipSecretInKeychain: false)
    let store = UsageStore(settings: settings, anomalyMonitor: nil)

    #expect(store.isCursorAvailable)
    #expect(store.surfacedLastError == nil)

    store.applyRefreshFailure(TokensError.tokenNotFound, cachedDataAvailable: false)
    #expect(store.isCursorAvailable == false)
    #expect(store.surfacedLastError != nil)
    #expect(store.burnLevel == .error)

    store.noteClaudeCodeInstalled(true)
    #expect(store.surfacedLastError == nil)
    #expect(store.burnLevel != .error)

    settings.claudeCodeEnabled = false
    #expect(store.surfacedLastError != nil)
    #expect(store.burnLevel == .error)

    settings.claudeCodeEnabled = true
    store.noteCursorCredentialsFound()
    #expect(store.isCursorAvailable)
    #expect(store.surfacedLastError == nil)
}

@Test @MainActor func disabledCursorSkipsRefresh() async {
    let suite = "com.burnrate.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }
    let settings = SettingsStore(defaults: defaults, persistMembershipSecretInKeychain: false)
    settings.cursorEnabled = false
    let store = UsageStore(settings: settings, anomalyMonitor: nil)

    await store.refresh()

    #expect(store.isCursorAvailable)
    #expect(store.hasCompletedFetch == false)
    #expect(store.lastError == nil)
    #expect(store.isLoading == false)
}

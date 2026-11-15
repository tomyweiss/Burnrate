import Foundation
import Testing
@testable import Tokens

@Test func claudeCodeEnabledDefaultsToOn() {
    let (suite, defaults) = claudeStoreDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let settings = claudeStoreSettings(defaults)
    #expect(settings.claudeCodeEnabled)
    settings.claudeCodeEnabled = false
    #expect(defaults.bool(forKey: "claudeCodeEnabled") == false)

    let reloaded = claudeStoreSettings(defaults)
    #expect(reloaded.claudeCodeEnabled == false)
}

@Test @MainActor func claudeCodeStoreClearsWhenClaudeCodeIsNotInstalled() async throws {
    let fixture = try ClaudeStoreFixture()
    defer { fixture.cleanup() }
    let settings = claudeStoreSettings(fixture.defaults)
    let store = ClaudeCodeStore(
        settings: settings,
        anomalyMonitor: nil,
        projectsRoot: fixture.root,
        cacheURL: fixture.cacheURL
    )

    await store.refresh()

    #expect(store.isInstalled == false)
    #expect(store.hasCompletedFetch)
    #expect(store.isLoading == false)
    #expect(store.snapshot.eventCount == 0)
    #expect(store.snapshot.windowCostCents == 0)
    #expect(store.isSpikeActive == false)
    #expect(store.burnLevel == .calm)
    #expect(store.indexingProgress == nil)
    #expect(store.unpricedModels.isEmpty)
    #expect(store.lastError == nil)
}

@Test @MainActor func claudeCodeStorePricesFilesInTheWindowAndSkipsOlderOnes() async throws {
    let fixture = try ClaudeStoreFixture()
    defer { fixture.cleanup() }
    let now = Date()
    let stamp = claudeStoreTimestamp(now.addingTimeInterval(-60))
    let old = try claudeStoreUsageLine(
        id: "old-msg",
        sessionId: "sess-old",
        model: "claude-haiku-4-5",
        timestamp: stamp,
        input: 0,
        output: 1_000_000
    )
    let live = try claudeStoreUsageLine(
        id: "live-msg",
        sessionId: "sess-live",
        model: "claude-opus-5-5",
        timestamp: stamp,
        input: 1_000_000,
        output: 0,
        cwd: "/Users/tom/workspace/tokens",
        gitBranch: "feature/claude"
    )
    let unpriced = try claudeStoreUsageLine(
        id: "mystery-msg",
        sessionId: "sess-live",
        model: "zeta-unknown",
        timestamp: stamp,
        input: 50,
        output: 0,
        cwd: "/Users/tom/workspace/tokens",
        gitBranch: "feature/claude"
    )
    let title = try claudeStoreTitleLine(sessionId: "sess-live", title: "Ship the parser")
    try fixture.write(
        "proj/sess-old.jsonl",
        old + "\n",
        mtime: now.addingTimeInterval(-40 * 24 * 60 * 60)
    )
    try fixture.write(
        "proj/sess-live.jsonl",
        [live, unpriced, title].joined(separator: "\n") + "\n",
        mtime: now
    )

    let index = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    _ = await index.refresh(sinceMs: 0)

    let settings = claudeStoreSettings(fixture.defaults)
    settings.anomalyThresholdDollars = 1
    let store = ClaudeCodeStore(
        settings: settings,
        anomalyMonitor: nil,
        projectsRoot: fixture.root,
        cacheURL: fixture.cacheURL
    )
    await store.refresh()

    #expect(store.isInstalled)
    #expect(store.hasCompletedFetch)
    #expect(store.isLoading == false)
    #expect(store.indexingProgress == nil)
    #expect(store.lastError == nil)
    #expect(store.snapshot.eventCount == 2)
    #expect(abs(store.snapshot.windowCostCents - 400) < 0.000_001)
    #expect(store.snapshot.rootSessions.map(\.conversationId) == ["sess-live"])
    #expect(store.snapshot.rootSessions.first?.name == "Ship the parser")
    #expect(store.snapshot.rootSessions.first?.workspaceName == "tokens")
    #expect(store.snapshot.rootSessions.first?.branchName == "feature/claude")
    #expect(store.unpricedModels == ["zeta-unknown"])
    #expect(store.isSpikeActive)
    #expect(store.burnLevel == .critical)
}

@Test @MainActor func disablingClaudeCodeClearsTheSnapshot() async throws {
    let fixture = try ClaudeStoreFixture()
    defer { fixture.cleanup() }
    let stamp = claudeStoreTimestamp(Date().addingTimeInterval(-30))
    let line = try claudeStoreUsageLine(
        id: "live-msg",
        sessionId: "sess-live",
        model: "claude-opus-5-5",
        timestamp: stamp,
        input: 1_000_000,
        output: 0
    )
    try fixture.write("proj/sess-live.jsonl", line + "\n", mtime: Date())

    let settings = claudeStoreSettings(fixture.defaults)
    let store = ClaudeCodeStore(
        settings: settings,
        anomalyMonitor: nil,
        projectsRoot: fixture.root,
        cacheURL: fixture.cacheURL
    )
    await store.refresh()
    #expect(store.snapshot.eventCount == 1)
    #expect(store.isInstalled)

    settings.claudeCodeEnabled = false
    await store.refresh()

    #expect(store.isInstalled)
    #expect(store.hasCompletedFetch)
    #expect(store.isLoading == false)
    #expect(store.snapshot.eventCount == 0)
    #expect(store.snapshot.windowCostCents == 0)
    #expect(store.isSpikeActive == false)
    #expect(store.unpricedModels.isEmpty)
    #expect(store.indexingProgress == nil)
}

private func claudeStoreDefaults() -> (suite: String, defaults: UserDefaults) {
    let suite = "com.burnrate.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (suite, defaults)
}

private func claudeStoreSettings(_ defaults: UserDefaults) -> SettingsStore {
    SettingsStore(defaults: defaults, persistMembershipSecretInKeychain: false)
}

private func claudeStoreTimestamp(_ date: Date) -> String {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return formatter.string(from: date)
}

private func claudeStoreUsageLine(
    id: String,
    sessionId: String,
    model: String,
    timestamp: String,
    input: Int,
    output: Int,
    cwd: String = "/tmp/demo",
    gitBranch: String = "main"
) throws -> String {
    let object: [String: Any] = [
        "type": "assistant",
        "timestamp": timestamp,
        "sessionId": sessionId,
        "cwd": cwd,
        "gitBranch": gitBranch,
        "message": [
            "id": id,
            "model": model,
            "role": "assistant",
            "usage": [
                "input_tokens": input,
                "cache_creation_input_tokens": 0,
                "cache_read_input_tokens": 0,
                "output_tokens": output,
            ],
        ] as [String: Any],
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    return String(decoding: data, as: UTF8.self)
}

private func claudeStoreTitleLine(sessionId: String, title: String) throws -> String {
    let data = try JSONSerialization.data(withJSONObject: [
        "type": "custom-title",
        "customTitle": title,
        "sessionId": sessionId,
    ])
    return String(decoding: data, as: UTF8.self)
}

private final class ClaudeStoreFixture {
    let root: URL
    let cacheURL: URL
    let defaults: UserDefaults
    let suite: String
    private let base: URL

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-store-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("projects", isDirectory: true)
        cacheURL = base.appendingPathComponent("claude-index.json")
        let isolated = claudeStoreDefaults()
        suite = isolated.suite
        defaults = isolated.defaults
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: base)
        defaults.removePersistentDomain(forName: suite)
    }

    func write(_ relative: String, _ contents: String, mtime: Date?) throws {
        let file = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: file)
        if let mtime {
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
        }
    }
}

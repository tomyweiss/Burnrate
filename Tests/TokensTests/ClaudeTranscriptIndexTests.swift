import Foundation
import Testing
import TokensCore
@testable import Tokens

@Test func claudeIndexParsesSessionAndSubagentOnFirstRefresh() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }

    let session = try ClaudeIndexLines.usage(id: "msg_1", sessionId: "sess-1")
    let prompt = try ClaudeIndexLines.prompt(uuid: "prompt-1", sessionId: "sess-1", text: "fix the parser")
    let title = try ClaudeIndexLines.title(sessionId: "sess-1", title: "Parser work")
    try fixture.write(
        "proj/sess-1.jsonl",
        ["not json", session, prompt, title].joined(separator: "\n") + "\n"
    )

    let subUsage = try ClaudeIndexLines.usage(
        id: "msg_sub",
        sessionId: "not-the-parent",
        output: 7,
        cwd: "/tmp/sub",
        gitBranch: "dev",
        model: "claude-sonnet-5",
        sidechain: true
    )
    let subPrompt = try ClaudeIndexLines.prompt(
        uuid: "prompt-sub",
        sessionId: "not-the-parent",
        text: "sub prompt"
    )
    try fixture.write(
        "proj/sess-1/subagents/agent-xyz.jsonl",
        [subUsage, subPrompt].joined(separator: "\n") + "\n"
    )
    try fixture.write("proj/sess-1/extra.jsonl", session + "\n")

    let progress = ProgressLog()
    let index = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    let files = await index.refresh(sinceMs: 0) { done, total in
        progress.append(done, total)
    }

    #expect(files.count == 2)
    #expect(progress.done == [1])
    #expect(progress.total == [1])
    #expect(await index.sessionCount() == 1)

    let sessionFile = try #require(files.first { $0.sessionId == "sess-1" && $0.agentId == nil })
    #expect(sessionFile.usage.map(\.messageId) == ["msg_1"])
    #expect(sessionFile.usage.first?.sessionId == "sess-1")
    #expect(sessionFile.prompts.map(\.text) == ["fix the parser"])
    #expect(sessionFile.title == "Parser work")
    #expect(sessionFile.cwd == "/tmp/demo")
    #expect(sessionFile.gitBranch == "main")
    #expect(sessionFile.offset > 0)

    let subagent = try #require(files.first { $0.agentId == "agent-xyz" })
    #expect(subagent.sessionId == "sess-1")
    #expect(subagent.path.hasSuffix("proj/sess-1/subagents/agent-xyz.jsonl"))
    let usage = try #require(subagent.usage.first)
    #expect(usage.sessionId == "sess-1")
    #expect(usage.messageId == "msg_sub")
    #expect(usage.model == "claude-sonnet-5")
    #expect(usage.outputTokens == 7)
    #expect(usage.inputTokens == 2)
    #expect(usage.cacheCreationTokens == 3)
    #expect(usage.cacheReadTokens == 4)
    #expect(usage.isSidechain)
    #expect(usage.cwd == "/tmp/sub")
    #expect(usage.gitBranch == "dev")
    #expect(subagent.prompts.map(\.text) == ["sub prompt"])
    #expect(subagent.prompts.first?.sessionId == "sess-1")
    #expect(subagent.prompts.first?.skills == [])
}

@Test func claudeIndexReportsProgressOverParentSessions() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    let line = try ClaudeIndexLines.usage(id: "msg_a", sessionId: "sess-a")
    try fixture.write("proj/sess-a.jsonl", line + "\n", mtime: ClaudeIndexFixture.date(30))
    try fixture.write(
        "proj/sess-a/subagents/agent-xyz.jsonl",
        try ClaudeIndexLines.usage(id: "msg_sub", sessionId: "sess-a", sidechain: true) + "\n",
        mtime: ClaudeIndexFixture.date(20)
    )
    try fixture.write(
        "proj/sess-b/subagents/agent-only.jsonl",
        try ClaudeIndexLines.usage(id: "msg_b", sessionId: "sess-b", sidechain: true) + "\n",
        mtime: ClaudeIndexFixture.date(10)
    )

    let progress = ProgressLog()
    let index = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    _ = await index.refresh(sinceMs: 0) { done, total in
        progress.append(done, total)
    }

    #expect(progress.done == [1, 2])
    #expect(progress.total == [2, 2])
}

@Test func claudeIndexAppendsOnlyNewLinesAndAdvancesOffset() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    let path = "proj/sess-1.jsonl"
    let first = try ClaudeIndexLines.usage(id: "msg_1", sessionId: "sess-1", output: 10)
    let second = try ClaudeIndexLines.usage(id: "msg_2", sessionId: "sess-1", output: 4)
    let prompt = try ClaudeIndexLines.prompt(uuid: "p2", sessionId: "sess-1", text: "next")
    try fixture.write(path, first + "\n", mtime: ClaudeIndexFixture.date(10_000))

    let index = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    let initial = await index.refresh(sinceMs: 0)
    let initialFile = try #require(initial.first)
    #expect(initialFile.usage.map(\.messageId) == ["msg_1"])
    #expect(initialFile.offset == UInt64(Data((first + "\n").utf8).count))

    try fixture.append(path, [second, prompt].joined(separator: "\n") + "\n", mtime: ClaudeIndexFixture.date(20_000))
    let updated = await index.refresh(sinceMs: 0)
    let file = try #require(updated.first)
    #expect(file.usage.map(\.messageId) == ["msg_1", "msg_2"])
    #expect(file.usage.map(\.outputTokens) == [10, 4])
    #expect(file.prompts.map(\.text) == ["next"])
    let onDisk = try Data(contentsOf: fixture.url(path))
    #expect(file.offset == UInt64(onDisk.count))
    #expect(file.offset > initialFile.offset)
}

@Test func claudeIndexWaitsForAPartialLineToFinish() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    let path = "proj/sess-1.jsonl"
    let first = try ClaudeIndexLines.usage(id: "msg_1", sessionId: "sess-1")
    let second = try ClaudeIndexLines.usage(id: "msg_2", sessionId: "sess-1", output: 8)
    let partial = String(second.dropLast(12))
    try fixture.write(
        path,
        first + "\n" + partial,
        mtime: ClaudeIndexFixture.date(10_000)
    )

    let index = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    let initial = await index.refresh(sinceMs: 0)
    let initialFile = try #require(initial.first)
    #expect(initialFile.usage.map(\.messageId) == ["msg_1"])
    #expect(initialFile.offset == UInt64(Data((first + "\n").utf8).count))

    try fixture.append(path, String(second.suffix(12)) + "\n", mtime: ClaudeIndexFixture.date(20_000))
    let updated = await index.refresh(sinceMs: 0)
    let file = try #require(updated.first)
    #expect(file.usage.map(\.messageId) == ["msg_1", "msg_2"])
    #expect(file.usage.map(\.outputTokens) == [10, 8])
    #expect(file.offset == UInt64(try Data(contentsOf: fixture.url(path)).count))
}

@Test func claudeIndexReplacesRecordsWhenAFileShrinks() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    let path = "proj/sess-1.jsonl"
    let original = [
        try ClaudeIndexLines.usage(
            id: "msg_old",
            sessionId: "sess-1",
            cwd: "/old/" + String(repeating: "o", count: 2_000)
        ),
        try ClaudeIndexLines.prompt(uuid: "old", sessionId: "sess-1", text: "old prompt"),
        try ClaudeIndexLines.title(sessionId: "sess-1", title: "Old"),
    ].joined(separator: "\n") + "\n"
    try fixture.write(path, original, mtime: ClaudeIndexFixture.date(10_000))

    let index = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    let initial = await index.refresh(sinceMs: 0)
    #expect(initial.first?.usage.map(\.messageId) == ["msg_old"])
    #expect(initial.first?.title == "Old")

    let replacement = [
        try ClaudeIndexLines.usage(id: "msg_new", sessionId: "sess-1", output: 3, cwd: "/new", gitBranch: "next"),
        try ClaudeIndexLines.prompt(uuid: "new", sessionId: "sess-1", text: "new prompt"),
        try ClaudeIndexLines.title(sessionId: "sess-1", title: "New"),
    ].joined(separator: "\n") + "\n"
    try fixture.write(path, replacement, mtime: ClaudeIndexFixture.date(20_000))
    #expect(try Data(contentsOf: fixture.url(path)).count < Data(original.utf8).count)

    let updated = await index.refresh(sinceMs: 0)
    let file = try #require(updated.first)
    #expect(file.usage.map(\.messageId) == ["msg_new"])
    #expect(file.prompts.map(\.text) == ["new prompt"])
    #expect(file.title == "New")
    #expect(file.cwd == "/new")
    #expect(file.gitBranch == "next")
    #expect(file.offset == UInt64(Data(replacement.utf8).count))
}

@Test func claudeIndexReplacesRecordsWhenMtimeMovesBackwards() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    let path = "proj/sess-1.jsonl"
    let original = try ClaudeIndexLines.usage(id: "msg_old", sessionId: "sess-1") + "\n"
    try fixture.write(path, original, mtime: ClaudeIndexFixture.date(50_000))

    let index = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    let initial = await index.refresh(sinceMs: 0)
    let initialOffset = try #require(initial.first?.offset)

    let rewritten = try ClaudeIndexLines.usage(
        id: "msg_new",
        sessionId: "sess-1",
        cwd: String(repeating: "x", count: 4_000)
    ) + "\n"
    try fixture.write(path, rewritten, mtime: ClaudeIndexFixture.date(40_000))
    #expect(UInt64(Data(rewritten.utf8).count) > initialOffset)

    let updated = await index.refresh(sinceMs: 0)
    let file = try #require(updated.first)
    #expect(file.usage.map(\.messageId) == ["msg_new"])
    #expect(file.cwd == String(repeating: "x", count: 4_000))
}

@Test func claudeIndexReloadsPersistedFilesAfterSourcesAreDeleted() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    let line = try ClaudeIndexLines.usage(id: "msg_1", sessionId: "sess-1", output: 11)
    let prompt = try ClaudeIndexLines.prompt(uuid: "p1", sessionId: "sess-1", text: "keep me")
    try fixture.write(
        "proj/sess-1.jsonl",
        [line, prompt, try ClaudeIndexLines.title(sessionId: "sess-1", title: "Kept")].joined(separator: "\n") + "\n"
    )
    try fixture.write(
        "proj/sess-1/subagents/agent-xyz.jsonl",
        try ClaudeIndexLines.usage(id: "msg_sub", sessionId: "sess-1", sidechain: true) + "\n"
    )

    let first = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    let indexed = await first.refresh(sinceMs: 0)
    #expect(indexed.count == 2)
    fixture.deleteSources()

    let second = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    let reloaded = await second.refresh(sinceMs: 0)
    #expect(reloaded.count == 2)
    let session = try #require(reloaded.first { $0.agentId == nil })
    #expect(session.usage.map(\.messageId) == ["msg_1"])
    #expect(session.usage.first?.outputTokens == 11)
    #expect(session.prompts.map(\.text) == ["keep me"])
    #expect(session.title == "Kept")
    #expect(session.cwd == "/tmp/demo")
    let subagent = try #require(reloaded.first { $0.agentId == "agent-xyz" })
    #expect(subagent.sessionId == "sess-1")
    #expect(subagent.usage.map(\.messageId) == ["msg_sub"])
    #expect(await second.sessionCount() == 1)
}

@Test func claudeIndexSkipsFilesOlderThanTheWindowButKeepsThem() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    let oldLine = try ClaudeIndexLines.usage(id: "msg_old", sessionId: "a-old")
    let newLine = try ClaudeIndexLines.usage(id: "msg_new", sessionId: "b-new")
    try fixture.write("proj/a-old.jsonl", oldLine + "\n", mtime: ClaudeIndexFixture.date(1_000))
    try fixture.write("proj/b-new.jsonl", newLine + "\n", mtime: ClaudeIndexFixture.date(5_000))

    let index = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    let progress = ProgressLog()
    let first = await index.refresh(sinceMs: 3_000_000) { done, total in
        progress.append(done, total)
    }
    #expect(progress.done == [1])
    #expect(progress.total == [1])
    #expect(first.map(\.sessionId) == ["b-new"])
    #expect(first.first?.usage.map(\.messageId) == ["msg_new"])

    let indexed = await index.refresh(sinceMs: 0)
    #expect(indexed.map(\.sessionId) == ["b-new", "a-old"])

    try fixture.append(
        "proj/a-old.jsonl",
        try ClaudeIndexLines.usage(id: "msg_extra", sessionId: "a-old") + "\n",
        mtime: ClaudeIndexFixture.date(1_000)
    )
    let second = await index.refresh(sinceMs: 3_000_000)
    #expect(second.map(\.sessionId) == ["b-new", "a-old"])
    let old = try #require(second.first { $0.sessionId == "a-old" })
    #expect(old.usage.map(\.messageId) == ["msg_old"])
}

@Test func claudeIndexDetectsWhetherClaudeCodeIsInstalled() throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    let missing = fixture.root.appendingPathComponent("missing")
    #expect(!ClaudeTranscriptIndex.isClaudeCodeInstalled(root: missing))
    #expect(!ClaudeTranscriptIndex.isClaudeCodeInstalled(root: fixture.root))

    try fixture.write("proj/sess/subagents/agent-only.jsonl", "{}\n")
    #expect(!ClaudeTranscriptIndex.isClaudeCodeInstalled(root: fixture.root))

    try fixture.write("proj/sess.jsonl", "{}\n")
    #expect(ClaudeTranscriptIndex.isClaudeCodeInstalled(root: fixture.root))
}

@Test func claudeIndexDedupesARepeatedMessageAcrossAppends() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    let path = "proj/sess-1.jsonl"
    let first = try ClaudeIndexLines.usage(id: "msg_1", sessionId: "sess-1", output: 10)
    let other = try ClaudeIndexLines.usage(id: "msg_2", sessionId: "sess-1", output: 4)
    try fixture.write(path, [first, other].joined(separator: "\n") + "\n", mtime: ClaudeIndexFixture.date(10_000))

    let index = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    _ = await index.refresh(sinceMs: 0)

    let later = try ClaudeIndexLines.usage(
        id: "msg_1",
        sessionId: "sess-1",
        output: 90,
        cwd: "/tmp/later",
        gitBranch: "later"
    )
    try fixture.append(path, later + "\n", mtime: ClaudeIndexFixture.date(20_000))
    let files = await index.refresh(sinceMs: 0)
    let file = try #require(files.first)
    #expect(file.usage.map(\.messageId) == ["msg_1", "msg_2"])
    #expect(file.usage.map(\.outputTokens) == [90, 4])
    #expect(file.cwd == "/tmp/later")
    #expect(file.gitBranch == "later")
}

@Test func claudeIndexKeepsTheLastNonNilWorkspaceAndTheLastTitle() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    let lines = [
        try ClaudeIndexLines.usage(id: "msg_1", sessionId: "sess-1", cwd: "/first", gitBranch: "main"),
        try ClaudeIndexLines.title(sessionId: "sess-1", title: "First"),
        try ClaudeIndexLines.usage(id: "msg_2", sessionId: "sess-1", cwd: "/second", gitBranch: nil),
        try ClaudeIndexLines.title(sessionId: "sess-1", title: "Second", summary: true),
        try ClaudeIndexLines.usage(id: "msg_3", sessionId: "sess-1", output: 1, cwd: nil, gitBranch: nil),
    ]
    try fixture.write("proj/sess-1.jsonl", lines.joined(separator: "\n") + "\n")

    let index = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    let files = await index.refresh(sinceMs: 0)
    let file = try #require(files.first)
    #expect(file.cwd == "/second")
    #expect(file.gitBranch == "main")
    #expect(file.title == "Second")
    #expect(file.usage.map(\.messageId) == ["msg_1", "msg_2", "msg_3"])
}

@Test func claudeIndexContinuesAReloadedFileWithoutRereadingThePrefix() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    let path = "proj/sess-1.jsonl"
    let first = try ClaudeIndexLines.usage(id: "msg_1", sessionId: "sess-1", output: 10)
    try fixture.write(path, first + "\n", mtime: ClaudeIndexFixture.date(10_000))

    let original = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    let indexed = await original.refresh(sinceMs: 0)
    #expect(indexed.first?.usage.map(\.messageId) == ["msg_1"])

    var bytes = try Data(contentsOf: fixture.url(path))
    bytes[0] = 0x58
    try bytes.write(to: fixture.url(path))
    let second = try ClaudeIndexLines.usage(id: "msg_2", sessionId: "sess-1", output: 6)
    try fixture.append(path, second + "\n", mtime: ClaudeIndexFixture.date(20_000))

    let reloaded = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    let files = await reloaded.refresh(sinceMs: 0)
    #expect(files.count == 1)
    #expect(files.first?.usage.map(\.messageId) == ["msg_1", "msg_2"])
    #expect(files.first?.usage.map(\.outputTokens) == [10, 6])
}

@Test func claudeIndexStartsEmptyWhenTheCacheIsCorrupt() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    try Data("{{{".utf8).write(to: fixture.cacheURL)
    try fixture.write(
        "proj/sess-1.jsonl",
        try ClaudeIndexLines.usage(id: "msg_1", sessionId: "sess-1") + "\n"
    )

    let index = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    let files = await index.refresh(sinceMs: 0)
    #expect(files.map(\.sessionId) == ["sess-1"])
    #expect(files.first?.usage.map(\.messageId) == ["msg_1"])
}

@Test func claudeIndexReadsALineThatSpansChunks() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    let line = try ClaudeIndexLines.usage(
        id: "msg_1",
        sessionId: "sess-1",
        cwd: String(repeating: "y", count: 80)
    )
    try fixture.write("proj/sess-1.jsonl", line + "\n")

    let index = ClaudeTranscriptIndex(
        projectsRoot: fixture.root,
        cacheURL: fixture.cacheURL,
        readChunkBytes: 24
    )
    let files = await index.refresh(sinceMs: 0)
    let file = try #require(files.first)
    #expect(file.usage.map(\.messageId) == ["msg_1"])
    #expect(file.cwd == String(repeating: "y", count: 80))
    #expect(file.offset == UInt64(Data((line + "\n").utf8).count))
}

@Test func claudeIndexCountsAnOrphanSubagentAsItsParentSession() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    try fixture.write(
        "proj/sess-2/subagents/agent-only.jsonl",
        try ClaudeIndexLines.usage(id: "msg_only", sessionId: "other", sidechain: true) + "\n"
    )
    let index = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    let files = await index.refresh(sinceMs: 0)
    #expect(files.count == 1)
    #expect(files.first?.sessionId == "sess-2")
    #expect(files.first?.agentId == "agent-only")
    #expect(files.first?.usage.first?.sessionId == "sess-2")
    #expect(await index.sessionCount() == 1)
}

@Test func claudeIndexSkipsRewritingTheCacheWhenNothingChanged() async throws {
    let fixture = try ClaudeIndexFixture()
    defer { fixture.cleanup() }
    try fixture.write(
        "proj/sess-1.jsonl",
        try ClaudeIndexLines.usage(id: "msg_1", sessionId: "sess-1") + "\n",
        mtime: ClaudeIndexFixture.date(10_000)
    )

    let index = ClaudeTranscriptIndex(projectsRoot: fixture.root, cacheURL: fixture.cacheURL)
    _ = await index.refresh(sinceMs: 0)
    let stamped = ClaudeIndexFixture.date(1_700_000_000)
    try FileManager.default.setAttributes(
        [.modificationDate: stamped],
        ofItemAtPath: fixture.cacheURL.path
    )

    _ = await index.refresh(sinceMs: 0)
    let attrs = try FileManager.default.attributesOfItem(atPath: fixture.cacheURL.path)
    let mtime = try #require(attrs[.modificationDate] as? Date)
    #expect(mtime == stamped)
}

@Test func claudeIndexUsesTheBurnrateApplicationSupportCache() {
    #expect(ClaudeTranscriptIndex.defaultRoot.path.hasSuffix("/.claude/projects"))
    let cache = ClaudeTranscriptIndex.defaultCacheURL
    #expect(cache.lastPathComponent == "claude-index.json")
    #expect(cache.deletingLastPathComponent().lastPathComponent == "Burnrate")
    #expect(cache.path.contains("Application Support"))
}

private final class ProgressLog: @unchecked Sendable {
    private let lock = NSLock()
    private var calls: [(done: Int, total: Int)] = []

    func append(_ done: Int, _ total: Int) {
        lock.lock()
        calls.append((done, total))
        lock.unlock()
    }

    var done: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return calls.map(\.done)
    }

    var total: [Int] {
        lock.lock()
        defer { lock.unlock() }
        return calls.map(\.total)
    }
}

private enum ClaudeIndexLines {
    static func usage(
        id: String,
        sessionId: String,
        output: Int = 10,
        cwd: String? = "/tmp/demo",
        gitBranch: String? = "main",
        model: String = "claude-opus-5-5",
        sidechain: Bool = false
    ) throws -> String {
        var object: [String: Any] = [
            "type": "assistant",
            "timestamp": "2026-11-14T20:02:55.108Z",
            "sessionId": sessionId,
            "isSidechain": sidechain,
            "message": [
                "id": id,
                "model": model,
                "role": "assistant",
                "usage": [
                    "input_tokens": 2,
                    "cache_creation_input_tokens": 3,
                    "cache_read_input_tokens": 4,
                    "output_tokens": output,
                ],
            ] as [String: Any],
        ]
        if let cwd { object["cwd"] = cwd }
        if let gitBranch { object["gitBranch"] = gitBranch }
        return try jsonLine(object)
    }

    static func prompt(uuid: String, sessionId: String, text: String) throws -> String {
        try jsonLine([
            "type": "user",
            "uuid": uuid,
            "sessionId": sessionId,
            "timestamp": "2026-11-14T20:02:55.108Z",
            "message": ["role": "user", "content": text],
        ])
    }

    static func title(sessionId: String, title: String, summary: Bool = false) throws -> String {
        if summary {
            return try jsonLine(["type": "summary", "summary": title, "sessionId": sessionId])
        }
        return try jsonLine(["type": "custom-title", "customTitle": title, "sessionId": sessionId])
    }

    private static func jsonLine(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        return String(decoding: data, as: UTF8.self)
    }
}

private final class ClaudeIndexFixture {
    let root: URL
    let cacheURL: URL
    private let base: URL

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-index-\(UUID().uuidString)", isDirectory: true)
        root = base.appendingPathComponent("projects", isDirectory: true)
        cacheURL = base.appendingPathComponent("claude-index.json")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: base)
    }

    func url(_ relative: String) -> URL {
        root.appendingPathComponent(relative)
    }

    @discardableResult
    func write(_ relative: String, _ contents: String, mtime: Date? = nil) throws -> URL {
        let file = url(relative)
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: file)
        if let mtime {
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
        }
        return file
    }

    func append(_ relative: String, _ contents: String, mtime: Date? = nil) throws {
        let file = url(relative)
        let handle = try FileHandle(forWritingTo: file)
        defer { try? handle.close() }
        try handle.seekToEnd()
        try handle.write(contentsOf: Data(contents.utf8))
        if let mtime {
            try FileManager.default.setAttributes([.modificationDate: mtime], ofItemAtPath: file.path)
        }
    }

    func deleteSources() {
        try? FileManager.default.removeItem(at: root)
    }

    static func date(_ seconds: TimeInterval) -> Date {
        Date(timeIntervalSince1970: seconds)
    }
}

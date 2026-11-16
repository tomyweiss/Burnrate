import Foundation
import TokensCore

struct ClaudeSessionFile: Sendable, Hashable, Codable {
    let path: String
    /// File stem for a session transcript. Parent session directory stem for a subagent file.
    let sessionId: String
    /// `"agent-xyz"` file stem for subagent transcripts. Nil for session transcripts.
    let agentId: String?
    /// Bytes consumed. Stops at the last complete line, so a trailing partial line is read again.
    var offset: UInt64
    var mtime: Date
    var size: UInt64
    var usage: [ClaudeUsageRecord]
    var prompts: [ClaudePromptRecord]
    var title: String?
    var cwd: String?
    var gitBranch: String?
}

actor ClaudeTranscriptIndex {
    private var files: [String: ClaudeSessionFile] = [:]
    private var didLoad = false
    private let projectsRoot: URL
    private let cacheURL: URL
    private let readChunkBytes: Int

    /// `readChunkBytes` is the `FileHandle` read size. Tests use a small value to span a line.
    init(
        projectsRoot: URL = ClaudeTranscriptIndex.defaultRoot,
        cacheURL: URL = ClaudeTranscriptIndex.defaultCacheURL,
        readChunkBytes: Int = 4 * 1024 * 1024
    ) {
        self.projectsRoot = projectsRoot
        self.cacheURL = cacheURL
        self.readChunkBytes = max(readChunkBytes, 1)
    }

    nonisolated static var defaultRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/projects", isDirectory: true)
    }

    /// Same Application Support directory `UsageRefreshCache` uses (`Burnrate`, not bundle-id specific).
    nonisolated static var defaultCacheURL: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let directory = base.appendingPathComponent("Burnrate", isDirectory: true)
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        return directory.appendingPathComponent("claude-index.json")
    }

    /// True when `root` exists and some project directory directly contains a `.jsonl` file.
    nonisolated static func isClaudeCodeInstalled(root: URL = defaultRoot) -> Bool {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory),
              isDirectory.boolValue,
              let projects = try? FileManager.default.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
              )
        else { return false }

        for project in projects {
            guard let children = try? FileManager.default.contentsOfDirectory(
                at: project,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ) else { continue }
            if children.contains(where: { $0.pathExtension == "jsonl" }) {
                return true
            }
        }
        return false
    }

    /// Returns every indexed file, including retained deleted files and files not re-read this pass.
    ///
    /// Refreshes files whose mtime is at least `sinceMs`, newest first. Calls `progress(done, total)`
    /// when a parent session's files in this pass are all processed. `total` is the number of
    /// distinct session ids in the pass. Subagent files are still read. Saves the cache when a file
    /// was read, added, or replaced.
    func refresh(
        sinceMs: Double,
        progress: @Sendable (Int, Int) -> Void = { _, _ in }
    ) async -> [ClaudeSessionFile] {
        loadIfNeeded()
        let updated = await Self.ingest(
            existing: files,
            root: projectsRoot,
            sinceMs: sinceMs,
            chunkBytes: readChunkBytes,
            progress: progress
        )
        let changed = updated != files
        files = updated
        if changed {
            Self.save(updated, to: cacheURL)
        }
        return Self.ordered(updated)
    }

    /// Distinct session ids in the index. A subagent counts as its parent session.
    func sessionCount() -> Int {
        loadIfNeeded()
        return Set(files.values.map(\.sessionId)).count
    }

    private func loadIfNeeded() {
        guard !didLoad else { return }
        didLoad = true
        files = Self.load(from: cacheURL)
    }

    private nonisolated static func ingest(
        existing: [String: ClaudeSessionFile],
        root: URL,
        sinceMs: Double,
        chunkBytes: Int,
        progress: @Sendable (Int, Int) -> Void
    ) async -> [String: ClaudeSessionFile] {
        var files = existing
        let discovered = discover(root: root, sinceMs: sinceMs)
        var remaining: [String: Int] = [:]
        remaining.reserveCapacity(discovered.count)
        for item in discovered {
            remaining[item.sessionId, default: 0] += 1
        }
        let total = remaining.count
        var done = 0
        for item in discovered {
            if let file = refreshed(item, existing: files[item.path], chunkBytes: chunkBytes) {
                files[file.path] = file
            }
            let left = remaining[item.sessionId, default: 1] - 1
            remaining[item.sessionId] = left
            if left == 0 {
                done += 1
                progress(done, total)
            }
            await Task.yield()
        }
        return files
    }

    private nonisolated static func refreshed(
        _ item: DiscoveredFile,
        existing: ClaudeSessionFile?,
        chunkBytes: Int
    ) -> ClaudeSessionFile? {
        let start: UInt64
        var state = ParseState()
        if let existing {
            if item.size < existing.offset || item.mtime < existing.mtime {
                start = 0
            } else if item.mtime > existing.mtime {
                start = existing.offset
                state.seed(from: existing)
            } else {
                var unchanged = existing
                unchanged.size = item.size
                unchanged.mtime = item.mtime
                return unchanged
            }
        } else {
            start = 0
        }

        do {
            let end = try readLines(
                at: item.url,
                from: start,
                chunkBytes: chunkBytes,
                sessionId: item.sessionId,
                into: &state
            )
            return ClaudeSessionFile(
                path: item.path,
                sessionId: item.sessionId,
                agentId: item.agentId,
                offset: end.offset,
                mtime: item.mtime,
                size: end.size,
                usage: ClaudeTranscript.dedupe(state.usage),
                prompts: state.prompts,
                title: state.title,
                cwd: state.cwd,
                gitBranch: state.gitBranch
            )
        } catch {
            return existing
        }
    }

    /// Reads complete lines only. `pending` never contains a newline, so each chunk is scanned once.
    private nonisolated static func readLines(
        at url: URL,
        from start: UInt64,
        chunkBytes: Int,
        sessionId: String,
        into state: inout ParseState
    ) throws -> (offset: UInt64, size: UInt64) {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let size = try handle.seekToEnd()
        guard start <= size else { return (start, size) }
        try handle.seek(toOffset: start)

        var pending = Data()
        var consumed = start
        while true {
            let chunk = try handle.read(upToCount: chunkBytes) ?? Data()
            if chunk.isEmpty { break }
            let already = pending.count
            pending.append(chunk)
            var lineStart = pending.startIndex
            var search = pending.index(pending.startIndex, offsetBy: already)
            while let newline = pending[search...].firstIndex(of: 0x0A) {
                let line = pending[lineStart..<newline]
                if !line.isEmpty {
                    let effect = autoreleasepool { lineEffect(Data(line), sessionId: sessionId) }
                    state.apply(effect)
                }
                lineStart = pending.index(after: newline)
                search = lineStart
            }
            if lineStart > pending.startIndex {
                consumed += UInt64(pending.distance(from: pending.startIndex, to: lineStart))
                pending.removeSubrange(..<lineStart)
            }
        }
        return (consumed, size)
    }

    private nonisolated static func lineEffect(_ line: Data, sessionId: String) -> LineEffect {
        switch ClaudeTranscript.parse(line: line) {
        case .usage(let record):
            return .usage(retarget(record, sessionId: sessionId))
        case .prompt(let record):
            return .prompt(retarget(record, sessionId: sessionId))
        case .title(_, let title):
            return .title(title)
        case .ignored:
            return .ignored
        }
    }

    private nonisolated static func retarget(_ record: ClaudeUsageRecord, sessionId: String) -> ClaudeUsageRecord {
        guard record.sessionId != sessionId else { return record }
        return ClaudeUsageRecord(
            messageId: record.messageId,
            timestampMs: record.timestampMs,
            sessionId: sessionId,
            model: record.model,
            inputTokens: record.inputTokens,
            outputTokens: record.outputTokens,
            cacheCreationTokens: record.cacheCreationTokens,
            cacheCreation1hTokens: record.cacheCreation1hTokens,
            cacheReadTokens: record.cacheReadTokens,
            isSidechain: record.isSidechain,
            cwd: record.cwd,
            gitBranch: record.gitBranch
        )
    }

    private nonisolated static func retarget(_ record: ClaudePromptRecord, sessionId: String) -> ClaudePromptRecord {
        guard record.sessionId != sessionId else { return record }
        return ClaudePromptRecord(
            uuid: record.uuid,
            sessionId: sessionId,
            timestampMs: record.timestampMs,
            text: record.text,
            skills: record.skills
        )
    }

    private nonisolated static func discover(root: URL, sinceMs: Double) -> [DiscoveredFile] {
        let root = root.standardizedFileURL
        guard let enumerator = FileManager.default.enumerator(
            at: root,
            includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        var found: [DiscoveredFile] = []
        while let item = enumerator.nextObject() as? URL {
            guard item.pathExtension == "jsonl" else { continue }
            let url = item.standardizedFileURL
            guard let identity = identity(of: url, root: root),
                  let meta = metadata(of: url),
                  meta.mtime.timeIntervalSince1970 * 1000 >= sinceMs
            else { continue }
            found.append(DiscoveredFile(
                path: url.path,
                url: url,
                sessionId: identity.sessionId,
                agentId: identity.agentId,
                mtime: meta.mtime,
                size: meta.size
            ))
        }
        found.sort { lhs, rhs in
            if lhs.mtime != rhs.mtime { return lhs.mtime > rhs.mtime }
            return lhs.path < rhs.path
        }
        return found
    }

    private nonisolated static func identity(
        of url: URL,
        root: URL
    ) -> (sessionId: String, agentId: String?)? {
        let rootParts = root.pathComponents
        let parts = url.pathComponents
        guard parts.count > rootParts.count, Array(parts.prefix(rootParts.count)) == rootParts else {
            return nil
        }
        let relative = Array(parts.dropFirst(rootParts.count))
        let stem = url.deletingPathExtension().lastPathComponent
        switch relative.count {
        case 2 where relative[1].hasSuffix(".jsonl"):
            return (stem, nil)
        case 4 where relative[2] == "subagents" && relative[3].hasSuffix(".jsonl"):
            guard !relative[1].isEmpty else { return nil }
            return (relative[1], stem)
        default:
            return nil
        }
    }

    private nonisolated static func metadata(of url: URL) -> (mtime: Date, size: UInt64)? {
        let keys: Set<URLResourceKey> = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        if let values = try? url.resourceValues(forKeys: keys) {
            if values.isRegularFile == false { return nil }
            if let mtime = values.contentModificationDate, let fileSize = values.fileSize {
                return (mtime, UInt64(fileSize))
            }
        }
        guard let attrs = try? FileManager.default.attributesOfItem(atPath: url.path) else { return nil }
        if let type = attrs[.type] as? FileAttributeType, type != .typeRegular { return nil }
        guard let mtime = attrs[.modificationDate] as? Date else { return nil }
        let size = (attrs[.size] as? NSNumber)?.uint64Value ?? 0
        return (mtime, size)
    }

    private nonisolated static func load(from url: URL) -> [String: ClaudeSessionFile] {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONDecoder().decode(CachePayload.self, from: data)
        else { return [:] }
        var files: [String: ClaudeSessionFile] = [:]
        files.reserveCapacity(payload.files.count)
        for file in payload.files {
            files[file.path] = file
        }
        return files
    }

    private nonisolated static func save(_ files: [String: ClaudeSessionFile], to url: URL) {
        let payload = CachePayload(files: files.values.sorted { $0.path < $1.path })
        guard let data = try? JSONEncoder().encode(payload) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [.posixPermissions: NSNumber(value: 0o700)]
        )
        do {
            try data.write(to: url, options: [.atomic, .completeFileProtection])
        } catch {
            try? data.write(to: url, options: [.atomic])
        }
        try? FileManager.default.setAttributes(
            [.posixPermissions: NSNumber(value: 0o600)],
            ofItemAtPath: url.path
        )
    }

    private nonisolated static func ordered(_ files: [String: ClaudeSessionFile]) -> [ClaudeSessionFile] {
        files.values.sorted { lhs, rhs in
            if lhs.mtime != rhs.mtime { return lhs.mtime > rhs.mtime }
            return lhs.path < rhs.path
        }
    }
}

private struct DiscoveredFile: Sendable {
    var path: String
    var url: URL
    var sessionId: String
    var agentId: String?
    var mtime: Date
    var size: UInt64
}

private struct CachePayload: Codable, Sendable {
    var files: [ClaudeSessionFile]
}

private enum LineEffect: Sendable {
    case usage(ClaudeUsageRecord)
    case prompt(ClaudePromptRecord)
    case title(String)
    case ignored
}

private struct ParseState: Sendable {
    var usage: [ClaudeUsageRecord] = []
    var prompts: [ClaudePromptRecord] = []
    var title: String?
    var cwd: String?
    var gitBranch: String?
    var usageIndex: [String: Int] = [:]

    mutating func seed(from file: ClaudeSessionFile) {
        usage = file.usage
        prompts = file.prompts
        title = file.title
        cwd = file.cwd
        gitBranch = file.gitBranch
        usageIndex.reserveCapacity(file.usage.count)
        for (index, record) in file.usage.enumerated() {
            usageIndex[record.messageId] = index
        }
    }

    mutating func apply(_ effect: LineEffect) {
        switch effect {
        case .usage(let record):
            if let index = usageIndex[record.messageId] {
                usage[index] = record
            } else {
                usageIndex[record.messageId] = usage.count
                usage.append(record)
            }
            if let cwd = record.cwd { self.cwd = cwd }
            if let gitBranch = record.gitBranch { self.gitBranch = gitBranch }
        case .prompt(let record):
            prompts.append(record)
        case .title(let title):
            self.title = title
        case .ignored:
            break
        }
    }
}

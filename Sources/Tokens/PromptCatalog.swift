import Foundation
import SQLite3
import TokensCore

/// A user prompt (chat message) recovered from local Cursor composer data.
struct PromptRecord: Sendable, Hashable {
    let conversationId: String
    let bubbleId: String
    let text: String
    let createdAtMs: Double
    /// Skill names mentioned as slash commands in the prompt, e.g. `/loop` → "loop".
    let skills: [String]
    /// Cursor `conversationTurnIndex` when present; used to order bubbles that share a timestamp.
    let turnIndex: Int?
}

/// Reads user prompts (with timestamps and `/skill` mentions) for conversations
/// from Cursor's local IDE database. Read-only, best effort: conversations whose
/// bubbles are not cached locally (e.g. cloud agents) simply return no prompts.
enum PromptCatalog {
    private static var ideDatabasePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
            )
    }

    /// Prompts per conversation id, each list sorted by creation time ascending.
    static func lookup(
        conversationIds: Set<String>,
        databasePath: URL = ideDatabasePath
    ) -> [String: [PromptRecord]] {
        guard !conversationIds.isEmpty,
              FileManager.default.fileExists(atPath: databasePath.path)
        else { return [:] }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databasePath.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_close(database) }

        var result: [String: [PromptRecord]] = [:]
        for conversationId in conversationIds {
            let prompts = readPrompts(database: database, conversationId: conversationId)
            if !prompts.isEmpty {
                result[conversationId] = prompts
            }
        }
        return result
    }

    /// Maps subagent (child) conversation ids to their immediate parent conversation id.
    ///
    /// Cursor stores the link in two places (either may be present):
    /// - Parent: `subagentComposerIds` (and legacy `subComposerIds`)
    /// - Child: `subagentInfo.parentComposerId`
    ///
    /// Reading both sides lets us relate children even when the parent has no
    /// billing events in the current window (so it was not in `conversationIds`
    /// until we discover it here).
    static func subagentParents(conversationIds: Set<String>) -> [String: String] {
        guard !conversationIds.isEmpty,
              FileManager.default.fileExists(atPath: ideDatabasePath.path)
        else { return [:] }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            ideDatabasePath.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK else {
            return [:]
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT
            json_extract(value, '$.subagentInfo.parentComposerId'),
            json_extract(value, '$.subagentComposerIds'),
            json_extract(value, '$.subComposerIds')
        FROM cursorDiskKV
        WHERE key = ?
        """
        var result: [String: String] = [:]
        for conversationId in conversationIds {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
                continue
            }
            defer { sqlite3_finalize(statement) }

            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, "composerData:\(conversationId)", -1, transient)
            guard sqlite3_step(statement) == SQLITE_ROW else { continue }

            if let cString = sqlite3_column_text(statement, 0) {
                let parent = String(cString: cString)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if !parent.isEmpty, parent != conversationId {
                    result[conversationId] = parent
                }
            }

            for column in Int32(1)...Int32(2) {
                guard let cString = sqlite3_column_text(statement, column),
                      let data = String(cString: cString).data(using: .utf8),
                      let children = try? JSONSerialization.jsonObject(with: data) as? [String]
                else { continue }
                for child in children where !child.isEmpty && child != conversationId {
                    // Child-side parentComposerId wins if both disagree.
                    if result[child] == nil {
                        result[child] = conversationId
                    }
                }
            }
        }
        return result
    }

    // MARK: - Bubble scan

    /// Bubble keys are `bubbleId:<composerId>:<bubbleId>`; the unique index on `key`
    /// makes a half-open range scan cheap.
    ///
    /// Assistant bubbles dwarf user prompts (often 50×+). Extracting `$.text` from
    /// every row is the slow path, so we first collect type-1 keys, then fetch
    /// text only for those rows.
    private static func readPrompts(
        database: OpaquePointer?,
        conversationId: String
    ) -> [PromptRecord] {
        let lower = "bubbleId:\(conversationId):"
        let keys = userBubbleKeys(database: database, conversationId: conversationId)
        guard !keys.isEmpty else { return [] }

        var prompts: [PromptRecord] = []
        let chunkSize = 200
        var start = keys.startIndex
        while start < keys.endIndex {
            let end = keys.index(start, offsetBy: chunkSize, limitedBy: keys.endIndex) ?? keys.endIndex
            prompts.append(contentsOf: promptRecords(
                database: database,
                conversationId: conversationId,
                keyPrefix: lower,
                keys: keys[start..<end]
            ))
            start = end
        }
        return prompts.sorted {
            if $0.createdAtMs != $1.createdAtMs { return $0.createdAtMs < $1.createdAtMs }
            return ($0.turnIndex ?? Int.max) < ($1.turnIndex ?? Int.max)
        }
    }

    private static func userBubbleKeys(
        database: OpaquePointer?,
        conversationId: String
    ) -> [String] {
        let query = """
        SELECT key
        FROM cursorDiskKV
        WHERE key >= ? AND key < ?
          AND json_extract(value, '$.type') = 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let lower = "bubbleId:\(conversationId):"
        let upper = "bubbleId:\(conversationId);" // ';' sorts right after ':'
        sqlite3_bind_text(statement, 1, lower, -1, transient)
        sqlite3_bind_text(statement, 2, upper, -1, transient)

        var keys: [String] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let keyC = sqlite3_column_text(statement, 0) else { continue }
            keys.append(String(cString: keyC))
        }
        return keys
    }

    private static func promptRecords(
        database: OpaquePointer?,
        conversationId: String,
        keyPrefix: String,
        keys: ArraySlice<String>
    ) -> [PromptRecord] {
        guard !keys.isEmpty else { return [] }

        let placeholders = Array(repeating: "?", count: keys.count).joined(separator: ",")
        let query = """
        SELECT key,
               json_extract(value, '$.text'),
               json_extract(value, '$.createdAt'),
               json_extract(value, '$.isSimulatedMsg'),
               json_extract(value, '$.conversationTurnIndex')
        FROM cursorDiskKV
        WHERE key IN (\(placeholders))
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return []
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        for (offset, key) in keys.enumerated() {
            sqlite3_bind_text(statement, Int32(offset + 1), key, -1, transient)
        }

        var prompts: [PromptRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            guard let textC = sqlite3_column_text(statement, 1) else { continue }
            let rawText = String(cString: textC).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !rawText.isEmpty else { continue }

            let isSimulated = sqliteBoolean(statement, column: 3)
            if CursorPromptText.isSynthetic(text: rawText, isSimulated: isSimulated) {
                continue
            }

            let text = CursorPromptText.visible(rawText)
            guard !text.isEmpty else { continue }

            guard let keyC = sqlite3_column_text(statement, 0) else { continue }
            let key = String(cString: keyC)
            let bubbleId = String(key.dropFirst(keyPrefix.count))

            let createdAtMs = CursorPromptText.resolvedCreatedAtMs(
                createdAt: columnString(statement, column: 2),
                text: rawText
            ) ?? 0
            let turnIndex = sqliteOptionalInt(statement, column: 4)

            prompts.append(
                PromptRecord(
                    conversationId: conversationId,
                    bubbleId: bubbleId,
                    text: text,
                    createdAtMs: createdAtMs,
                    skills: skillMentions(in: text),
                    turnIndex: turnIndex
                )
            )
        }
        return prompts
    }

    private static func columnString(_ statement: OpaquePointer?, column: Int32) -> String? {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER, SQLITE_FLOAT:
            let value = sqlite3_column_double(statement, column)
            return value > 0 ? String(value) : nil
        case SQLITE_TEXT:
            guard let cString = sqlite3_column_text(statement, column) else { return nil }
            let text = String(cString: cString).trimmingCharacters(in: .whitespacesAndNewlines)
            return text.isEmpty ? nil : text
        default:
            return nil
        }
    }

    private static func sqliteBoolean(_ statement: OpaquePointer?, column: Int32) -> Bool {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER, SQLITE_FLOAT:
            return sqlite3_column_int(statement, column) != 0
        case SQLITE_TEXT:
            guard let cString = sqlite3_column_text(statement, column) else { return false }
            let text = String(cString: cString).lowercased()
            return text == "true" || text == "1"
        default:
            return false
        }
    }

    private static func sqliteOptionalInt(_ statement: OpaquePointer?, column: Int32) -> Int? {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER, SQLITE_FLOAT:
            return Int(sqlite3_column_int64(statement, column))
        case SQLITE_TEXT:
            guard let cString = sqlite3_column_text(statement, column) else { return nil }
            return Int(String(cString: cString))
        default:
            return nil
        }
    }

    // MARK: - Skill detection

    static func skillMentions(in text: String) -> [String] {
        // Matches `/name` slash commands at a word boundary. Requires a letter first
        // and rejects matches followed by `/` so absolute paths like `/Users/me`
        // don't count. (Local because `Regex` is not Sendable.)
        let skillRegex = #/(?:^|[\s(\["'`])/([A-Za-z][A-Za-z0-9_-]*)(?![A-Za-z0-9_/-])/#
        var seen: Set<String> = []
        var skills: [String] = []
        for match in text.matches(of: skillRegex) {
            let name = String(match.1).lowercased()
            if seen.insert(name).inserted {
                skills.append(name)
            }
        }
        return skills
    }
}

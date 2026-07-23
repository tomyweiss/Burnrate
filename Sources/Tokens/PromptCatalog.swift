import Foundation
import SQLite3

/// A user prompt (chat message) recovered from local Cursor composer data.
struct PromptRecord: Sendable, Hashable {
    let conversationId: String
    let bubbleId: String
    let text: String
    let createdAtMs: Double
    /// Skill names mentioned as slash commands in the prompt, e.g. `/loop` → "loop".
    let skills: [String]
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
    static func lookup(conversationIds: Set<String>) -> [String: [PromptRecord]] {
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

        var result: [String: [PromptRecord]] = [:]
        for conversationId in conversationIds {
            let prompts = readPrompts(database: database, conversationId: conversationId)
            if !prompts.isEmpty {
                result[conversationId] = prompts
            }
        }
        return result
    }

    /// Maps subagent (child) conversation ids to their parent conversation id,
    /// based on `subComposerIds` recorded in each parent's composer data. Only
    /// parents present in `conversationIds` are inspected.
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
        SELECT json_extract(value, '$.subComposerIds')
        FROM cursorDiskKV
        WHERE key = ?
        """
        var result: [String: String] = [:]
        for parentId in conversationIds {
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
                continue
            }
            defer { sqlite3_finalize(statement) }

            let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
            sqlite3_bind_text(statement, 1, "composerData:\(parentId)", -1, transient)
            guard sqlite3_step(statement) == SQLITE_ROW,
                  let cString = sqlite3_column_text(statement, 0),
                  let data = String(cString: cString).data(using: .utf8),
                  let children = try? JSONSerialization.jsonObject(with: data) as? [String]
            else { continue }

            for child in children where !child.isEmpty && child != parentId {
                result[child] = parentId
            }
        }
        return result
    }

    // MARK: - Bubble scan

    /// Bubble keys are `bubbleId:<composerId>:<bubbleId>`; the unique index on `key`
    /// makes a half-open range scan cheap. `json_extract` keeps large payloads inside
    /// SQLite and only surfaces the three fields we need.
    private static func readPrompts(
        database: OpaquePointer?,
        conversationId: String
    ) -> [PromptRecord] {
        let query = """
        SELECT key,
               json_extract(value, '$.type'),
               json_extract(value, '$.text'),
               json_extract(value, '$.createdAt')
        FROM cursorDiskKV
        WHERE key >= ? AND key < ?
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

        var prompts: [PromptRecord] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            // type 1 = user message, 2 = assistant.
            guard sqlite3_column_int(statement, 1) == 1,
                  let textC = sqlite3_column_text(statement, 2)
            else { continue }
            let text = String(cString: textC).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            guard let keyC = sqlite3_column_text(statement, 0) else { continue }
            let key = String(cString: keyC)
            let bubbleId = String(key.dropFirst(lower.count))

            guard let createdAtMs = createdAtMs(from: statement, column: 3) else { continue }

            prompts.append(
                PromptRecord(
                    conversationId: conversationId,
                    bubbleId: bubbleId,
                    text: text,
                    createdAtMs: createdAtMs,
                    skills: skillMentions(in: text)
                )
            )
        }
        return prompts.sorted { $0.createdAtMs < $1.createdAtMs }
    }

    private static func createdAtMs(from statement: OpaquePointer?, column: Int32) -> Double? {
        switch sqlite3_column_type(statement, column) {
        case SQLITE_INTEGER, SQLITE_FLOAT:
            let value = sqlite3_column_double(statement, column)
            return value > 0 ? value : nil
        case SQLITE_TEXT:
            guard let cString = sqlite3_column_text(statement, column) else { return nil }
            return parseISOToMs(String(cString: cString))
        default:
            return nil
        }
    }

    private static let isoWithFraction = Date.ISO8601FormatStyle(includingFractionalSeconds: true)
    private static let isoPlain = Date.ISO8601FormatStyle()

    private static func parseISOToMs(_ text: String) -> Double? {
        if let date = (try? Date(text, strategy: isoWithFraction))
            ?? (try? Date(text, strategy: isoPlain)) {
            return date.timeIntervalSince1970 * 1000
        }
        // Some older bubbles store epoch milliseconds as a string.
        if let ms = Double(text), ms > 0 {
            return ms
        }
        return nil
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

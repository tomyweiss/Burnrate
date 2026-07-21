import Foundation
import SQLite3

struct SessionMeta: Sendable, Hashable {
    let conversationId: String
    let name: String?
    let workspaceName: String?

    var displayName: String {
        let trimmed = name?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !trimmed.isEmpty { return trimmed }
        let short = conversationId.count > 8
            ? String(conversationId.prefix(8))
            : conversationId
        return "Session \(short)"
    }
}

enum SessionCatalog {
    private static var databasePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
            )
    }

    /// Resolve titles/workspaces for the given conversation IDs from local Cursor state.
    static func lookup(conversationIds: Set<String>) -> [String: SessionMeta] {
        guard !conversationIds.isEmpty else { return [:] }
        guard FileManager.default.fileExists(atPath: databasePath.path) else { return [:] }

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

        var result: [String: SessionMeta] = [:]

        if let headersJSON = readItemValue(database: database, key: "composer.composerHeaders"),
           let data = headersJSON.data(using: .utf8),
           let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
           let composers = root["allComposers"] as? [[String: Any]] {
            for composer in composers {
                guard let id = composer["composerId"] as? String,
                      conversationIds.contains(id)
                else { continue }
                result[id] = SessionMeta(
                    conversationId: id,
                    name: stringValue(composer["name"]),
                    workspaceName: workspaceName(from: composer["workspaceIdentifier"])
                )
            }
        }

        let missing = conversationIds.subtracting(result.keys)
        for id in missing {
            let key = "composerData:\(id)"
            guard let json = readDiskKVValue(database: database, key: key),
                  let data = json.data(using: .utf8),
                  let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                result[id] = SessionMeta(conversationId: id, name: nil, workspaceName: nil)
                continue
            }
            result[id] = SessionMeta(
                conversationId: id,
                name: stringValue(root["name"]),
                workspaceName: workspaceName(from: root["workspaceIdentifier"])
            )
        }

        return result
    }

    private static func stringValue(_ value: Any?) -> String? {
        guard let text = value as? String else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func workspaceName(from value: Any?) -> String? {
        guard let dict = value as? [String: Any] else { return nil }
        if let uri = dict["uri"] as? [String: Any] {
            if let fsPath = uri["fsPath"] as? String, !fsPath.isEmpty {
                return URL(fileURLWithPath: fsPath).lastPathComponent
            }
            if let path = uri["path"] as? String, !path.isEmpty {
                return URL(fileURLWithPath: path).lastPathComponent
            }
        }
        if let id = dict["id"] as? String, id != "empty-window", !id.isEmpty {
            return nil
        }
        return nil
    }

    private static func readItemValue(database: OpaquePointer?, key: String) -> String? {
        let query = "SELECT value FROM ItemTable WHERE key = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0)
        else {
            return nil
        }
        return String(cString: cString)
    }

    private static func readDiskKVValue(database: OpaquePointer?, key: String) -> String? {
        let query = "SELECT value FROM cursorDiskKV WHERE key = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }
        sqlite3_bind_text(statement, 1, key, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0)
        else {
            return nil
        }
        return String(cString: cString)
    }
}

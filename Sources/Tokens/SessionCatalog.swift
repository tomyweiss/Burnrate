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
    private static var ideDatabasePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
            )
    }

    private static var cliChatsDir: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/chats")
    }

    /// Resolve titles/workspaces for the given conversation IDs from local Cursor state.
    /// Checks the desktop IDE database first, then falls back to CLI per-session store.db files.
    static func lookup(conversationIds: Set<String>) -> [String: SessionMeta] {
        guard !conversationIds.isEmpty else { return [:] }

        var result = lookupIDE(conversationIds: conversationIds)

        let needsCLI = conversationIds.filter { result[$0]?.name == nil }
        if !needsCLI.isEmpty {
            let cliResults = lookupCLI(conversationIds: Set(needsCLI))
            for (id, meta) in cliResults {
                if meta.name != nil {
                    result[id] = meta
                }
            }
        }

        for id in conversationIds where result[id] == nil {
            result[id] = SessionMeta(conversationId: id, name: nil, workspaceName: nil)
        }

        return result
    }

    // MARK: - IDE (desktop) lookup

    private static func lookupIDE(conversationIds: Set<String>) -> [String: SessionMeta] {
        guard FileManager.default.fileExists(atPath: ideDatabasePath.path) else { return [:] }

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

    // MARK: - CLI lookup

    private static func normalizeID(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: "").lowercased()
    }

    private static func lookupCLI(conversationIds: Set<String>) -> [String: SessionMeta] {
        let chatsDir = cliChatsDir
        guard FileManager.default.fileExists(atPath: chatsDir.path) else { return [:] }

        guard let workspaceDirs = try? FileManager.default.contentsOfDirectory(
            at: chatsDir,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [:] }

        let wanted = Dictionary(uniqueKeysWithValues: conversationIds.map { (normalizeID($0), $0) })
        var index: [String: URL] = [:]

        for wsDir in workspaceDirs {
            guard let sessions = try? FileManager.default.contentsOfDirectory(
                at: wsDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { continue }
            for sessionDir in sessions {
                let norm = normalizeID(sessionDir.lastPathComponent)
                if wanted[norm] != nil {
                    index[norm] = sessionDir.appendingPathComponent("store.db")
                }
            }
        }

        var result: [String: SessionMeta] = [:]
        for (norm, originalID) in wanted {
            guard let dbURL = index[norm] else { continue }
            if let meta = readCLIStoreMeta(conversationId: originalID, dbPath: dbURL) {
                result[originalID] = meta
            }
        }
        return result
    }

    private static func readCLIStoreMeta(
        conversationId: String,
        dbPath: URL
    ) -> SessionMeta? {
        guard FileManager.default.fileExists(atPath: dbPath.path) else { return nil }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            dbPath.path, &database, SQLITE_OPEN_READONLY, nil
        ) == SQLITE_OK else { return nil }
        defer { sqlite3_close(database) }

        let query = "SELECT value FROM meta LIMIT 1"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK
        else { return nil }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0)
        else { return nil }

        let hex = String(cString: cString)
        guard let jsonData = dataFromHex(hex),
              let json = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any]
        else { return nil }

        return SessionMeta(
            conversationId: conversationId,
            name: stringValue(json["name"]),
            workspaceName: nil
        )
    }

    private static func dataFromHex(_ hex: String) -> Data? {
        let chars = Array(hex)
        guard chars.count % 2 == 0 else { return nil }
        var data = Data(capacity: chars.count / 2)
        for i in stride(from: 0, to: chars.count, by: 2) {
            guard let byte = UInt8(String(chars[i ... i + 1]), radix: 16) else { return nil }
            data.append(byte)
        }
        return data
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

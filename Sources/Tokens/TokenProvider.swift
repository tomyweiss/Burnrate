import Foundation
import SQLite3
import TokensCore

struct SessionCredentials: Sendable {
    /// Value for the `WorkosCursorSessionToken` cookie (`userId%3A%3Ajwt`).
    let cookieValue: String
}

enum TokenProvider {
    static let databasePath = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent(
            "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
        )

    static func loadSessionCredentials() throws -> SessionCredentials {
        guard FileManager.default.fileExists(atPath: databasePath.path) else {
            throw TokensError.databaseNotFound
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databasePath.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK else {
            throw TokensError.databaseNotFound
        }
        defer { sqlite3_close(database) }

        let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            throw TokensError.tokenNotFound
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0)
        else {
            throw TokensError.tokenNotFound
        }

        let accessToken = String(cString: cString)
        let userID = try extractUserID(from: accessToken)
        return SessionCredentials(cookieValue: "\(userID)%3A%3A\(accessToken)")
    }

    /// Cursor profile display name from local state (never uploaded as email/ID).
    static func loadCursorDisplayName() -> String? {
        guard FileManager.default.fileExists(atPath: databasePath.path) else {
            return nil
        }

        if let profileJSON = readItemValue(key: "cursorAuth/cachedScopedProfile"),
           let name = CursorDisplayName.parseScopedProfileJSON(profileJSON) {
            return name
        }

        if let cached = readItemValue(key: "cursor.customize.userDisplayNameCache") {
            return CursorDisplayName.sanitize(cached)
        }

        return nil
    }

    private static func readItemValue(key: String) -> String? {
        var database: OpaquePointer?
        guard sqlite3_open_v2(
            databasePath.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(database) }

        let query = "SELECT value FROM ItemTable WHERE key = ?"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        _ = key.withCString { cKey in
            sqlite3_bind_text(statement, 1, cKey, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0)
        else {
            return nil
        }

        return String(cString: cString)
    }

    private static func extractUserID(from jwt: String) throws -> String {
        let parts = jwt.split(separator: ".")
        guard parts.count >= 2 else {
            throw TokensError.invalidToken
        }

        var payload = String(parts[1])
        let remainder = payload.count % 4
        if remainder > 0 {
            payload += String(repeating: "=", count: 4 - remainder)
        }
        payload = payload
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")

        guard let data = Data(base64Encoded: payload),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let subject = json["sub"] as? String
        else {
            throw TokensError.invalidToken
        }

        if let separatorIndex = subject.lastIndex(of: "|") {
            return String(subject[subject.index(after: separatorIndex)...])
        }
        return subject
    }
}

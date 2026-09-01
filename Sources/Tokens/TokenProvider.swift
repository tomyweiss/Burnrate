import Foundation
import Security
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

    /// Agent CLI file-store login (`agent login` with `AGENT_CLI_CREDENTIAL_STORE=file`,
    /// or non-macOS). Default macOS CLI login lives in Keychain instead.
    static var cliAuthFilePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/auth.json")
    }

    static func loadSessionCredentials(
        ideDatabasePath: URL = databasePath,
        cliAuthFile: URL = cliAuthFilePath,
        keychainAccessToken: () -> String? = loadCLIKeychainAccessToken,
        now: Date = Date()
    ) throws -> SessionCredentials {
        if let token = loadIDEAccessToken(from: ideDatabasePath),
           !CursorAccessToken.isExpired(token, now: now),
           let credentials = credentials(fromJWT: token) {
            return credentials
        }

        if let token = loadCLIFileAccessToken(from: cliAuthFile),
           !CursorAccessToken.isExpired(token, now: now),
           let credentials = credentials(fromJWT: token) {
            return credentials
        }

        if let token = keychainAccessToken(),
           !CursorAccessToken.isExpired(token, now: now),
           let credentials = credentials(fromJWT: token) {
            return credentials
        }

        throw TokensError.tokenNotFound
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

    private static func credentials(fromJWT jwt: String) -> SessionCredentials? {
        guard let cookie = CursorAccessToken.cookieValue(fromJWT: jwt) else {
            return nil
        }
        return SessionCredentials(cookieValue: cookie)
    }

    private static func loadIDEAccessToken(from dbURL: URL) -> String? {
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            return nil
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            dbURL.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_close(database) }

        let query = "SELECT value FROM ItemTable WHERE key = 'cursorAuth/accessToken'"
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return nil
        }
        defer { sqlite3_finalize(statement) }

        guard sqlite3_step(statement) == SQLITE_ROW,
              let cString = sqlite3_column_text(statement, 0)
        else {
            return nil
        }

        let token = String(cString: cString).trimmingCharacters(in: .whitespacesAndNewlines)
        return token.isEmpty ? nil : token
    }

    private static func loadCLIFileAccessToken(from fileURL: URL) -> String? {
        guard FileManager.default.fileExists(atPath: fileURL.path),
              let data = try? Data(contentsOf: fileURL)
        else {
            return nil
        }
        return CursorAccessToken.accessToken(fromCLIAuthJSON: data)
    }

    /// Cursor Agent CLI default macOS store: Keychain service `cursor-access-token`,
    /// account `cursor-user`.
    static func loadCLIKeychainAccessToken() -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "cursor-access-token",
            kSecAttrAccount as String: "cursor-user",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        let trimmed = token.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

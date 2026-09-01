import Foundation
import SQLite3
import Testing
@testable import Tokens
@testable import TokensCore

@Test func cursorAccessTokenExtractsUserIDAfterPipe() throws {
    let jwt = testJWT(sub: "auth0|user-99")
    #expect(CursorAccessToken.userID(fromJWT: jwt) == "user-99")
}

@Test func cursorAccessTokenCookieValueURLEncodesSeparator() throws {
    let jwt = testJWT(sub: "auth0|abc")
    let cookie = try #require(CursorAccessToken.cookieValue(fromJWT: jwt))
    #expect(cookie == "abc%3A%3A\(jwt)")
}

@Test func cursorAccessTokenTreatsMissingExpAsUsable() {
    let jwt = testJWT(sub: "auth0|abc")
    #expect(!CursorAccessToken.isExpired(jwt, now: Date(timeIntervalSince1970: 1_700_000_000)))
}

@Test func cursorAccessTokenDetectsExpiredJWT() {
    let jwt = testJWT(sub: "auth0|abc", exp: 1_000)
    #expect(CursorAccessToken.isExpired(jwt, now: Date(timeIntervalSince1970: 2_000)))
}

@Test func cursorAccessTokenReadsCLIAuthJSON() throws {
    let jwt = testJWT(sub: "auth0|cli-user")
    let data = try JSONSerialization.data(withJSONObject: [
        "accessToken": jwt,
        "refreshToken": "refresh",
        "apiKey": "cursor_xxx"
    ])
    #expect(CursorAccessToken.accessToken(fromCLIAuthJSON: data) == jwt)
}

@Test func cursorAccessTokenIgnoresAPIKeyOnlyAuthJSON() throws {
    let data = try JSONSerialization.data(withJSONObject: [
        "apiKey": "cursor_xxx"
    ])
    #expect(CursorAccessToken.accessToken(fromCLIAuthJSON: data) == nil)
}

@Test func tokenProviderLoadsCLIAuthJSONWhenIDEDatabaseIsMissing() throws {
    let jwt = testJWT(sub: "auth0|cli-only")
    let authFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("cli-auth-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: authFile) }
    try JSONSerialization.data(withJSONObject: ["accessToken": jwt])
        .write(to: authFile)

    let missingIDE = FileManager.default.temporaryDirectory
        .appendingPathComponent("missing-\(UUID().uuidString).vscdb")

    let credentials = try TokenProvider.loadSessionCredentials(
        ideDatabasePath: missingIDE,
        cliAuthFile: authFile,
        keychainAccessToken: { nil }
    )
    #expect(credentials.cookieValue == "cli-only%3A%3A\(jwt)")
}

@Test func tokenProviderUsesKeychainWhenFilesAreMissing() throws {
    let jwt = testJWT(sub: "auth0|keychain-user")
    let missing = FileManager.default.temporaryDirectory
        .appendingPathComponent("missing-\(UUID().uuidString)")

    let credentials = try TokenProvider.loadSessionCredentials(
        ideDatabasePath: missing.appendingPathComponent("state.vscdb"),
        cliAuthFile: missing.appendingPathComponent("auth.json"),
        keychainAccessToken: { jwt }
    )
    #expect(credentials.cookieValue == "keychain-user%3A%3A\(jwt)")
}

@Test func tokenProviderSkipsExpiredIDETokenAndUsesCLIAuthJSON() throws {
    let expired = testJWT(sub: "auth0|stale", exp: 1_000)
    let fresh = testJWT(sub: "auth0|cli-fresh", exp: 9_999)

    let ideDB = FileManager.default.temporaryDirectory
        .appendingPathComponent("ide-\(UUID().uuidString).vscdb")
    defer { try? FileManager.default.removeItem(at: ideDB) }
    try writeIDEAccessToken(expired, to: ideDB)

    let authFile = FileManager.default.temporaryDirectory
        .appendingPathComponent("cli-auth-\(UUID().uuidString).json")
    defer { try? FileManager.default.removeItem(at: authFile) }
    try JSONSerialization.data(withJSONObject: ["accessToken": fresh])
        .write(to: authFile)

    let credentials = try TokenProvider.loadSessionCredentials(
        ideDatabasePath: ideDB,
        cliAuthFile: authFile,
        keychainAccessToken: { nil },
        now: Date(timeIntervalSince1970: 5_000)
    )
    #expect(credentials.cookieValue == "cli-fresh%3A%3A\(fresh)")
}

private func testJWT(sub: String, exp: Int? = nil) -> String {
    func encode(_ object: [String: Any]) -> String {
        let data = try! JSONSerialization.data(withJSONObject: object)
        return data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
    var payload: [String: Any] = ["sub": sub]
    if let exp {
        payload["exp"] = exp
    }
    return "\(encode(["alg": "none"])).\(encode(payload)).sig"
}

private func writeIDEAccessToken(_ token: String, to url: URL) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
        throw TokenProviderTestError.openFailed
    }
    defer { sqlite3_close(database) }

    guard sqlite3_exec(
        database,
        "CREATE TABLE ItemTable (key TEXT PRIMARY KEY, value TEXT);",
        nil,
        nil,
        nil
    ) == SQLITE_OK else {
        throw TokenProviderTestError.createFailed
    }

    var statement: OpaquePointer?
    guard sqlite3_prepare_v2(
        database,
        "INSERT INTO ItemTable (key, value) VALUES (?, ?)",
        -1,
        &statement,
        nil
    ) == SQLITE_OK else {
        throw TokenProviderTestError.insertFailed
    }
    defer { sqlite3_finalize(statement) }

    let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    sqlite3_bind_text(statement, 1, "cursorAuth/accessToken", -1, transient)
    sqlite3_bind_text(statement, 2, token, -1, transient)
    guard sqlite3_step(statement) == SQLITE_DONE else {
        throw TokenProviderTestError.insertFailed
    }
}

private enum TokenProviderTestError: Error {
    case openFailed
    case createFailed
    case insertFailed
}

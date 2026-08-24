import Foundation
import SQLite3
import Testing
@testable import Tokens

@Test func promptCatalogLookupReturnsUserPromptsOnly() throws {
    let dbURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("prompt-catalog-\(UUID().uuidString).vscdb")
    defer { try? FileManager.default.removeItem(at: dbURL) }

    try createBubbleDatabase(
        at: dbURL,
        rows: [
            (
                key: "bubbleId:conv-a:user-1",
                json: #"{"type":1,"text":"run /loop please","createdAt":1000}"#
            ),
            (
                key: "bubbleId:conv-a:assistant-1",
                json: #"{"type":2,"text":"\#(String(repeating: "x", count: 8000))","createdAt":1001}"#
            ),
            (
                key: "bubbleId:conv-a:empty-user",
                json: #"{"type":1,"text":"   ","createdAt":1002}"#
            ),
            (
                key: "bubbleId:conv-b:user-1",
                json: #"{"type":1,"text":"other conversation","createdAt":2000}"#
            ),
        ]
    )

    let result = PromptCatalog.lookup(conversationIds: ["conv-a"], databasePath: dbURL)

    #expect(result.keys.sorted() == ["conv-a"])
    let prompts = try #require(result["conv-a"])
    #expect(prompts.count == 1)
    #expect(prompts[0].bubbleId == "user-1")
    #expect(prompts[0].text == "run /loop please")
    #expect(prompts[0].skills == ["loop"])
    #expect(prompts[0].createdAtMs == 1000)
}

@Test func promptCatalogLookupIgnoresUnknownConversations() throws {
    let dbURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("prompt-catalog-\(UUID().uuidString).vscdb")
    defer { try? FileManager.default.removeItem(at: dbURL) }

    try createBubbleDatabase(
        at: dbURL,
        rows: [
            (
                key: "bubbleId:conv-a:user-1",
                json: #"{"type":1,"text":"hello","createdAt":1}"#
            ),
        ]
    )

    let result = PromptCatalog.lookup(conversationIds: ["missing"], databasePath: dbURL)
    #expect(result.isEmpty)
}

private func createBubbleDatabase(
    at url: URL,
    rows: [(key: String, json: String)]
) throws {
    var database: OpaquePointer?
    guard sqlite3_open(url.path, &database) == SQLITE_OK else {
        throw PromptCatalogTestError.openFailed
    }
    defer { sqlite3_close(database) }

    guard sqlite3_exec(
        database,
        "CREATE TABLE cursorDiskKV (key TEXT UNIQUE ON CONFLICT REPLACE, value BLOB);",
        nil,
        nil,
        nil
    ) == SQLITE_OK else {
        throw PromptCatalogTestError.createFailed
    }

    let insert = "INSERT INTO cursorDiskKV (key, value) VALUES (?, ?)"
    for row in rows {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, insert, -1, &statement, nil) == SQLITE_OK else {
            throw PromptCatalogTestError.insertFailed
        }
        defer { sqlite3_finalize(statement) }
        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        sqlite3_bind_text(statement, 1, row.key, -1, transient)
        sqlite3_bind_text(statement, 2, row.json, -1, transient)
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw PromptCatalogTestError.insertFailed
        }
    }
}

private enum PromptCatalogTestError: Error {
    case openFailed
    case createFailed
    case insertFailed
}

import Foundation
import SQLite3
import Testing
@testable import Tokens

@Test func composersUpdatedIncludesChatsWithNoBillingEvents() throws {
    let database = FileManager.default.temporaryDirectory
        .appendingPathComponent("burnrate-composers-\(UUID().uuidString).sqlite")
    defer { try? FileManager.default.removeItem(at: database) }

    var db: OpaquePointer?
    #expect(sqlite3_open(database.path, &db) == SQLITE_OK)
    defer { sqlite3_close(db) }
    let schema = """
    CREATE TABLE composerHeaders (
      composerId TEXT PRIMARY KEY,
      lastUpdatedAt INTEGER,
      isArchived INTEGER,
      isSubagent INTEGER,
      value TEXT
    );
    """
    #expect(sqlite3_exec(db, schema, nil, nil, nil) == SQLITE_OK)

    func insert(id: String, updated: Int64, subagent: Int, json: String) {
        var statement: OpaquePointer?
        sqlite3_prepare_v2(
            db,
            "INSERT INTO composerHeaders (composerId, lastUpdatedAt, isArchived, isSubagent, value) VALUES (?, ?, 0, ?, ?)",
            -1,
            &statement,
            nil
        )
        sqlite3_bind_text(statement, 1, id, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_bind_int64(statement, 2, updated)
        sqlite3_bind_int(statement, 3, Int32(subagent))
        sqlite3_bind_text(statement, 4, json, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
        sqlite3_step(statement)
        sqlite3_finalize(statement)
    }

    insert(
        id: "today-session",
        updated: 2_000,
        subagent: 0,
        json: #"{"name":"Bucket calculation issues","isDraft":false}"#
    )
    insert(
        id: "old-session",
        updated: 500,
        subagent: 0,
        json: #"{"name":"Yesterday"}"#
    )
    insert(
        id: "draft-session",
        updated: 2_000,
        subagent: 0,
        json: #"{"name":"Draft","isDraft":true}"#
    )
    insert(
        id: "child-session",
        updated: 2_000,
        subagent: 1,
        json: #"{"name":"Subagent"}"#
    )

    let found = SessionCatalog.composersUpdated(
        fromMs: 1_000,
        toMs: 3_000,
        databasePath: database
    )

    #expect(found.map(\.meta.conversationId) == ["today-session"])
    #expect(found.first?.meta.name == "Bucket calculation issues")
    #expect(found.first?.updatedAtMs == 2_000)
}

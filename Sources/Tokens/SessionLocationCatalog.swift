import Foundation
import SQLite3
import TokensCore

enum SessionStorageKind: String, Sendable {
    case agentTranscript
    case cliStore
    case ideDatabase
    case notFound
}

struct SessionStorageLocation: Sendable {
    let kind: SessionStorageKind
    let fileURL: URL?
    let workspacePath: String?
    let detail: String?

    /// Best on-disk path to copy for investigation (log file, then workspace).
    var copyablePath: String? {
        if let fileURL { return fileURL.path }
        return workspacePath
    }

    var copyHelp: String {
        switch kind {
        case .agentTranscript: "Copy transcript path"
        case .cliStore: "Copy CLI store path"
        case .ideDatabase: "Copy Cursor state database path"
        case .notFound: "No local log file — copies conversation ID"
        }
    }
}

/// Resolves where a Cursor session's conversation log lives on disk (read-only).
enum SessionLocationCatalog {
    private static var projectsRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/projects")
    }

    private static var ideDatabasePath: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(
                "Library/Application Support/Cursor/User/globalStorage/state.vscdb"
            )
    }

    static func resolve(
        conversationId: String,
        parentConversationId: String?
    ) -> SessionStorageLocation {
        let meta = SessionCatalog.lookup(conversationIds: [conversationId])[conversationId]
        let workspacePath = meta?.workspaceFSPath

        if let transcriptURL = findAgentTranscript(
            conversationId: conversationId,
            parentConversationId: parentConversationId,
            workspacePath: workspacePath
        ) {
            let detail = parentConversationId != nil ? "Subagent transcript" : nil
            return SessionStorageLocation(
                kind: .agentTranscript,
                fileURL: transcriptURL,
                workspacePath: workspacePath,
                detail: detail
            )
        }

        if let cliURL = CLIChatStore.storeURL(for: conversationId) {
            return SessionStorageLocation(
                kind: .cliStore,
                fileURL: cliURL,
                workspacePath: workspacePath,
                detail: "CLI chat store"
            )
        }

        if hasIDEBubbles(conversationId: conversationId) {
            return SessionStorageLocation(
                kind: .ideDatabase,
                fileURL: ideDatabasePath,
                workspacePath: workspacePath,
                detail: "Bubbles stored in Cursor state database"
            )
        }

        let cloudDetail = conversationId.hasPrefix("bc-")
            ? "Cloud session — not stored locally"
            : "No local conversation log found"
        return SessionStorageLocation(
            kind: .notFound,
            fileURL: nil,
            workspacePath: workspacePath,
            detail: cloudDetail
        )
    }

    // MARK: - Agent transcripts

    static func findAgentTranscript(
        conversationId: String,
        parentConversationId: String?,
        workspacePath: String?
    ) -> URL? {
        let root = projectsRoot
        guard FileManager.default.fileExists(atPath: root.path) else { return nil }

        let rootMatches = SessionLogPathMatcher.allRootTranscriptURLs(
            projectsRoot: root,
            conversationId: conversationId
        )
        if let match = SessionLogPathMatcher.bestTranscriptMatch(
            among: rootMatches,
            workspacePath: workspacePath
        ) {
            return match
        }

        let subagentMatches = SessionLogPathMatcher.allSubagentTranscriptURLs(
            projectsRoot: root,
            conversationId: conversationId,
            parentConversationId: parentConversationId
        )
        return SessionLogPathMatcher.bestTranscriptMatch(
            among: subagentMatches,
            workspacePath: workspacePath
        )
    }

    // MARK: - IDE bubble storage

    private static func hasIDEBubbles(conversationId: String) -> Bool {
        guard FileManager.default.fileExists(atPath: ideDatabasePath.path) else { return false }

        var database: OpaquePointer?
        guard sqlite3_open_v2(
            ideDatabasePath.path,
            &database,
            SQLITE_OPEN_READONLY,
            nil
        ) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_close(database) }

        let query = """
        SELECT 1 FROM cursorDiskKV
        WHERE key >= ? AND key < ?
        LIMIT 1
        """
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
            return false
        }
        defer { sqlite3_finalize(statement) }

        let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
        let lower = "bubbleId:\(conversationId):"
        let upper = "bubbleId:\(conversationId);"
        sqlite3_bind_text(statement, 1, lower, -1, transient)
        sqlite3_bind_text(statement, 2, upper, -1, transient)
        return sqlite3_step(statement) == SQLITE_ROW
    }
}

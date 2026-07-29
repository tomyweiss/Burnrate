import Foundation

/// Locates Cursor CLI chat `store.db` files under `~/.cursor/chats`.
enum CLIChatStore {
    static var chatsDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cursor/chats")
    }

    static func normalizeID(_ id: String) -> String {
        id.replacingOccurrences(of: "-", with: "").lowercased()
    }

    static func storeURL(
        for conversationId: String,
        chatsRoot: URL = CLIChatStore.chatsDirectory
    ) -> URL? {
        guard FileManager.default.fileExists(atPath: chatsRoot.path) else { return nil }

        guard let workspaceDirs = try? FileManager.default.contentsOfDirectory(
            at: chatsRoot,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return nil }

        let wanted = normalizeID(conversationId)
        for wsDir in workspaceDirs {
            guard let sessions = try? FileManager.default.contentsOfDirectory(
                at: wsDir,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { continue }
            for sessionDir in sessions {
                guard normalizeID(sessionDir.lastPathComponent) == wanted else { continue }
                let dbURL = sessionDir.appendingPathComponent("store.db")
                if FileManager.default.fileExists(atPath: dbURL.path) {
                    return dbURL
                }
            }
        }
        return nil
    }
}

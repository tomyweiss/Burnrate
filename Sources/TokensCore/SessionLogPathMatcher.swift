import Foundation

/// Pure path matching for Cursor session log files (testable without filesystem I/O).
public enum SessionLogPathMatcher {
    public static func projectSlug(fromWorkspacePath path: String) -> String? {
        let trimmed = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let withoutLeadingSlash = trimmed.hasPrefix("/")
            ? String(trimmed.dropFirst())
            : trimmed
        let slug = withoutLeadingSlash.replacingOccurrences(of: "/", with: "-")
        return slug.isEmpty ? nil : slug
    }

    public static func rootTranscriptURL(
        projectsRoot: URL,
        conversationId: String
    ) -> URL? {
        let fileName = "\(conversationId).jsonl"
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return nil }

        var matches: [URL] = []
        for projectDir in projectDirs {
            let candidate = projectDir
                .appendingPathComponent("agent-transcripts")
                .appendingPathComponent(conversationId)
                .appendingPathComponent(fileName)
            if FileManager.default.fileExists(atPath: candidate.path) {
                matches.append(candidate)
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    public static func subagentTranscriptURL(
        projectsRoot: URL,
        conversationId: String,
        parentConversationId: String?
    ) -> URL? {
        let fileName = "\(conversationId).jsonl"
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return nil }

        var matches: [URL] = []
        for projectDir in projectDirs {
            let transcriptsRoot = projectDir.appendingPathComponent("agent-transcripts")
            guard let sessionDirs = try? FileManager.default.contentsOfDirectory(
                at: transcriptsRoot,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { continue }

            for sessionDir in sessionDirs {
                let candidate = sessionDir
                    .appendingPathComponent("subagents")
                    .appendingPathComponent(fileName)
                guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
                if let parentConversationId,
                   sessionDir.lastPathComponent != parentConversationId {
                    continue
                }
                matches.append(candidate)
            }
        }
        return matches.count == 1 ? matches[0] : nil
    }

    public static func allRootTranscriptURLs(
        projectsRoot: URL,
        conversationId: String
    ) -> [URL] {
        let fileName = "\(conversationId).jsonl"
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        return projectDirs.compactMap { projectDir in
            let candidate = projectDir
                .appendingPathComponent("agent-transcripts")
                .appendingPathComponent(conversationId)
                .appendingPathComponent(fileName)
            return FileManager.default.fileExists(atPath: candidate.path) ? candidate : nil
        }
    }

    public static func allSubagentTranscriptURLs(
        projectsRoot: URL,
        conversationId: String,
        parentConversationId: String?
    ) -> [URL] {
        let fileName = "\(conversationId).jsonl"
        guard let projectDirs = try? FileManager.default.contentsOfDirectory(
            at: projectsRoot,
            includingPropertiesForKeys: nil,
            options: .skipsHiddenFiles
        ) else { return [] }

        var matches: [URL] = []
        for projectDir in projectDirs {
            let transcriptsRoot = projectDir.appendingPathComponent("agent-transcripts")
            guard let sessionDirs = try? FileManager.default.contentsOfDirectory(
                at: transcriptsRoot,
                includingPropertiesForKeys: nil,
                options: .skipsHiddenFiles
            ) else { continue }

            for sessionDir in sessionDirs {
                let candidate = sessionDir
                    .appendingPathComponent("subagents")
                    .appendingPathComponent(fileName)
                guard FileManager.default.fileExists(atPath: candidate.path) else { continue }
                if let parentConversationId,
                   sessionDir.lastPathComponent != parentConversationId {
                    continue
                }
                matches.append(candidate)
            }
        }
        if matches.isEmpty, parentConversationId != nil {
            return allSubagentTranscriptURLs(
                projectsRoot: projectsRoot,
                conversationId: conversationId,
                parentConversationId: nil
            )
        }
        return matches
    }

    public static func bestTranscriptMatch(
        among urls: [URL],
        workspacePath: String?
    ) -> URL? {
        guard !urls.isEmpty else { return nil }
        guard urls.count > 1, let workspacePath,
              let slug = projectSlug(fromWorkspacePath: workspacePath)
        else { return urls.first }

        let preferred = urls.filter { $0.path.contains("/\(slug)/") }
        if preferred.count == 1 { return preferred[0] }
        return urls.first
    }
}

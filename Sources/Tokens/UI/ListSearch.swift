import Foundation

enum ListSearch {
    static func isActive(_ query: String) -> Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    static func noMatchesMessage(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "No matches" : "No matches for \"\(trimmed)\""
    }

    static func matches(_ query: String, in fields: [String?]) -> Bool {
        guard isActive(query) else { return true }
        let needle = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return fields.contains { field in
            field?.lowercased().contains(needle) == true
        }
    }

    static func session(_ session: SessionUsage, query: String) -> Bool {
        matches(query, in: [
            session.displayName,
            session.name,
            session.conversationId,
            session.locationSubtitle,
            session.repoName,
            session.branchName,
            session.workspaceName,
            session.models.joined(separator: " "),
        ])
    }

    static func model(_ model: ModelUsage, query: String) -> Bool {
        if matches(query, in: [model.model]) { return true }
        return model.sessions.contains { session($0, query: query) }
    }

    static func skill(_ skill: SkillUsage, query: String) -> Bool {
        matches(query, in: [skill.skill])
    }

    static func prompt(_ prompt: PromptUsage, query: String) -> Bool {
        matches(query, in: [
            prompt.text,
            prompt.headline,
            prompt.sessionName,
            prompt.conversationId,
            prompt.models.joined(separator: " "),
            prompt.skills.joined(separator: " "),
        ])
    }

    static func benchPoint(_ point: BenchPoint, query: String) -> Bool {
        matches(query, in: [point.name, point.id])
    }
}

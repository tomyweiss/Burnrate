import Foundation
import TokensCore

struct ChangeLogDisplaySection: Identifiable, Sendable {
    let version: String
    let items: [String]
    let isHighlighted: Bool
    var id: String { version }
}

enum ChangeLog {
    static func displaySections(
        limit: Int = 3,
        highlightVersion: String? = nil,
        releaseNotes: String? = nil
    ) -> [ChangeLogDisplaySection] {
        let normalizedHighlight = highlightVersion.map(normalizeVersion)
        let sections = ChangeLogParser.displaySections(
            in: markdown,
            limit: limit,
            highlightVersion: highlightVersion,
            releaseNotes: releaseNotes
        )
        return sections.map { section in
            ChangeLogDisplaySection(
                version: section.version,
                items: section.items,
                isHighlighted: normalizedHighlight == section.version
            )
        }
    }

    private static func normalizeVersion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = trimmed.split(separator: "-", maxSplits: 1).first else {
            return trimmed
        }
        return String(base)
    }

    private static var markdown: String {
        if let url = Bundle.module.url(forResource: "CHANGELOG", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        if let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            return text
        }
        return ""
    }
}

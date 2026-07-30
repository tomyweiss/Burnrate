import Foundation
import TokensCore

struct ChangeLogDisplaySection: Identifiable, Sendable {
    let id: String
    let version: String
    let items: [ChangeLogItem]
    let isHighlighted: Bool
}

struct ChangeLogItem: Identifiable, Sendable, Hashable {
    let id: String
    let text: String
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
        return sections.enumerated().map { index, section in
            ChangeLogDisplaySection(
                id: "\(section.version)-\(index)",
                version: section.version,
                items: section.items.enumerated().map { itemIndex, text in
                    ChangeLogItem(id: "\(section.version)-\(index)-\(itemIndex)", text: text)
                },
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

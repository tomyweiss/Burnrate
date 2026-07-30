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
        if let text = loadMarkdown(from: Bundle.main) {
            return text
        }
        // `swift run` places resources in Tokens_Tokens.bundle beside the executable.
        // Do not use Bundle.module here — it traps in a packaged .app (no SPM module bundle).
        let spmBundleURL = Bundle.main.bundleURL
            .appendingPathComponent("Tokens_Tokens.bundle", isDirectory: true)
        if let spmBundle = Bundle(url: spmBundleURL),
           let text = loadMarkdown(from: spmBundle) {
            return text
        }
        return ""
    }

    private static func loadMarkdown(from bundle: Bundle) -> String? {
        guard let url = bundle.url(forResource: "CHANGELOG", withExtension: "md"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return text
    }
}

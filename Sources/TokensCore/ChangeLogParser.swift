import Foundation

public struct ChangeLogSection: Sendable, Hashable {
    public let version: String
    public let items: [String]

    public init(version: String, items: [String]) {
        self.version = version
        self.items = items
    }
}

public enum ChangeLogParser {
    /// Bullet items under a `## version` section in the bundled changelog markdown.
    public static func items(in markdown: String, version: String) -> [String] {
        let lookupVersion = normalizedVersion(version)
        if !lookupVersion.isEmpty, lookupVersion != "0" {
            let matched = parseSection(in: markdown, version: lookupVersion)
            if !matched.isEmpty {
                return matched
            }
        }
        return latestSectionItems(in: markdown)
    }

    public static func parseAllSections(in markdown: String) -> [ChangeLogSection] {
        var sections: [ChangeLogSection] = []
        var currentVersion: String?
        var currentItems: [String] = []

        func flush() {
            guard let currentVersion else { return }
            sections.append(ChangeLogSection(version: currentVersion, items: currentItems))
        }

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                flush()
                currentVersion = normalizedVersion(String(trimmed.dropFirst(3)))
                currentItems = []
                continue
            }

            guard currentVersion != nil else { continue }

            if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !item.isEmpty {
                    currentItems.append(item)
                }
            }
        }

        flush()
        return sections
    }

    /// Up to `limit` recent versions. When `highlightVersion` is set (e.g. an incoming
    /// update), that version is listed first and uses `releaseNotes` if it is not in
    /// the bundled changelog yet.
    public static func displaySections(
        in markdown: String,
        limit: Int = 3,
        highlightVersion: String? = nil,
        releaseNotes: String? = nil
    ) -> [ChangeLogSection] {
        let all = parseAllSections(in: markdown)
        let highlight = highlightVersion.map(normalizedVersion)
        var result: [ChangeLogSection] = []

        if let highlight, !highlight.isEmpty {
            if let section = all.first(where: { normalizedVersion($0.version) == highlight }) {
                result.append(section)
            } else {
                result.append(
                    ChangeLogSection(
                        version: highlight,
                        items: itemsFromReleaseNotes(releaseNotes)
                    )
                )
            }
        }

        for section in all {
            if result.count >= limit { break }
            if let highlight, normalizedVersion(section.version) == highlight { continue }
            result.append(section)
        }

        return Array(result.prefix(limit))
    }

    public static func itemsFromReleaseNotes(_ notes: String?) -> [String] {
        guard let notes else { return [] }
        var items: [String] = []
        for line in notes.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !item.isEmpty {
                    items.append(item)
                }
            }
        }
        return items
    }

    private static func parseSection(in markdown: String, version: String) -> [String] {
        let lookupVersion = normalizedVersion(version)
        guard !lookupVersion.isEmpty else { return [] }

        var inSection = false
        var items: [String] = []

        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if trimmed.hasPrefix("## ") {
                let headerVersion = normalizedVersion(String(trimmed.dropFirst(3)))
                if inSection, headerVersion != lookupVersion {
                    break
                }
                inSection = headerVersion == lookupVersion
                continue
            }

            guard inSection else { continue }

            if trimmed.hasPrefix("- ") {
                let item = String(trimmed.dropFirst(2)).trimmingCharacters(in: .whitespaces)
                if !item.isEmpty {
                    items.append(item)
                }
            }
        }

        return items
    }

    private static func latestSectionItems(in markdown: String) -> [String] {
        for line in markdown.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard trimmed.hasPrefix("## ") else { continue }
            let version = normalizedVersion(String(trimmed.dropFirst(3)))
            guard !version.isEmpty else { continue }
            return parseSection(in: markdown, version: version)
        }
        return []
    }

    private static func normalizedVersion(_ raw: String) -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let base = trimmed.split(separator: "-", maxSplits: 1).first else {
            return trimmed
        }
        return String(base)
    }
}

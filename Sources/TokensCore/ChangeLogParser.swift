import Foundation

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

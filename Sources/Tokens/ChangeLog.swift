import Foundation
import TokensCore

enum ChangeLog {
    static func itemsForCurrentVersion() -> [String] {
        items(for: AppIdentity.shortVersion)
    }

    static func items(for version: String) -> [String] {
        ChangeLogParser.items(in: markdown, version: version)
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

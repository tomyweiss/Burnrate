import Foundation

enum UsageSource: String, CaseIterable, Sendable, Codable {
    case cursor
    case claudeCode

    var displayName: String {
        switch self {
        case .cursor: "Cursor"
        case .claudeCode: "Claude Code"
        }
    }
}

import Foundation

/// How the community leaderboard nickname is chosen.
enum CommunityNicknameSource: String, CaseIterable, Identifiable {
    case cursor
    case random
    case anonymous

    var id: String { rawValue }

    var label: String {
        switch self {
        case .cursor: "Cursor name"
        case .random: "Random"
        case .anonymous: "Anonymous"
        }
    }
}

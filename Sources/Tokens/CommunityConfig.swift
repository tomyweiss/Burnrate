import Foundation

enum CommunityConfig {
    /// Production community API base URL (build-time constant).
    static let baseURL = URL(string: "https://community-api-production-6514.up.railway.app")!
}

enum CommunityError: Error, LocalizedError, Sendable {
    case invalidURL
    case httpStatus(Int)
    case shareToViewRequired
    case decodingFailed
    case apiMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid community API URL."
        case .httpStatus(let code):
            "Community API returned HTTP \(code)."
        case .shareToViewRequired:
            "Enable sharing to view the cohort."
        case .decodingFailed:
            "Could not decode community response."
        case .apiMessage(let message):
            message
        }
    }
}

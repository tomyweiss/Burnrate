import Foundation

enum CommunityConfig {
    /// Production community API base URL (build-time constant).
    static let baseURL = URL(string: "https://community-api-production-6514.up.railway.app")!
}

enum CommunityError: Error, LocalizedError, Sendable {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)
    case shareToViewRequired
    case invalidMembershipSecret
    case decodingFailed
    case apiMessage(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            "Invalid community API URL."
        case .invalidResponse:
            "Community API returned an invalid response."
        case .httpStatus(let code):
            "Community API returned HTTP \(code)."
        case .shareToViewRequired:
            "Community data is not available yet. Try again in a moment."
        case .invalidMembershipSecret:
            "Community credentials were reset. Try again in a moment."
        case .decodingFailed:
            "Could not decode community response."
        case .apiMessage(let message):
            message
        }
    }
}

import Foundation

enum NetworkMessages {
    static func userMessage(for error: Error, cachedDataAvailable: Bool = false) -> String {
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return cachedDataAvailable
                    ? "You're offline. Showing cached data."
                    : "You're offline. Check your connection and try again."
            case .timedOut:
                return cachedDataAvailable
                    ? "Request timed out. Showing cached data."
                    : "Request timed out. Try again."
            default:
                break
            }
        }
        return error.localizedDescription
    }
}

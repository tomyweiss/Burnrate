import Foundation
import Security
import TokensCore

/// How `ClaudeCodeStore` reads plan limits. Tests pass a fake; the app uses `.live`.
struct ClaudePlanLimits {
    var readKeychain: @MainActor () -> Data?
    var fetch: @MainActor (String) async throws -> ClaudeLimits
    var now: @MainActor () -> Date

    @MainActor static let live = ClaudePlanLimits(
        readKeychain: { ClaudeLimitsClient.copyKeychainData() },
        fetch: { try await ClaudeLimitsClient.fetch(accessToken: $0) },
        now: { Date() }
    )
}

/// `GET https://api.anthropic.com/api/oauth/usage`, the call behind Claude Code's
/// `/usage` view. Required headers are `Authorization: Bearer` and
/// `anthropic-beta: oauth-2025-04-20` (a missing beta header is a 401).
/// User-Agent identifies Burnrate. Some clients send `claude-code/<version>` to
/// avoid a tighter rate-limit bucket; this app does not impersonate Claude Code
/// and polls at most once a minute.
/// https://caleb.software/posts/claude-usage-api.html
/// https://github.com/Maciek-roboblog/Claude-Code-Usage-Monitor/issues/202
enum ClaudeLimitsClient {
    static let unavailable = "Limits unavailable"
    static let loginExpired = "Claude Code login expired. Run Claude Code to renew it."
    static let noLogin = "No Claude Code login found. Sign in to Claude Code."
    static let minimumInterval: TimeInterval = 60
    static let endpoint = URL(string: "https://api.anthropic.com/api/oauth/usage")!

    static func makeRequest(accessToken: String, userAgent: String) -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 10)
        request.httpMethod = "GET"
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("oauth-2025-04-20", forHTTPHeaderField: "anthropic-beta")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    static func userAgent() -> String {
        "Burnrate/\(AppIdentity.shortVersion)"
    }

    static func fetch(accessToken: String) async throws -> ClaudeLimits {
        let request = makeRequest(accessToken: accessToken, userAgent: userAgent())
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            reportFailure("Claude plan limits request failed")
            throw error
        }
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            reportFailure("Claude plan limits request failed (HTTP \(status))")
            throw ClaudeLimitsClientError.httpStatus(status)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let limits = ClaudeLimits.parse(json: json)
        else {
            reportFailure("Claude plan limits response was not recognized")
            throw ClaudeLimitsClientError.unrecognized
        }
        return limits
    }

    /// Generic password for service `Claude Code-credentials`. The token stays
    /// in memory for this call and is never written or logged.
    static func copyKeychainData() -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "Claude Code-credentials",
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return data
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 10
        config.timeoutIntervalForResource = 10
        config.httpShouldSetCookies = false
        config.httpCookieAcceptPolicy = .never
        return URLSession(configuration: config)
    }()

    /// Fixed text only. The OAuth token and the response body stay out of telemetry.
    private static func reportFailure(_ message: String) {
        FailureReporter.report(source: .usage, category: .network, message: message)
    }
}

enum ClaudeLimitsClientError: Error {
    case httpStatus(Int)
    case unrecognized
}

import Foundation
import Security
import TokensCore

/// How `ClaudeCodeStore` reads plan limits. Tests pass a fake; the app uses `.live`.
struct ClaudePlanLimits {
    var readKeychain: @MainActor () -> Data?
    var fetch: @MainActor (String) async throws -> ClaudeLimits
    /// Renews the login in the Keychain item and returns the new payload, or nil.
    var renew: @MainActor (Data) async -> Data?
    var now: @MainActor () -> Date

    @MainActor static let live = ClaudePlanLimits(
        readKeychain: { ClaudeLimitsClient.copyKeychainData() },
        fetch: { try await ClaudeLimitsClient.fetch(accessToken: $0) },
        renew: { await ClaudeLimitsClient.renew(data: $0) },
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
    static let loginExpired = "Claude Code login expired and could not be renewed. Run claude in Terminal to sign in again."
    static let noLogin = "No Claude Code login found. Sign in to Claude Code."
    static let minimumInterval: TimeInterval = 60
    static let renewInterval: TimeInterval = 300
    /// Wait after a 429, doubling on each one in a row up to `maximumBackoff`.
    static let minimumBackoff: TimeInterval = 120
    static let maximumBackoff: TimeInterval = 1800
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
        if let http = response as? HTTPURLResponse, http.statusCode == 429 {
            reportFailure("Claude plan limits request failed (HTTP 429)")
            throw ClaudeLimitsClientError.rateLimited(retryAfter: retryAfter(http))
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

    /// `Retry-After` in seconds. The HTTP-date form is not used by this endpoint.
    private static func retryAfter(_ response: HTTPURLResponse) -> TimeInterval? {
        guard let value = response.value(forHTTPHeaderField: "Retry-After"),
              let seconds = TimeInterval(value.trimmingCharacters(in: .whitespaces)),
              seconds.isFinite, seconds > 0
        else { return nil }
        return seconds
    }

    /// Generic password for service `Claude Code-credentials`. The token stays
    /// in memory for this call, is never logged, and is only written back by `renew`.
    ///
    /// Read through `/usr/bin/security`, not `SecItemCopyMatching`. Claude Code
    /// rewrites the item with that tool on every token refresh, which resets the
    /// partition list to `apple-tool:` and makes macOS prompt Burnrate again even
    /// after "Always Allow". The tool itself stays trusted, so this never prompts.
    static func copyKeychainData() -> Data? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = ["find-generic-password", "-s", "Claude Code-credentials", "-w"]
        let stdout = Pipe()
        process.standardOutput = stdout
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return nil
        }
        let output = stdout.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let trimmed = output.prefix { $0 != UInt8(ascii: "\n") }
        return trimmed.isEmpty ? nil : Data(trimmed)
    }

    /// Renews with the refresh token and writes the result back the way Claude Code
    /// does. If Claude Code renewed meanwhile, its item wins and is returned unchanged.
    @MainActor static func renew(data: Data) async -> Data? {
        guard let usedRefresh = ClaudeOAuthRefresh.refreshToken(in: data),
              let body = ClaudeOAuthRefresh.requestBody(from: data)
        else { return nil }
        var request = URLRequest(url: ClaudeOAuthRefresh.tokenURL, timeoutInterval: 30)
        request.httpMethod = "POST"
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent(), forHTTPHeaderField: "User-Agent")

        let reply: Data
        do {
            let (responseData, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                let status = (response as? HTTPURLResponse)?.statusCode ?? -1
                reportFailure("Claude Code login renewal failed (HTTP \(status))")
                return nil
            }
            reply = responseData
        } catch {
            reportFailure("Claude Code login renewal failed")
            return nil
        }

        guard let current = copyKeychainData() else { return nil }
        if ClaudeOAuthRefresh.refreshToken(in: current) != usedRefresh {
            return current
        }
        guard let merged = ClaudeOAuthRefresh.merge(response: reply, into: current, now: Date()),
              writeKeychainData(merged)
        else {
            reportFailure("Claude Code login renewal could not be saved")
            return nil
        }
        return merged
    }

    /// Same command Claude Code runs, so the item's access list and partition list
    /// stay as Claude Code expects. Like Claude Code, short payloads go through
    /// `security -i` stdin to stay out of process arguments; `security -i` truncates
    /// lines past about 4 KB, so longer payloads (with `mcpOAuth`) go in argv.
    private static func writeKeychainData(_ data: Data) -> Bool {
        let hex = data.map { String(format: "%02x", $0) }.joined()
        let account = NSUserName()
        let service = "Claude Code-credentials"
        let command = "add-generic-password -U -a \"\(account)\" -s \"\(service)\" -X \"\(hex)\"\n"
        let useStdin = command.utf8.count <= 4000
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/security")
        process.arguments = useStdin
            ? ["-i"]
            : ["add-generic-password", "-U", "-a", account, "-s", service, "-X", hex]
        let stdin = Pipe()
        process.standardInput = stdin
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
        } catch {
            return false
        }
        if useStdin {
            stdin.fileHandleForWriting.write(Data(command.utf8))
        }
        try? stdin.fileHandleForWriting.close()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return false }
        return ClaudeOAuthRefresh.refreshToken(in: copyKeychainData() ?? Data())
            == ClaudeOAuthRefresh.refreshToken(in: data)
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
    case rateLimited(retryAfter: TimeInterval?)
    case unrecognized
}

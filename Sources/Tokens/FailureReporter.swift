import Foundation

/// Fire-and-forget client failure reports for debugging production issues.
enum FailureReporter {
    enum Source: String {
        case usage
        case community
        case updates
        case app
    }

    enum Category: String {
        case network
        case api
        case auth
        case decode
        case validation
        case unknown
    }

    /// Assigned at app startup; defaults to disabled until wired.
    nonisolated(unsafe) static var isEnabled: () -> Bool = { false }

    static func report(
        source: Source,
        category: Category,
        message: String,
        participantId: String? = nil,
        membershipSecret: String? = nil,
        context: [String: String] = [:]
    ) {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        Task.detached(priority: .utility) {
            await send(
                source: source.rawValue,
                category: category.rawValue,
                message: String(trimmed.prefix(2000)),
                participantId: participantId,
                membershipSecret: membershipSecret,
                context: context
            )
        }
    }

    static func report(error: Error, source: Source, category override: Category? = nil, participantId: String? = nil, membershipSecret: String? = nil) {
        report(
            source: source,
            category: override ?? category(for: error),
            message: error.localizedDescription,
            participantId: participantId,
            membershipSecret: membershipSecret
        )
    }

    static func category(for error: Error) -> Category {
        if let tokensError = error as? TokensError {
            switch tokensError {
            case .tokenNotFound, .invalidToken, .databaseNotFound:
                return .auth
            case .decodingFailed:
                return .decode
            case .httpStatus, .apiMessage, .spendUnavailable:
                return .api
            case .tooManyPages:
                return .validation
            }
        }
        if let communityError = error as? CommunityError {
            switch communityError {
            case .invalidURL, .invalidResponse, .decodingFailed:
                return .decode
            case .httpStatus, .apiMessage, .shareToViewRequired:
                return .api
            }
        }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .notConnectedToInternet, .networkConnectionLost, .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut:
                return .network
            default:
                break
            }
        }
        return .unknown
    }

    /// Strips JWTs and session cookies from telemetry payloads.
    static func redact(_ text: String) -> String {
        var result = text
        if let regex = try? NSRegularExpression(
            pattern: #"eyJ[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}"#,
            options: []
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "[REDACTED_JWT]"
            )
        }
        if let regex = try? NSRegularExpression(
            pattern: #"WorkosCursorSessionToken=[^\s;]+"#,
            options: [.caseInsensitive]
        ) {
            let range = NSRange(result.startIndex..., in: result)
            result = regex.stringByReplacingMatches(
                in: result,
                options: [],
                range: range,
                withTemplate: "WorkosCursorSessionToken=[REDACTED]"
            )
        }
        return result
    }

    private static func send(
        source: String,
        category: String,
        message: String,
        participantId: String?,
        membershipSecret: String?,
        context: [String: String]
    ) async {
        guard isEnabled() else { return }

        let safeMessage = redact(message)
        let safeContext = context.mapValues { redact($0) }

        let url = CommunityConfig.baseURL.appendingPathComponent("v1/client/failures")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppIdentity.shortVersion, forHTTPHeaderField: "clientVersion")
        if let membershipSecret {
            request.setValue(membershipSecret, forHTTPHeaderField: "X-Membership-Secret")
        }
        request.timeoutInterval = 10

        var payload: [String: Any] = [
            "source": source,
            "category": category,
            "message": safeMessage,
            "clientVersion": AppIdentity.versionLabel,
        ]
        if let participantId {
            payload["participantId"] = participantId
        }
        if !safeContext.isEmpty {
            payload["context"] = safeContext
        }

        guard let body = try? JSONSerialization.data(withJSONObject: payload) else { return }

        do {
            request.httpBody = body
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return
            }
        } catch {
            // Never surface telemetry failures to the user.
        }
    }
}

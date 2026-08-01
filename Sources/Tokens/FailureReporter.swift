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

    static func report(
        source: Source,
        category: Category,
        message: String,
        participantId: String? = nil,
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
                context: context
            )
        }
    }

    static func report(error: Error, source: Source, category override: Category? = nil, participantId: String? = nil) {
        report(
            source: source,
            category: override ?? category(for: error),
            message: error.localizedDescription,
            participantId: participantId
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

    private static func send(
        source: String,
        category: String,
        message: String,
        participantId: String?,
        context: [String: String]
    ) async {
        let url = CommunityConfig.baseURL.appendingPathComponent("v1/client/failures")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(AppIdentity.shortVersion, forHTTPHeaderField: "clientVersion")
        request.timeoutInterval = 10

        var payload: [String: Any] = [
            "source": source,
            "category": category,
            "message": message,
            "clientVersion": AppIdentity.versionLabel,
        ]
        if let participantId {
            payload["participantId"] = participantId
        }
        if !context.isEmpty {
            payload["context"] = context
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

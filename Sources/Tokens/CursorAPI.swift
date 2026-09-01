import Foundation

actor CursorAPI {
    private let session: URLSession
    private let maxPages = 20
    private let pageSize = 1000

    init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        config.httpCookieAcceptPolicy = .never
        config.httpShouldSetCookies = false
        session = URLSession(configuration: config)
    }

    func fetchUsageEvents(
        credentials: SessionCredentials,
        startMs: Int64,
        endMs: Int64
    ) async throws -> [UsageEvent] {
        var all: [UsageEvent] = []
        var page = 1
        var totalCount: Int?

        while page <= maxPages {
            let response = try await fetchPage(
                credentials: credentials,
                startMs: startMs,
                endMs: endMs,
                page: page
            )
            let events = response.usageEventsDisplay ?? []
            all.append(contentsOf: events)

            if totalCount == nil {
                totalCount = response.totalUsageEventsCount
            }

            let expected = totalCount ?? all.count
            if events.isEmpty || all.count >= expected {
                break
            }
            if totalCount == nil, events.count < pageSize {
                break
            }
            page += 1
        }

        if page > maxPages {
            throw TokensError.tooManyPages
        }

        return all
    }

    /// Billing-cycle spend for the signed-in user.
    ///
    /// Request-based plans leave every per-event dollar field at zero, so these
    /// cycle totals are the only authoritative spend figures Cursor exposes to a
    /// non-admin session.
    func fetchSpendSummary(credentials: SessionCredentials) async throws -> SpendSummary {
        let stripe = try await getJSON(credentials: credentials, path: "/api/auth/stripe")
        guard let teamId = stripe["teamId"] as? Int else {
            throw TokensError.spendUnavailable
        }

        let me = try await getJSON(credentials: credentials, path: "/api/auth/me")
        guard let userId = me["id"] as? Int else {
            throw TokensError.spendUnavailable
        }

        let spend = try await postJSON(
            credentials: credentials,
            path: "/api/dashboard/get-team-spend",
            body: ["teamId": teamId]
        )

        // Cursor only fills in spend fields for the requesting member; teammates
        // come back without them.
        guard let members = spend["teamMemberSpend"] as? [[String: Any]],
              let mine = members.first(where: { $0["userId"] as? Int == userId })
        else {
            throw TokensError.spendUnavailable
        }

        let onDemand = (mine["spendCents"] as? NSNumber)?.doubleValue ?? 0
        let included = (mine["includedSpendCents"] as? NSNumber)?.doubleValue ?? 0
        let cycleStart = Double(spend["subscriptionCycleStart"] as? String ?? "") ?? 0

        guard onDemand > 0 || included > 0 else {
            throw TokensError.spendUnavailable
        }

        return SpendSummary(
            onDemandCents: onDemand,
            includedCents: included,
            cycleStartMs: cycleStart
        )
    }

    private func getJSON(
        credentials: SessionCredentials,
        path: String
    ) async throws -> [String: Any] {
        guard let url = URL(string: "https://cursor.com" + path) else {
            throw TokensError.apiMessage("Invalid API URL.")
        }
        var request = URLRequest(url: url)
        request.setValue(
            "WorkosCursorSessionToken=\(credentials.cookieValue)",
            forHTTPHeaderField: "Cookie"
        )
        return try await performJSON(request)
    }

    private func postJSON(
        credentials: SessionCredentials,
        path: String,
        body: [String: Any]
    ) async throws -> [String: Any] {
        guard let url = URL(string: "https://cursor.com" + path) else {
            throw TokensError.apiMessage("Invalid API URL.")
        }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue(
            "WorkosCursorSessionToken=\(credentials.cookieValue)",
            forHTTPHeaderField: "Cookie"
        )
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await performJSON(request)
    }

    private func performJSON(_ request: URLRequest) async throws -> [String: Any] {
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TokensError.httpStatus(-1)
        }
        guard (200..<300).contains(http.statusCode) else {
            throw TokensError.httpStatus(http.statusCode)
        }
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw TokensError.decodingFailed
        }
        return object
    }

    private func fetchPage(
        credentials: SessionCredentials,
        startMs: Int64,
        endMs: Int64,
        page: Int
    ) async throws -> UsageEventsResponse {
        guard let url = URL(string: "https://cursor.com/api/dashboard/get-filtered-usage-events") else {
            throw TokensError.apiMessage("Invalid API URL.")
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("https://cursor.com", forHTTPHeaderField: "Origin")
        request.setValue(
            "WorkosCursorSessionToken=\(credentials.cookieValue)",
            forHTTPHeaderField: "Cookie"
        )

        let body: [String: Any] = [
            "startDate": String(startMs),
            "endDate": String(endMs),
            "page": page,
            "pageSize": pageSize
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw TokensError.httpStatus(-1)
        }

        if http.statusCode == 401 {
            throw TokensError.apiMessage(
                "Not authenticated. Sign in to the Cursor app or run `agent login`, then refresh."
            )
        }
        guard (200..<300).contains(http.statusCode) else {
            if let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = obj["error"] as? String {
                throw TokensError.apiMessage(error)
            }
            throw TokensError.httpStatus(http.statusCode)
        }

        do {
            return try JSONDecoder().decode(UsageEventsResponse.self, from: data)
        } catch {
            throw TokensError.decodingFailed
        }
    }
}

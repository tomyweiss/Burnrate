import Foundation

actor CursorAPI {
    private let session: URLSession
    private let maxPages = 20
    private let pageSize = 1000
    private var eventScope: (cookieValue: String, fields: [String: Any])?

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
        let scope = await usageEventScope(credentials: credentials)
        var all: [UsageEvent] = []
        var page = 1
        var totalCount: Int?

        while page <= maxPages {
            let response = try await fetchPage(
                credentials: credentials,
                startMs: startMs,
                endMs: endMs,
                page: page,
                scope: scope
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

    /// Included-pool percentages and cycle dollar totals for the signed-in plan.
    ///
    /// Pools are nil when the account is unlimited or the payload has no pool
    /// bars. Spend is nil when the payload has no on-demand or included cents.
    /// Throws only when the request itself fails.
    ///
    /// These rings sit beside "Spend this cycle", so they use `usage-summary`,
    /// whose billing cycle is that spend cycle (the calendar month). The
    /// current-period endpoint is a different window on unified accounts: a
    /// week that just reset, with the same percent as Grok Bot. Reading it
    /// here draws two empty rings next to a month of spend.
    func fetchUsageCycle(credentials: SessionCredentials) async throws -> (pools: IncludedPools?, spend: CycleSpend?) {
        let summary = try await getJSON(credentials: credentials, path: "/api/usage-summary")
        return (
            pools: IncludedPools.parse(json: summary),
            spend: CycleSpend.parse(json: summary)
        )
    }

    /// Weekly Grok Bot allowance. Nil when this account has no personal pool.
    /// Throws only when the request itself fails.
    func fetchGrokBotUsage(credentials: SessionCredentials) async throws -> GrokBotUsage? {
        let status = try await postJSON(
            credentials: credentials,
            path: "/api/dashboard/get-sand-usage-status",
            body: [:]
        )
        return GrokBotUsage.parse(json: status)
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

    /// Team members' events are only returned when the request names the team,
    /// and naming the team returns every member's events unless `userId` is set.
    /// Personal accounts send neither. A failed lookup is retried next refresh.
    private func usageEventScope(credentials: SessionCredentials) async -> [String: Any] {
        if let eventScope, eventScope.cookieValue == credentials.cookieValue {
            return eventScope.fields
        }
        do {
            let stripe = try await getJSON(credentials: credentials, path: "/api/auth/stripe")
            var fields: [String: Any] = [:]
            if stripe["isTeamMember"] as? Bool == true, let teamId = stripe["teamId"] as? Int {
                let me = try await getJSON(credentials: credentials, path: "/api/auth/me")
                guard let userId = me["id"] as? Int else { return [:] }
                fields = ["teamId": teamId, "userId": userId]
            }
            eventScope = (credentials.cookieValue, fields)
            return fields
        } catch {
            return [:]
        }
    }

    private func fetchPage(
        credentials: SessionCredentials,
        startMs: Int64,
        endMs: Int64,
        page: Int,
        scope: [String: Any]
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

        let body: [String: Any] = scope.merging([
            "startDate": String(startMs),
            "endDate": String(endMs),
            "page": page,
            "pageSize": pageSize
        ]) { _, new in new }
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

import Foundation

actor CursorAPI {
    private let session: URLSession
    private let maxPages = 20
    private let pageSize = 200

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
            if all.count >= expected || events.count < pageSize {
                break
            }
            page += 1
        }

        if page > maxPages {
            throw TokensError.tooManyPages
        }

        return all
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
            throw TokensError.apiMessage("Not authenticated. Sign in to Cursor and try again.")
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

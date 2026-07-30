import Foundation
import TokensCore

actor CommunityClient {
    private let session: URLSession
    private let baseURL: URL
    private let clientVersion: String

    init(
        baseURL: URL = CommunityConfig.baseURL,
        clientVersion: String = AppIdentity.shortVersion
    ) {
        self.baseURL = baseURL
        self.clientVersion = clientVersion
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 60
        session = URLSession(configuration: config)
    }

    func postSnapshot(_ payload: CommunitySnapshotPayload) async throws {
        let url = baseURL.appendingPathComponent("v1/community/snapshot")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientVersion, forHTTPHeaderField: "clientVersion")
        request.httpBody = try JSONEncoder().encode(payload)

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    func fetchRank(participantId: String) async throws -> CommunityRankResponse {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("v1/community/rank"),
            resolvingAgainstBaseURL: false
        )
        components?.queryItems = [URLQueryItem(name: "participantId", value: participantId)]
        guard let url = components?.url else { throw CommunityError.invalidURL }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue(clientVersion, forHTTPHeaderField: "clientVersion")

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 403 {
            throw CommunityError.shareToViewRequired
        }
        try validate(response, data: data)

        do {
            return try JSONDecoder().decode(CommunityRankResponse.self, from: data)
        } catch {
            throw CommunityError.decodingFailed
        }
    }

    func deleteParticipant(participantId: String) async throws {
        let url = baseURL.appendingPathComponent("v1/community/me")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientVersion, forHTTPHeaderField: "clientVersion")
        let body = ["participantId": participantId]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private func validate(_ response: URLResponse, data: Data? = nil) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CommunityError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                throw CommunityError.apiMessage(error)
            }
            throw CommunityError.httpStatus(http.statusCode)
        }
    }
}

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

        let (data, response) = try await session.data(for: request)
        try validate(response, data: data, invalidMembershipSecretMessage: "Invalid membership secret")
    }

    func fetchRank(participantId: String, membershipSecret: String) async throws -> CommunityRankResponse {
        let url = baseURL.appendingPathComponent("v1/community/rank")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientVersion, forHTTPHeaderField: "clientVersion")
        request.setValue(membershipSecret, forHTTPHeaderField: "X-Membership-Secret")
        let body = [
            "participantId": participantId,
            "membershipSecret": membershipSecret,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        if let http = response as? HTTPURLResponse, http.statusCode == 403 {
            throw CommunityError.shareToViewRequired
        }
        try validate(response, data: data, invalidMembershipSecretMessage: "Invalid membership secret")

        do {
            return try JSONDecoder().decode(CommunityRankResponse.self, from: data)
        } catch {
            throw CommunityError.decodingFailed
        }
    }

    func deleteParticipant(participantId: String, membershipSecret: String) async throws {
        let url = baseURL.appendingPathComponent("v1/community/me")
        var request = URLRequest(url: url)
        request.httpMethod = "DELETE"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(clientVersion, forHTTPHeaderField: "clientVersion")
        let body = [
            "participantId": participantId,
            "membershipSecret": membershipSecret,
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (_, response) = try await session.data(for: request)
        try validate(response)
    }

    private func validate(
        _ response: URLResponse,
        data: Data? = nil,
        invalidMembershipSecretMessage: String? = nil
    ) throws {
        guard let http = response as? HTTPURLResponse else {
            throw CommunityError.invalidResponse
        }
        guard (200..<300).contains(http.statusCode) else {
            if let data,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let error = json["error"] as? String {
                if http.statusCode == 401,
                   error == invalidMembershipSecretMessage {
                    throw CommunityError.invalidMembershipSecret
                }
                throw CommunityError.apiMessage(error)
            }
            throw CommunityError.httpStatus(http.statusCode)
        }
    }
}

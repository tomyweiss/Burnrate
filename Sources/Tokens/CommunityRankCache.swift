import Foundation
import TokensCore

enum CommunityRankCache {
    private struct Envelope: Codable {
        let participantId: String
        let savedAt: Date
        let rank: CommunityRankResponse
    }

    private static let defaultsKey = "communityRankCache"

    static func save(_ rank: CommunityRankResponse, participantId: String) {
        let envelope = Envelope(participantId: participantId, savedAt: Date(), rank: rank)
        guard let data = try? JSONEncoder().encode(envelope) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func load(participantId: String) -> (rank: CommunityRankResponse, savedAt: Date)? {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let envelope = try? JSONDecoder().decode(Envelope.self, from: data),
              envelope.participantId == participantId else {
            return nil
        }
        return (envelope.rank, envelope.savedAt)
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }
}

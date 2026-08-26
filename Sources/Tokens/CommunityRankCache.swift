import Foundation
import TokensCore

enum CommunityRankCache {
    private struct Envelope: Codable {
        let participantId: String
        let window: CommunityRankWindow?
        let savedAt: Date
        let rank: CommunityRankResponse
    }

    private static let defaultsKey = "communityRankCache"

    static func save(
        _ rank: CommunityRankResponse,
        participantId: String,
        window: CommunityRankWindow
    ) {
        var entries = loadAll(participantId: participantId)
        entries.removeAll { $0.window == window }
        entries.append(
            Envelope(participantId: participantId, window: window, savedAt: Date(), rank: rank)
        )
        if entries.count > 12 {
            entries.sort { $0.savedAt > $1.savedAt }
            entries = Array(entries.prefix(12))
        }
        guard let data = try? JSONEncoder().encode(entries) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }

    static func load(
        participantId: String,
        window: CommunityRankWindow
    ) -> (rank: CommunityRankResponse, savedAt: Date)? {
        if let cached = loadAll(participantId: participantId).first(where: { $0.window == window }) {
            return (cached.rank, cached.savedAt)
        }
        return nil
    }

    static func clear() {
        UserDefaults.standard.removeObject(forKey: defaultsKey)
    }

    private static func loadAll(participantId: String) -> [Envelope] {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey) else {
            return []
        }

        if let envelopes = try? JSONDecoder().decode([Envelope].self, from: data) {
            return envelopes
                .filter { $0.participantId == participantId }
                .map { envelope in
                    if envelope.window != nil {
                        return envelope
                    }
                    return Envelope(
                        participantId: envelope.participantId,
                        window: .rolling24h,
                        savedAt: envelope.savedAt,
                        rank: envelope.rank
                    )
                }
        }

        if let legacy = try? JSONDecoder().decode(Envelope.self, from: data),
           legacy.participantId == participantId {
            return [
                Envelope(
                    participantId: legacy.participantId,
                    window: .rolling24h,
                    savedAt: legacy.savedAt,
                    rank: legacy.rank
                ),
            ]
        }

        return []
    }
}

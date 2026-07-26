import Foundation

public enum CommunityPayloadBuilder {
    public static let windowHours = 24

    /// Build a rolling last-24h snapshot from cost events only (no session/prompt data).
    public static func build(
        participantId: String,
        nickname: String?,
        events: [CommunityCostEvent],
        now: Date = Date()
    ) -> CommunitySnapshotPayload {
        let startMs = now.addingTimeInterval(-Double(windowHours) * 3600).timeIntervalSince1970 * 1000
        let endMs = now.timeIntervalSince1970 * 1000

        var totalCents: Double = 0
        var byModel: [String: Double] = [:]

        for event in events {
            guard event.timestampMs >= startMs, event.timestampMs <= endMs else { continue }
            totalCents += event.costCents
            let modelName = event.model.isEmpty ? "unknown" : event.model
            byModel[modelName, default: 0] += event.costCents
        }

        let models = byModel
            .map { CommunityModelSpend(name: $0.key, spendCents: Int($0.value.rounded())) }
            .sorted { $0.spendCents > $1.spendCents }

        return CommunitySnapshotPayload(
            participantId: participantId,
            nickname: nickname,
            windowHours: windowHours,
            spendCents: Int(totalCents.rounded()),
            models: models
        )
    }
}

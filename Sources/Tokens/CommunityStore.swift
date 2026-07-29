import Foundation
import TokensCore

@MainActor
@Observable
final class CommunityStore {
    private(set) var rank: CommunityRankResponse?
    private(set) var isLoading = false
    private(set) var lastError: String?

    private let settings: SettingsStore
    private let client: CommunityClient
    private let cursorAPI = CursorAPI()
    private let interactionTracker: InteractionTracker
    private var lastUploadAt: Date?
    private let uploadThrottle: TimeInterval = 5 * 60

    init(
        settings: SettingsStore,
        interactionTracker: InteractionTracker,
        client: CommunityClient = CommunityClient()
    ) {
        self.settings = settings
        self.interactionTracker = interactionTracker
        self.client = client
    }

    var isSharing: Bool { settings.shareCommunityUsage }

    var displayNickname: String {
        let trimmed = settings.communityNickname?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "Anonymous" : trimmed
    }

    func enableSharing() async {
        let participantId = settings.ensureCommunityParticipantId()
        if settings.communityNickname == nil {
            settings.communityNickname = NicknameGenerator.random()
        }
        settings.shareCommunityUsage = true
        lastUploadAt = nil
        await uploadSnapshot(participantId: participantId, force: true)
        await refreshRank()
    }

    func disableSharing() async {
        settings.shareCommunityUsage = false
        if let participantId = settings.communityParticipantId {
            do {
                try await client.deleteParticipant(participantId: participantId)
            } catch {
                // Best-effort delete; local opt-out still applies.
            }
        }
        rank = nil
        lastError = nil
        lastUploadAt = nil
        interactionTracker.reset()
    }

    func shuffleNickname() {
        settings.communityNickname = NicknameGenerator.random()
        if settings.shareCommunityUsage {
            Task { await uploadSnapshotIfNeeded(force: true) }
        }
    }

    func clearNickname() {
        settings.communityNickname = nil
        if settings.shareCommunityUsage {
            Task { await uploadSnapshotIfNeeded(force: true) }
        }
    }

    func refreshRank() async {
        guard settings.shareCommunityUsage,
              let participantId = settings.communityParticipantId else {
            rank = nil
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            rank = try await client.fetchRank(participantId: participantId)
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    /// Called after UsageStore completes a successful refresh.
    func handleUsageRefreshIfNeeded() async {
        guard settings.shareCommunityUsage else { return }
        await uploadSnapshotIfNeeded(force: false)
        await refreshRank()
    }

    private func uploadSnapshotIfNeeded(force: Bool) async {
        guard let participantId = settings.communityParticipantId else { return }
        await uploadSnapshot(participantId: participantId, force: force)
    }

    private func uploadSnapshot(participantId: String, force: Bool) async {
        if !force, let lastUploadAt, Date().timeIntervalSince(lastUploadAt) < uploadThrottle {
            return
        }

        do {
            let payload = try await buildSnapshotPayload(participantId: participantId)
            try await client.postSnapshot(payload)
            lastUploadAt = Date()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func buildSnapshotPayload(participantId: String) async throws -> CommunitySnapshotPayload {
        let credentials = try TokenProvider.loadSessionCredentials()
        let now = Date()
        let window = UsageTimeWindow(
            preset: .last24Hours,
            timeZone: settings.resolvedTimeZone,
            billingDayOfMonth: settings.billingDayOfMonth
        )
        let range = window.dateRange(now: now)
        let startMs = Int64(range.start.timeIntervalSince1970 * 1000)
        let endMs = Int64(range.end.timeIntervalSince1970 * 1000)

        let events = try await cursorAPI.fetchUsageEvents(
            credentials: credentials,
            startMs: startMs,
            endMs: endMs
        )

        let costEvents = events.map { event in
            CommunityCostEvent(
                timestampMs: event.timestampMs,
                model: event.model?.isEmpty == false ? event.model! : "unknown",
                costCents: event.costCents
            )
        }

        let nickname = settings.communityNickname?.trimmingCharacters(in: .whitespacesAndNewlines)
        let resolvedNickname = (nickname?.isEmpty == false) ? nickname : nil

        return CommunityPayloadBuilder.build(
            participantId: participantId,
            nickname: resolvedNickname,
            events: costEvents,
            now: now,
            interactionStats: interactionTracker.snapshot()
        )
    }
}

import Foundation
import TokensCore

@MainActor
@Observable
final class CommunityStore {
    private(set) var rank: CommunityRankResponse?
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var cursorDisplayName: String?

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
        refreshCursorDisplayName()
    }

    var isSharing: Bool { settings.shareCommunityUsage }

    var nicknameSource: CommunityNicknameSource {
        settings.communityNicknameSource
    }

    var displayNickname: String {
        resolvedUploadNickname() ?? "Anonymous"
    }

    var canUseCursorName: Bool {
        cursorDisplayName != nil
    }

    func refreshCursorDisplayName() {
        cursorDisplayName = TokenProvider.loadCursorDisplayName()
    }

    func enableSharing() async {
        refreshCursorDisplayName()
        let participantId = settings.ensureCommunityParticipantId()
        if cursorDisplayName != nil {
            settings.communityNicknameSource = .cursor
        } else if settings.communityNicknameSource == .random,
                  settings.communityNickname == nil {
            settings.communityNickname = NicknameGenerator.random()
        } else if settings.communityNicknameSource == .cursor {
            settings.communityNicknameSource = .random
            if settings.communityNickname == nil {
                settings.communityNickname = NicknameGenerator.random()
            }
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

    func useCursorName() {
        refreshCursorDisplayName()
        settings.communityNicknameSource = .cursor
        uploadIfSharing()
    }

    func shuffleNickname() {
        settings.communityNicknameSource = .random
        settings.communityNickname = NicknameGenerator.random()
        uploadIfSharing()
    }

    func useAnonymous() {
        settings.communityNicknameSource = .anonymous
        settings.communityNickname = nil
        uploadIfSharing()
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
        refreshCursorDisplayName()
        await uploadSnapshotIfNeeded(force: false)
        await refreshRank()
    }

    private func uploadIfSharing() {
        if settings.shareCommunityUsage {
            Task { await uploadSnapshotIfNeeded(force: true) }
        }
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

    private func resolvedUploadNickname() -> String? {
        switch settings.communityNicknameSource {
        case .cursor:
            return cursorDisplayName
        case .random:
            let nickname = settings.communityNickname?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            return (nickname?.isEmpty == false) ? nickname : nil
        case .anonymous:
            return nil
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

        return CommunityPayloadBuilder.build(
            participantId: participantId,
            nickname: resolvedUploadNickname(),
            events: costEvents,
            now: now,
            interactionStats: interactionTracker.snapshot(),
            clientVersion: AppIdentity.versionLabel
        )
    }
}

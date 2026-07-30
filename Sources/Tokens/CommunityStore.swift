import Foundation
import TokensCore

@MainActor
@Observable
final class CommunityStore {
    private(set) var rank: CommunityRankResponse?
    private(set) var isLoading = false
    private(set) var lastError: String?
    private(set) var rankIsStale = false
    private(set) var cursorDisplayName: String?

    private let settings: SettingsStore
    private let client: CommunityClient
    private let interactionTracker: InteractionTracker
    private weak var usageStore: UsageStore?
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
        restoreCachedRankIfAvailable()
    }

    func setUsageStore(_ store: UsageStore?) {
        usageStore = store
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
        rankIsStale = false
        lastUploadAt = nil
        interactionTracker.reset()
        CommunityRankCache.clear()
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
            rankIsStale = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            rank = try await client.fetchRank(participantId: participantId)
            rankIsStale = false
            lastError = nil
            if let rank {
                CommunityRankCache.save(rank, participantId: participantId)
            }
        } catch {
            lastError = NetworkMessages.userMessage(for: error, cachedDataAvailable: rank != nil)
            FailureReporter.report(
                error: error,
                source: .community,
                participantId: settings.communityParticipantId
            )
            if rank == nil {
                restoreCachedRankIfAvailable()
            } else {
                rankIsStale = true
            }
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
            let payload = try buildSnapshotPayload(participantId: participantId)
            try await client.postSnapshot(payload)
            lastUploadAt = Date()
            lastError = nil
        } catch {
            lastError = NetworkMessages.userMessage(for: error, cachedDataAvailable: rank != nil)
            FailureReporter.report(
                error: error,
                source: .community,
                participantId: participantId
            )
        }
    }

    private func restoreCachedRankIfAvailable() {
        guard settings.shareCommunityUsage,
              let participantId = settings.communityParticipantId,
              let cached = CommunityRankCache.load(participantId: participantId) else {
            return
        }
        rank = cached.rank
        rankIsStale = true
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

    private func buildSnapshotPayload(participantId: String) throws -> CommunitySnapshotPayload {
        let events = usageStore?.communityCostEvents ?? []
        guard !events.isEmpty else {
            throw CommunityError.apiMessage("No recent usage data to share yet.")
        }

        return CommunityPayloadBuilder.build(
            participantId: participantId,
            nickname: resolvedUploadNickname(),
            events: events,
            now: Date(),
            interactionStats: interactionTracker.snapshot(),
            clientVersion: AppIdentity.versionLabel
        )
    }
}

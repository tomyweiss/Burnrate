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

    var displayNickname: String {
        cursorDisplayName ?? "Unknown"
    }

    var canEnableSharing: Bool {
        cursorDisplayName != nil
    }

    func refreshCursorDisplayName() {
        cursorDisplayName = TokenProvider.loadCursorDisplayName()
    }

    /// One-time upgrade: reconcile old random nicknames to the Cursor display name on the server.
    func migrateNicknameToCursorDefaultIfNeeded() async {
        if settings.communityPendingPreviousNickname != nil {
            await reconcilePendingNicknameIfNeeded()
        }
    }

    func enableSharing() async {
        refreshCursorDisplayName()
        guard let cursorDisplayName else {
            lastError = "Cursor display name not found. Sign in to Cursor to share."
            return
        }

        let participantId = settings.ensureCommunityParticipantId()
        settings.shareCommunityUsage = true
        lastUploadAt = nil
        lastError = nil
        await uploadSnapshot(participantId: participantId, nickname: cursorDisplayName, force: true)
        await refreshRank()
    }

    func disableSharing() async {
        settings.shareCommunityUsage = false
        settings.communityPendingPreviousNickname = nil
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
        usageStore?.refreshMetrics.reset()
        CommunityRankCache.clear()
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
        await migrateNicknameToCursorDefaultIfNeeded()
        await uploadSnapshotIfNeeded(force: false)
        await refreshRank()
    }

    private func uploadSnapshotIfNeeded(force: Bool) async {
        guard let participantId = settings.communityParticipantId,
              let nickname = cursorDisplayName else { return }
        _ = await uploadSnapshot(participantId: participantId, nickname: nickname, force: force)
    }

    @discardableResult
    private func uploadSnapshot(participantId: String, nickname: String, force: Bool) async -> Bool {
        if !force, let lastUploadAt, Date().timeIntervalSince(lastUploadAt) < uploadThrottle {
            return false
        }

        do {
            let payload = try buildSnapshotPayload(participantId: participantId, nickname: nickname)
            try await client.postSnapshot(payload)
            lastUploadAt = Date()
            lastError = nil
            clearPendingNicknameReconciliation()
            return true
        } catch {
            lastError = NetworkMessages.userMessage(for: error, cachedDataAvailable: rank != nil)
            FailureReporter.report(
                error: error,
                source: .community,
                participantId: participantId
            )
            return false
        }
    }

    private func reconcilePendingNicknameIfNeeded() async {
        guard settings.shareCommunityUsage,
              settings.communityPendingPreviousNickname != nil,
              let participantId = settings.communityParticipantId,
              let nickname = cursorDisplayName else { return }

        let reconciled = await uploadSnapshot(participantId: participantId, nickname: nickname, force: true)
        if reconciled {
            await refreshRank()
        }
    }

    private func clearPendingNicknameReconciliation() {
        settings.communityPendingPreviousNickname = nil
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

    private func buildSnapshotPayload(participantId: String, nickname: String) throws -> CommunitySnapshotPayload {
        let events = usageStore?.communityAnalyticsEvents ?? []
        guard !events.isEmpty else {
            throw CommunityError.apiMessage("No recent usage data to share yet.")
        }

        let now = Date()
        return CommunityPayloadBuilder.build(
            participantId: participantId,
            nickname: nickname,
            previousNickname: settings.communityPendingPreviousNickname,
            events: events,
            now: now,
            interactionStats: interactionTracker.snapshot(),
            dailyEngagement: { [self] day in
                var engagement = interactionTracker.dailyEngagement(forDay: day)
                if let refresh = usageStore?.refreshMetrics.metrics(forDay: day) {
                    engagement = CommunityPayloadBuilder.DailyEngagement(
                        panelOpens: engagement.panelOpens,
                        tabChanges: engagement.tabChanges,
                        refreshAttempts: refresh.attempts,
                        refreshFailures: refresh.failures
                    )
                }
                return engagement
            },
            nicknameSource: "cursor",
            clientConfig: settings.communityClientConfig(),
            clientVersion: AppIdentity.versionLabel
        )
    }
}

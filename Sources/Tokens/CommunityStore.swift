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
    var selectedWindow: CommunityRankWindow = .rolling24h

    private let settings: SettingsStore
    private let client: CommunityClient
    private let interactionTracker: InteractionTracker
    private weak var usageStore: UsageStore?
    private var lastUploadAt: Date?
    private let uploadThrottle: TimeInterval = 5 * 60
    private var didResetCommunityCredentials = false
    private var rankRequestGeneration = 0

    init(
        settings: SettingsStore,
        interactionTracker: InteractionTracker,
        client: CommunityClient = CommunityClient()
    ) {
        self.settings = settings
        self.interactionTracker = interactionTracker
        self.client = client
        settings.shareCommunityUsage = true
        _ = settings.ensureCommunityParticipantId()
        refreshCursorDisplayName()
        restoreCachedRankIfAvailable()
    }

    func setUsageStore(_ store: UsageStore?) {
        usageStore = store
    }

    var displayNickname: String {
        cursorDisplayName ?? "Unknown"
    }

    var needsCursorSignIn: Bool {
        cursorDisplayName == nil
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

    func activateCommunity() async {
        settings.shareCommunityUsage = true
        let participantId = settings.ensureCommunityParticipantId()
        refreshCursorDisplayName()
        guard let cursorDisplayName else {
            lastError = "Cursor display name not found. Sign in to Cursor to appear on the leaderboard."
            return
        }

        lastUploadAt = nil
        lastError = nil
        await uploadSnapshot(participantId: participantId, nickname: cursorDisplayName, force: true)
        await refreshRank()
    }

    func refreshRank() async {
        await refreshRank(for: selectedWindow)
    }

    func refreshRank(for window: CommunityRankWindow) async {
        guard let participantId = settings.communityParticipantId else {
            rank = nil
            rankIsStale = false
            return
        }

        let generation = rankRequestGeneration
        isLoading = true
        defer { isLoading = false }

        do {
            let membershipSecret = settings.ensureCommunityMembershipSecret()
            let response = try await client.fetchRank(
                participantId: participantId,
                membershipSecret: membershipSecret,
                window: window
            )
            guard generation == rankRequestGeneration, window == selectedWindow else { return }
            guard response.rankWindow == window else {
                throw CommunityError.apiMessage(
                    "Historical leaderboard is not available yet. The community API may need an update."
                )
            }
            rank = response
            selectedWindow = window
            rankIsStale = false
            lastError = nil
            CommunityRankCache.save(response, participantId: participantId, window: window)
        } catch {
            guard generation == rankRequestGeneration, window == selectedWindow else { return }
            if await resetCommunityCredentialsIfNeeded(for: error) {
                await refreshRank(for: window)
                return
            }
            lastError = NetworkMessages.userMessage(for: error, cachedDataAvailable: rank != nil)
            FailureReporter.report(
                error: error,
                source: .community,
                participantId: settings.communityParticipantId,
                membershipSecret: settings.communityMembershipSecret
            )
            applyFailedRankFetch(for: window)
        }
    }

    func selectWindow(_ window: CommunityRankWindow) async {
        guard window != selectedWindow else {
            await refreshRank(for: window)
            return
        }
        selectedWindow = window
        prepareForWindowChange(window)
        await refreshRank(for: window)
    }

    func stepWindow(forward: Bool) async {
        let offset = forward ? 1 : -1
        guard let next = selectedWindow.shiftedDays(by: offset) else { return }
        await selectWindow(next)
    }

    private func prepareForWindowChange(_ window: CommunityRankWindow) {
        rankRequestGeneration += 1
        lastError = nil
        if let participantId = settings.communityParticipantId,
           let cached = CommunityRankCache.load(participantId: participantId, window: window),
           cached.rank.rankWindow == window {
            rank = cached.rank
            rankIsStale = true
        } else {
            rank = nil
            rankIsStale = false
        }
    }

    private func applyFailedRankFetch(for window: CommunityRankWindow) {
        if rank?.rankWindow != window {
            rank = nil
            rankIsStale = false
        }
        if rank == nil {
            restoreCachedRankIfAvailable(for: window)
        } else {
            rankIsStale = true
        }
    }

    /// Called after UsageStore completes a successful refresh.
    func handleUsageRefreshIfNeeded() async {
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
            settings.communitySupersededParticipantId = nil
            return true
        } catch {
            if await resetCommunityCredentialsIfNeeded(for: error) {
                let participantId = settings.ensureCommunityParticipantId()
                return await uploadSnapshot(participantId: participantId, nickname: nickname, force: force)
            }
            lastError = NetworkMessages.userMessage(for: error, cachedDataAvailable: rank != nil)
            FailureReporter.report(
                error: error,
                source: .community,
                participantId: participantId,
                membershipSecret: settings.communityMembershipSecret
            )
            return false
        }
    }

    private func reconcilePendingNicknameIfNeeded() async {
        guard settings.communityPendingPreviousNickname != nil,
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

    private func resetCommunityCredentialsIfNeeded(for error: Error) async -> Bool {
        guard !didResetCommunityCredentials, Self.isInvalidMembershipSecret(error) else {
            return false
        }
        didResetCommunityCredentials = true

        let oldParticipantId = settings.communityParticipantId
        let oldSecret = settings.communityMembershipSecret
        settings.resetCommunityCredentials()

        if let oldParticipantId, let oldSecret {
            try? await client.deleteParticipant(
                participantId: oldParticipantId,
                membershipSecret: oldSecret
            )
        }

        CommunityRankCache.clear()
        rank = nil
        rankIsStale = false
        lastUploadAt = nil
        return true
    }

    private static func isInvalidMembershipSecret(_ error: Error) -> Bool {
        guard let communityError = error as? CommunityError else { return false }
        switch communityError {
        case .invalidMembershipSecret:
            return true
        case .apiMessage(let message):
            return message == "Invalid membership secret"
        default:
            return false
        }
    }

    private func restoreCachedRankIfAvailable(for window: CommunityRankWindow? = nil) {
        let window = window ?? selectedWindow
        guard let participantId = settings.communityParticipantId,
              let cached = CommunityRankCache.load(participantId: participantId, window: window),
              cached.rank.rankWindow == window else {
            rank = nil
            rankIsStale = false
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

        let membershipSecret = settings.ensureCommunityMembershipSecret()
        let now = Date()
        return CommunityPayloadBuilder.build(
            participantId: participantId,
            membershipSecret: membershipSecret,
            nickname: nickname,
            previousNickname: settings.communityPendingPreviousNickname,
            previousParticipantId: settings.communitySupersededParticipantId,
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
            dailySkills: { [self] day in
                usageStore?.communityDailySkills[day] ?? []
            },
            nicknameSource: "cursor",
            clientConfig: settings.communityClientConfig(),
            clientVersion: AppIdentity.versionLabel
        )
    }
}

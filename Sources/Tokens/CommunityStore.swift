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
        normalizeNicknameSource()
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

    /// Keeps the stored nickname source consistent with what's available locally.
    private func normalizeNicknameSource() {
        refreshCursorDisplayName()

        guard settings.communityNicknameSource == .cursor, cursorDisplayName == nil else { return }

        settings.communityNicknameSource = .random
        if settings.communityNickname == nil {
            settings.communityNickname = NicknameGenerator.random()
        }
    }

    /// One-time upgrade: move users still on the old random default to their Cursor name.
    func migrateNicknameToCursorDefaultIfNeeded() async {
        if settings.communityPendingPreviousNickname != nil {
            await reconcilePendingNicknameIfNeeded()
            return
        }

        guard !settings.communityNicknameMigratedToCursorDefault else { return }

        refreshCursorDisplayName()
        guard settings.communityNicknameSource == .random,
              cursorDisplayName != nil else {
            settings.communityNicknameMigratedToCursorDefault = true
            return
        }

        applyCursorNicknameLocally(previousRandomNickname: settings.communityNickname)

        if settings.shareCommunityUsage {
            await reconcilePendingNicknameIfNeeded()
        } else {
            settings.communityNicknameMigratedToCursorDefault = true
        }
    }

    func enableSharing() async {
        refreshCursorDisplayName()
        normalizeNicknameSource()
        if settings.communityNicknameSource == .random,
           settings.communityNickname == nil {
            settings.communityNickname = NicknameGenerator.random()
        }
        let participantId = settings.ensureCommunityParticipantId()
        settings.shareCommunityUsage = true
        lastUploadAt = nil
        await uploadSnapshot(participantId: participantId, force: true)
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

    func useCursorName() {
        refreshCursorDisplayName()
        rememberPreviousNicknameForReconciliation(from: settings.communityNicknameSource)
        settings.communityNicknameSource = .cursor
        uploadIfSharing()
    }

    func shuffleNickname() {
        settings.communityNicknameSource = .random
        settings.communityNickname = NicknameGenerator.random()
        settings.communityPendingPreviousNickname = nil
        uploadIfSharing()
    }

    func useAnonymous() {
        settings.communityNicknameSource = .anonymous
        settings.communityNickname = nil
        settings.communityPendingPreviousNickname = nil
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
        await migrateNicknameToCursorDefaultIfNeeded()
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
        _ = await uploadSnapshot(participantId: participantId, force: force)
    }

    @discardableResult
    private func uploadSnapshot(participantId: String, force: Bool) async -> Bool {
        if !force, let lastUploadAt, Date().timeIntervalSince(lastUploadAt) < uploadThrottle {
            return false
        }

        do {
            let payload = try buildSnapshotPayload(participantId: participantId)
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
              let participantId = settings.communityParticipantId else { return }

        let reconciled = await uploadSnapshot(participantId: participantId, force: true)
        if reconciled {
            await refreshRank()
        }
    }

    private func applyCursorNicknameLocally(previousRandomNickname: String?) {
        settings.communityNicknameSource = .cursor
        if let previous = normalizedNickname(previousRandomNickname) {
            settings.communityPendingPreviousNickname = previous
        }
        settings.communityNickname = nil
    }

    private func rememberPreviousNicknameForReconciliation(from source: CommunityNicknameSource) {
        guard source == .random else { return }
        if let previous = normalizedNickname(settings.communityNickname) {
            settings.communityPendingPreviousNickname = previous
        }
    }

    private func clearPendingNicknameReconciliation() {
        settings.communityPendingPreviousNickname = nil
        settings.communityNicknameMigratedToCursorDefault = true
    }

    private func normalizedNickname(_ value: String?) -> String? {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? nil : trimmed
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
            return normalizedNickname(settings.communityNickname)
        case .anonymous:
            return nil
        }
    }

    private func buildSnapshotPayload(participantId: String) throws -> CommunitySnapshotPayload {
        let events = usageStore?.communityAnalyticsEvents ?? []
        guard !events.isEmpty else {
            throw CommunityError.apiMessage("No recent usage data to share yet.")
        }

        let now = Date()
        return CommunityPayloadBuilder.build(
            participantId: participantId,
            nickname: resolvedUploadNickname(),
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
            nicknameSource: settings.communityNicknameSource.rawValue,
            clientConfig: settings.communityClientConfig(),
            clientVersion: AppIdentity.versionLabel
        )
    }
}

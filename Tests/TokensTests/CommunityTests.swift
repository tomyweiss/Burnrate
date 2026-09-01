import Foundation
import Testing
@testable import TokensCore

@Test func displayTextStripsNerdFontGlyphs() {
    let apple = String(UnicodeScalar(0xF8FF)!)
    let powerline = String(UnicodeScalar(0xE0B0)!)
    let raw = "\(apple) \(powerline) ~/wo/tokens on main bash scripts/release.sh --yes"
    let cleaned = DisplayText.sanitize(raw, collapseWhitespace: true)
    #expect(!cleaned.contains("?"))
    #expect(cleaned == "~/wo/tokens on main bash scripts/release.sh --yes")
}

@Test func communityModelLabelUsesPrefixForLongNames() {
    #expect(CommunityModelLabel.leaderboard("cursor-grok-4.6-high") == "cursor-grok-4.6-high")
    #expect(CommunityModelLabel.leaderboard("claude-sonnet-4-20250514-thinking") == "sonnet-4-20250514…")
    #expect(CommunityModelLabel.leaderboard("claude-opus-4") == "opus-4")
    #expect(CommunityModelLabel.leaderboard("  gpt-4.1-long-variant-name  ") == "gpt-4.1-long…")
}

@Test func nicknameGeneratorFormat() {
    let nickname = NicknameGenerator.random()
    #expect(nickname.contains("-"))
    #expect(NicknameGenerator.isValidFormat(nickname))
}

@Test func competitionRankTies() {
    let values = [100, 80, 80, 50]
    let ranks = CompetitionRank.ranks(spendCentsDescending: values)
    #expect(ranks == [1, 2, 2, 4])
}

@Test func competitionRankSingle() {
    let ranks = CompetitionRank.ranks(spendCentsDescending: [42])
    #expect(ranks == [1])
}

@Test func competitionRankOfParticipant() {
    let all = [100, 80, 80, 50]
    #expect(CompetitionRank.rank(of: 80, among: all) == 2)
    #expect(CompetitionRank.rank(of: 50, among: all) == 4)
}

@Test func eventFetchStartExpandsTodayWindow() {
    let now = Date(timeIntervalSince1970: 1_700_010_000)
    let todayStart = Calendar.current.startOfDay(for: now)
    let fetchStart = CommunityPayloadBuilder.eventFetchStart(displayWindowStart: todayStart, now: now)
    let rollingStart = now.addingTimeInterval(-48 * 3600)
    #expect(fetchStart == rollingStart)
}

@Test func eventFetchStartKeepsLongerWindows() {
    let now = Date(timeIntervalSince1970: 1_700_010_000)
    let weekStart = now.addingTimeInterval(-7 * 24 * 3600)
    let fetchStart = CommunityPayloadBuilder.eventFetchStart(displayWindowStart: weekStart, now: now)
    #expect(fetchStart == weekStart)
}

@Test func payloadBuilderRolling24h() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let start = now.addingTimeInterval(-12 * 3600)
    let old = now.addingTimeInterval(-30 * 3600)

    let events = [
        CommunityCostEvent(timestampMs: start.timeIntervalSince1970 * 1000, model: "claude-4-sonnet", costCents: 800),
        CommunityCostEvent(timestampMs: start.timeIntervalSince1970 * 1000 + 1000, model: "gpt-4.1", costCents: 440),
        CommunityCostEvent(timestampMs: old.timeIntervalSince1970 * 1000, model: "claude-4-sonnet", costCents: 9999)
    ]

    let payload = CommunityPayloadBuilder.build(
        participantId: "test-uuid",
        membershipSecret: String(repeating: "s", count: 32),
        nickname: "cobalt-fox",
        events: events,
        now: now
    )

    #expect(payload.participantId == "test-uuid")
    #expect(payload.nickname == "cobalt-fox")
    #expect(payload.windowHours == 24)
    #expect(payload.spendCents == 1240)
    #expect(payload.models.count == 2)
    #expect(payload.models[0].name == "claude-4-sonnet")
    #expect(payload.models[0].spendCents == 800)
}

@Test func payloadBuilderExcludesSessionFields() {
    // CommunityCostEvent has no session/prompt fields by design.
    let event = CommunityCostEvent(timestampMs: 1_700_000_000_000, model: "m", costCents: 1)
    #expect(event.model == "m")
    #expect(event.costCents == 1)
}

@Test func interactionStatsRecordPanelOpenAndTabChange() {
    var stats = CommunityInteractionStats()
    stats.recordPanelOpen()
    stats.recordPanelOpen()
    stats.recordTabChange("models")
    stats.recordTabChange("models")
    stats.recordTabChange("feed")

    #expect(stats.panelOpens == 2)
    #expect(stats.tabChanges["models"] == 2)
    #expect(stats.tabChanges["feed"] == 1)
}

@Test func payloadBuilderIncludesInteractionStats() {
    let stats = CommunityInteractionStats(panelOpens: 3, tabChanges: ["sessions": 5])
    let payload = CommunityPayloadBuilder.build(
        participantId: "test-uuid",
        membershipSecret: String(repeating: "s", count: 32),
        nickname: nil,
        events: [],
        interactionStats: stats
    )
    #expect(payload.interactionStats == stats)
}

@Test func cursorDisplayNameParsesScopedProfile() {
    let json = #"{"displayName":"Tom Weiss","pictureUrl":"https://example.com/x"}"#
    #expect(CursorDisplayName.parseScopedProfileJSON(json) == "Tom Weiss")
}

@Test func cursorDisplayNameSanitizeRejectsEmpty() {
    #expect(CursorDisplayName.sanitize("  ") == nil)
    #expect(CursorDisplayName.sanitize("Ada") == "Ada")
}

@Test func payloadBuilderIncludesPreviousNickname() {
    let payload = CommunityPayloadBuilder.build(
        participantId: "test-uuid",
        membershipSecret: String(repeating: "s", count: 32),
        nickname: "Tom Weiss",
        previousNickname: "cobalt-fox",
        events: []
    )
    #expect(payload.previousNickname == "cobalt-fox")
    #expect(payload.nickname == "Tom Weiss")
}

@Test func payloadBuilderIncludesClientVersion() {
    let payload = CommunityPayloadBuilder.build(
        participantId: "test-uuid",
        membershipSecret: String(repeating: "s", count: 32),
        nickname: nil,
        events: [],
        clientVersion: "0.0.25-dev"
    )
    #expect(payload.clientVersion == "0.0.25-dev")
}

@Test func communityRankWindowStepsWithinLookback() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let today = CommunityRankWindow.todayUTC(now: now)
    #expect(today.shiftedDays(by: 1, now: now) == nil)
    #expect(today.shiftedDays(by: -1, now: now)?.day == CommunityRankWindow.yesterdayUTC(now: now).day)
    #expect(CommunityRankWindow.rolling24h.apiDayParameter == nil)
    #expect(today.apiDayParameter == CommunityDayFormat.utcDayString(for: now))
}

@Test func communityRankResponseDefaultsMissingWindowFields() throws {
    let json = """
    {
      "participantCount": 3,
      "rank": 2,
      "yourSpendCents": 80,
      "medianSpendCents": 70,
      "p25SpendCents": 50,
      "p75SpendCents": 90,
      "maxSpendCents": 100,
      "leaderboardNear": [],
      "notEnoughParticipants": false
    }
  """.data(using: .utf8)!
    let response = try JSONDecoder().decode(CommunityRankResponse.self, from: json)
    #expect(response.window == "rolling24h")
    #expect(response.day == nil)
    #expect(response.isProvisional == false)
    #expect(response.rankWindow == .rolling24h)
}

@Test func payloadBuilderDailyReportsIncludeTodayAndYesterday() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let today = CommunityDayFormat.utcDayString(for: now)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let yesterdayDate = calendar.date(byAdding: .day, value: -1, to: now)!
    let yesterday = CommunityDayFormat.utcDayString(for: yesterdayDate)

    let dayStart = CommunityDayFormat.utcDayStartMs(for: today)!
    let events = [
        CommunityAnalyticsEvent(
            timestampMs: dayStart + 3_600_000,
            model: "claude-4-sonnet",
            costCents: 500,
            billingKind: .usageBased,
            tokenInput: 1000,
            tokenOutput: 200,
            tokenCacheRead: 50,
            tokenCacheWrite: 10
        ),
    ]
    let config = CommunityClientConfig(
        timelinePreset: "today",
        refreshIntervalSeconds: 60,
        anomalyThresholdDollars: 10,
        anomalyWindowMinutes: 10,
        hideAmountInMenuBar: false,
        autoCheckForUpdates: true,
        launchAtLogin: false,
        hiddenTabs: ["bench"],
        customTimezone: false,
        billingDayOfMonth: 1
    )

    let payload = CommunityPayloadBuilder.build(
        participantId: "test-uuid",
        membershipSecret: String(repeating: "s", count: 32),
        nickname: "Ada",
        events: events,
        now: now,
        dailyEngagement: { _ in
            CommunityPayloadBuilder.DailyEngagement(panelOpens: 2, tabChanges: ["models": 1])
        },
        nicknameSource: "cursor",
        clientConfig: config
    )

    #expect(payload.dailyReports?.count == 2)
    #expect(payload.dailyReports?.map(\.day).contains(today) == true)
    #expect(payload.dailyReports?.map(\.day).contains(yesterday) == true)
    let todayReport = payload.dailyReports?.first { $0.day == today }
    #expect(todayReport?.spendCents == 500)
    #expect(todayReport?.panelOpens == 2)
    #expect(todayReport?.regionBucket == CommunityDayFormat.regionBucket(now: now))
}

@Test func communitySkillCapNormalizesAndMergesDuplicates() {
    let capped = CommunitySkillCap.cap([
        (name: "/Cmd-Fast-PR", invocationCount: 2, spendCents: 100),
        (name: "cmd-fast-pr", invocationCount: 1, spendCents: 50),
    ])
    #expect(capped.count == 1)
    #expect(capped[0].name == "cmd-fast-pr")
    #expect(capped[0].invocationCount == 3)
    #expect(capped[0].spendCents == 150)
}

@Test func communitySkillCapFoldsOverflowIntoOther() {
    let skills = (0..<(CommunitySkillCap.maxSkills + 3)).map { index in
        (name: "skill-\(index)", invocationCount: 1, spendCents: CommunitySkillCap.maxSkills + 3 - index)
    }
    let capped = CommunitySkillCap.cap(skills)
    #expect(capped.count == CommunitySkillCap.maxSkills + 1)
    let other = capped.first { $0.name == CommunitySkillCap.otherBucketName }
    #expect(other?.invocationCount == 3)
    #expect(other?.spendCents == 6)
}

@Test func payloadBuilderOmitsSkillsWithoutDailySkillsCallback() {
    let payload = CommunityPayloadBuilder.build(
        participantId: "test-uuid",
        membershipSecret: String(repeating: "s", count: 32),
        nickname: nil,
        events: []
    )
    #expect(payload.dailyReports?.allSatisfy { $0.skills == nil } == true)
}

@Test func payloadBuilderIncludesDailySkillsWhenProvided() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let today = CommunityDayFormat.utcDayString(for: now)
    let config = CommunityClientConfig(
        timelinePreset: "today",
        refreshIntervalSeconds: 60,
        anomalyThresholdDollars: 10,
        anomalyWindowMinutes: 10,
        hideAmountInMenuBar: false,
        autoCheckForUpdates: true,
        launchAtLogin: false,
        hiddenTabs: [],
        customTimezone: false,
        billingDayOfMonth: 1
    )
    let payload = CommunityPayloadBuilder.build(
        participantId: "test-uuid",
        membershipSecret: String(repeating: "s", count: 32),
        nickname: nil,
        events: [],
        now: now,
        dailySkills: { day in
            guard day == today else { return [] }
            return [CommunitySkillSpend(name: "cmd-fast-pr", invocationCount: 4, spendCents: 900)]
        },
        nicknameSource: "cursor",
        clientConfig: config
    )
    let todayReport = payload.dailyReports?.first { $0.day == today }
    #expect(todayReport?.skills == [
        CommunitySkillSpend(name: "cmd-fast-pr", invocationCount: 4, spendCents: 900),
    ])
}

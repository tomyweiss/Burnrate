import Foundation
import Testing
@testable import TokensCore

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

@Test func payloadBuilderIncludesClientVersion() {
    let payload = CommunityPayloadBuilder.build(
        participantId: "test-uuid",
        nickname: nil,
        events: [],
        clientVersion: "0.0.25-dev"
    )
    #expect(payload.clientVersion == "0.0.25-dev")
}

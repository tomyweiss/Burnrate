import Foundation
import Testing
@testable import TokensCore

@Test func cursorPromptHeadlineUsesUserQueryNotTimestampTag() {
    let raw = """
    <timestamp>Thursday, Aug 6, 2026, 7:25 PM (UTC+3)</timestamp>
    <user_query>
    push and open pr
    </user_query>
    """
    #expect(CursorPromptText.headline(raw) == "push and open pr")
    #expect(CursorPromptText.visible(raw) == "push and open pr")
}

@Test func cursorPromptHeadlineStripsBareTimestampTag() {
    let raw = "<timestamp>Thursday, Aug 6, 2026, 7:25 PM (UTC+3)</timestamp>\nfix ci"
    #expect(CursorPromptText.headline(raw) == "fix ci")
}

@Test func cursorPromptKeepsPlainUserText() {
    #expect(CursorPromptText.headline("fix ci") == "fix ci")
    #expect(CursorPromptText.isSynthetic(text: "fix ci", isSimulated: false) == false)
}

@Test func cursorPromptDetectsTaskFinishedSyntheticBubble() {
    let raw = """
    <timestamp>Thursday, Aug 6, 2026, 7:25 PM (UTC+3)</timestamp>
    <system_notification>
    The following task has finished.
    <task>
    title: Sample prod usage and silo Bedrock metrics
    </task>
    </system_notification>
    <user_query>Briefly inform the user about the task result and perform any follow-up actions (if needed).</user_query>
    """
    #expect(CursorPromptText.isSynthetic(text: raw, isSimulated: false))
    #expect(CursorPromptText.isSynthetic(text: "hello", isSimulated: true))
}

@Test func cursorPromptParsesTimestampTagToUtc() throws {
    let raw = "<timestamp>Thursday, Aug 6, 2026, 7:25 PM (UTC+3)</timestamp>"
    let ms = try #require(CursorPromptText.timestampMs(in: raw))
    let date = Date(timeIntervalSince1970: ms / 1000)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let parts = calendar.dateComponents([.year, .month, .day, .hour, .minute], from: date)
    #expect(parts.year == 2026)
    #expect(parts.month == 8)
    #expect(parts.day == 6)
    #expect(parts.hour == 16)
    #expect(parts.minute == 25)
}

@Test func cursorPromptResolvedCreatedAtPrefersJsonThenTimestampTag() {
    let text = "<timestamp>Thursday, Aug 6, 2026, 7:25 PM (UTC+3)</timestamp>"
    let fromJson = CursorPromptText.resolvedCreatedAtMs(
        createdAt: "2026-08-24T14:03:15.137Z",
        text: text
    )
    #expect(fromJson != nil)
    #expect(abs((fromJson ?? 0) - 1_787_580_195_137) < 1)

    let fromTag = CursorPromptText.resolvedCreatedAtMs(createdAt: "", text: text)
    #expect(fromTag != nil)
    #expect(CursorPromptText.resolvedCreatedAtMs(createdAt: nil, text: "plain") == nil)
    #expect(CursorPromptText.resolvedCreatedAtMs(createdAt: "1000", text: "plain") == 1000)
}

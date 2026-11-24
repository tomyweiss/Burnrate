import Foundation
import Testing
@testable import Tokens

@Test func cursorBucketsKeepPlaceholdersUntilPoolsLoad() {
    let meters = CursorBucketMeters.make(pools: nil, grokBot: nil)

    #expect(meters.map(\.title) == ["Cursor models", "Other models"])
    #expect(meters.map(\.percent) == [nil, nil])
    #expect(meters.map(\.detail) == [nil, nil])
}

@Test func cursorBucketsDropOtherModelsWhenThePeriodHasNoSuchBucket() {
    let pools = IncludedPools(cursorModelsPercent: 11, otherModelsPercent: nil, hasOtherModelsBucket: false)

    let meters = CursorBucketMeters.make(pools: pools, grokBot: nil)

    #expect(meters.map(\.title) == ["Cursor models"])
    #expect(meters.map(\.percent) == [11])
}

@Test func cursorBucketsAddGrokBotWithItsReset() {
    let pools = IncludedPools(cursorModelsPercent: 11, otherModelsPercent: 36, hasOtherModelsBucket: true)
    let utc = TimeZone(secondsFromGMT: 0)!
    // 2026-11-23 12:00 UTC
    let grok = GrokBotUsage(percentUsed: 12, resetsAt: Date(timeIntervalSince1970: 1_795_435_200))

    let meters = CursorBucketMeters.make(pools: pools, grokBot: grok, timeZone: utc)

    #expect(meters.map(\.title) == ["Cursor models", "Other models", "Grok Bot"])
    #expect(meters.map(\.percent) == [11, 36, 12])
    #expect(meters.map(\.detail) == [nil, nil, "resets Nov 23"])

    let noReset = CursorBucketMeters.make(
        pools: pools,
        grokBot: GrokBotUsage(percentUsed: 12, resetsAt: nil),
        timeZone: utc
    )
    #expect(noReset.last?.detail == nil)
}

@Test func bucketMeterSpeaksPercentAndReset() {
    #expect(
        BucketMeter(title: "Grok Bot", percent: 12.4, detail: "resets Nov 23").accessibilityLabel
            == "Grok Bot, 12 percent used, resets Nov 23"
    )
    #expect(
        BucketMeter(title: "Cursor models", percent: 0.4, detail: nil).accessibilityLabel
            == "Cursor models, 1 percent used"
    )
    #expect(
        BucketMeter(title: "5h limit", percent: nil, detail: nil).accessibilityLabel
            == "5h limit, not loaded"
    )
}

@Test func claudeLimitPlaceholdersAreTheTwoPlanWindows() {
    #expect(ClaudeLimitGauges.placeholders.map(\.title) == ["5h limit", "Weekly limit"])
    #expect(ClaudeLimitGauges.placeholders.map(\.percent) == [nil, nil])
}

@Test func claudeLimitNoteShowsSignInProblemsAndFailuresWithNothingToShow() {
    #expect(ClaudeLimitGauges.note(error: nil, hasLimits: false) == nil)
    #expect(ClaudeLimitGauges.note(error: ClaudeLimitsClient.unavailable, hasLimits: true) == nil)
    #expect(
        ClaudeLimitGauges.note(error: ClaudeLimitsClient.unavailable, hasLimits: false)
            == ClaudeLimitsClient.unavailable
    )
    #expect(
        ClaudeLimitGauges.note(error: ClaudeLimitsClient.noLogin, hasLimits: true)
            == ClaudeLimitsClient.noLogin
    )
}

@Test func bucketRowsReserveTheirStackedHeight() {
    #expect(BucketLayout.metersHeight(rows: 0) == 0)
    #expect(BucketLayout.metersHeight(rows: 1) == BucketLayout.rowHeight)
    #expect(
        BucketLayout.metersHeight(rows: 3)
            == 3 * BucketLayout.rowHeight + 2 * BucketLayout.rowSpacing
    )
}

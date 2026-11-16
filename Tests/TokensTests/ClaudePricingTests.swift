import Foundation
import Testing
@testable import TokensCore

@Test func claudePricingCostsAKnownModelAtListRates() throws {
    let price = try #require(ClaudePricing.price(for: "claude-opus-5-5"))
    #expect(price.inputPerMTok == 4)
    #expect(price.outputPerMTok == 20)
    #expect(price.cacheWritePerMTok == 5)
    #expect(price.cacheWrite1hPerMTok == 8)
    #expect(price.cacheReadPerMTok == 0.2)

    let record = claudeUsage(
        model: "claude-opus-5-5",
        input: 500_000,
        output: 100_000,
        cacheWrite: 200_000,
        cacheRead: 1_000_000
    )
    let cache5m = record.cacheCreationTokens - record.cacheCreation1hTokens
    let dollars = (
        Double(record.inputTokens) * price.inputPerMTok
            + Double(record.outputTokens) * price.outputPerMTok
            + Double(cache5m) * price.cacheWritePerMTok
            + Double(record.cacheCreation1hTokens) * price.cacheWrite1hPerMTok
            + Double(record.cacheReadTokens) * price.cacheReadPerMTok
    ) / 1_000_000
    let cents = try #require(ClaudePricing.costCents(for: record))
    #expect(abs(cents - dollars * 100) < 0.000_001)
    #expect(abs(cents - 520) < 0.000_001)
}

@Test func claudePricingCostsFiveMinuteAndOneHourCacheWritesSeparately() throws {
    let price = try #require(ClaudePricing.price(for: "claude-opus-5-5"))
    let record = claudeUsage(
        model: "claude-opus-5-5",
        input: 0,
        output: 0,
        cacheWrite: 1_000_000,
        cacheWrite1h: 400_000
    )
    let cache5m = record.cacheCreationTokens - record.cacheCreation1hTokens
    let dollars = (
        Double(cache5m) * price.cacheWritePerMTok
            + Double(record.cacheCreation1hTokens) * price.cacheWrite1hPerMTok
    ) / 1_000_000
    let cents = try #require(ClaudePricing.costCents(for: record))
    #expect(record.cacheCreation1hTokens == 400_000)
    #expect(abs(cents - dollars * 100) < 0.000_001)
    // 600k at $5 plus 400k at $8.
    #expect(abs(cents - 620) < 0.000_001)
}

@Test func claudePricingClampsOneHourCacheTokensIntoTheCreationTotal() throws {
    let price = try #require(ClaudePricing.price(for: "claude-opus-5-5"))
    let over = claudeUsage(
        model: "claude-opus-5-5",
        input: 0,
        output: 0,
        cacheWrite: 1_000_000,
        cacheWrite1h: 1_400_000
    )
    let overCents = try #require(ClaudePricing.costCents(for: over))
    #expect(abs(overCents - price.cacheWrite1hPerMTok * 100) < 0.000_001)

    let negative = claudeUsage(
        model: "claude-opus-5-5",
        input: 0,
        output: 0,
        cacheWrite: 1_000_000,
        cacheWrite1h: -50_000
    )
    let negativeCents = try #require(ClaudePricing.costCents(for: negative))
    #expect(abs(negativeCents - price.cacheWritePerMTok * 100) < 0.000_001)
}

@Test func claudePricingResolvesADatedModelSuffix() throws {
    let dated = try #require(ClaudePricing.price(for: "claude-haiku-4-5-20251001"))
    let bare = try #require(ClaudePricing.price(for: "claude-haiku-4-5"))
    #expect(dated == bare)
    #expect(bare.inputPerMTok == 1)
    #expect(bare.outputPerMTok == 5)
    #expect(bare.cacheWritePerMTok == 1.25)
    #expect(bare.cacheWrite1hPerMTok == 2)
    #expect(bare.cacheReadPerMTok == 0.1)
}

@Test func claudePricingResolvesFamilyAliases() throws {
    #expect(ClaudePricing.price(for: "opus") == ClaudePricing.price(for: "claude-opus-5-5"))
    #expect(ClaudePricing.price(for: "sonnet") == ClaudePricing.price(for: "claude-sonnet-5-5"))
    #expect(ClaudePricing.price(for: "haiku") == ClaudePricing.price(for: "claude-haiku-5-5"))

    let fable = try #require(ClaudePricing.price(for: "fable"))
    #expect(fable == ClaudePricing.price(for: "claude-fable-5-2"))
    #expect(fable.inputPerMTok == 8)
    #expect(fable.outputPerMTok == 40)
    #expect(fable.cacheWritePerMTok == 10)
    #expect(fable.cacheWrite1hPerMTok == 16)
    #expect(fable.cacheReadPerMTok == 0.2)

    let sonnet = try #require(ClaudePricing.price(for: "claude-sonnet-5-5"))
    #expect(sonnet.inputPerMTok == 2)
    #expect(sonnet.outputPerMTok == 10)
    #expect(sonnet.cacheWritePerMTok == 2.5)
    #expect(sonnet.cacheWrite1hPerMTok == 4)
    #expect(sonnet.cacheReadPerMTok == 0.1)
}

@Test func claudePricingDoesNotConfuseOpus5WithOpus55() throws {
    let opus5 = try #require(ClaudePricing.price(for: "claude-opus-5"))
    let opus55 = try #require(ClaudePricing.price(for: "claude-opus-5-5"))
    #expect(opus5 != opus55)
    #expect(opus5.inputPerMTok == 5)
    #expect(opus5.outputPerMTok == 25)
    #expect(opus5.cacheWritePerMTok == 6.25)
    #expect(opus5.cacheWrite1hPerMTok == 10)
    #expect(opus5.cacheReadPerMTok == 0.5)

    let sonnet5 = try #require(ClaudePricing.price(for: "claude-sonnet-5"))
    #expect(sonnet5 != ClaudePricing.price(for: "claude-sonnet-5-5"))
    #expect(sonnet5.inputPerMTok == 2)
    #expect(sonnet5.outputPerMTok == 10)
    #expect(sonnet5.cacheWritePerMTok == 2.5)
    #expect(sonnet5.cacheWrite1hPerMTok == 4)
    #expect(sonnet5.cacheReadPerMTok == 0.2)
}

@Test func claudePricingUsesTheHaiku55RateForPromptsUpTo100kTokens() throws {
    let haiku = try #require(ClaudePricing.price(for: "claude-haiku-5-5"))
    #expect(haiku.inputPerMTok == 0.1)
    #expect(haiku.outputPerMTok == 0.5)
    #expect(haiku.cacheWritePerMTok == 0.125)
    #expect(haiku.cacheWrite1hPerMTok == 0.2)
    #expect(haiku.cacheReadPerMTok == 0.01)
}

@Test func claudePricingReturnsNilCostForAnUnknownModel() {
    #expect(ClaudePricing.price(for: "claude-not-a-model") == nil)
    #expect(ClaudePricing.costCents(for: claudeUsage(model: "claude-not-a-model")) == nil)
}

private func claudeUsage(
    model: String,
    input: Int = 10,
    output: Int = 4,
    cacheWrite: Int = 0,
    cacheWrite1h: Int = 0,
    cacheRead: Int = 0
) -> ClaudeUsageRecord {
    ClaudeUsageRecord(
        messageId: "msg_1",
        timestampMs: 0,
        sessionId: "sess-1",
        model: model,
        inputTokens: input,
        outputTokens: output,
        cacheCreationTokens: cacheWrite,
        cacheCreation1hTokens: cacheWrite1h,
        cacheReadTokens: cacheRead,
        isSidechain: false,
        cwd: nil,
        gitBranch: nil
    )
}

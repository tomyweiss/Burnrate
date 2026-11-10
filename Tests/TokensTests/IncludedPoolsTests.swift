import Foundation
import Testing
@testable import Tokens

private func parseUsageSummary(_ json: String) -> IncludedPools? {
    let data = Data(json.utf8)
    let object = try? JSONSerialization.jsonObject(with: data)
    return (object as? [String: Any]).flatMap(IncludedPools.parse(json:))
}

@Test func includedPoolsReadsPlanPercentages() {
    let pools = parseUsageSummary("""
    {
      "membershipType": "ultra",
      "isUnlimited": false,
      "individualUsage": {
        "plan": {
          "enabled": true,
          "used": 40000,
          "limit": 40000,
          "remaining": 0,
          "autoPercentUsed": 98.109,
          "apiPercentUsed": 100,
          "totalPercentUsed": 98.5128
        }
      }
    }
    """)

    #expect(pools?.cursorModelsPercent == 98.109)
    #expect(pools?.otherModelsPercent == 100)
    #expect(pools?.hasOtherModelsBucket == true)
    #expect(IncludedPools.displayPercent(98.109) == 98)
    #expect(IncludedPools.displayPercent(98.5128) == 99)
    #expect(IncludedPools.displayPercent(0) == 0)
    #expect(IncludedPools.displayPercent(0.1299) == 1)
    #expect(IncludedPools.displayPercent(0.99) == 1)
}

@Test func includedPoolsTreatsOmittedPercentageAsZero() {
    let pools = parseUsageSummary("""
    {
      "individualUsage": {
        "plan": { "enabled": true, "apiPercentUsed": 3 }
      }
    }
    """)

    #expect(pools?.cursorModelsPercent == 0)
    #expect(pools?.otherModelsPercent == 3)
}

@Test func includedPoolsKeepsUsagePastTheAllowance() {
    let pools = parseUsageSummary("""
    {
      "individualUsage": {
        "plan": { "autoPercentUsed": 142.7, "apiPercentUsed": 5, "totalPercentUsed": 80 }
      }
    }
    """)

    #expect(pools?.cursorModelsPercent == 142.7)
    #expect(IncludedPools.displayPercent(142.7) == 143)
}

@Test func includedPoolsHidesUnlimitedPlans() {
    let pools = parseUsageSummary("""
    {
      "isUnlimited": true,
      "individualUsage": {
        "plan": { "autoPercentUsed": 10, "apiPercentUsed": 10, "totalPercentUsed": 10 }
      }
    }
    """)

    #expect(pools == nil)
}

@Test func includedPoolsFallsBackToBothDisplayMessages() {
    let pools = parseUsageSummary("""
    {
      "membershipType": "team",
      "autoModelSelectedDisplayMessage": "You've used 42% of your included total usage",
      "namedModelSelectedDisplayMessage": "You've used 7.5% of your included API usage"
    }
    """)

    #expect(pools?.cursorModelsPercent == 42)
    #expect(pools?.otherModelsPercent == 7.5)
}

@Test func includedPoolsIgnoresASingleDisplayMessage() {
    let pools = parseUsageSummary("""
    {
      "autoModelSelectedDisplayMessage": "You've used 42% of your included total usage"
    }
    """)

    #expect(pools == nil)
}

@Test func cycleSpendReadsIndividualOnDemandAndIncludedBreakdown() {
    let spend = parseCycleSpend("""
    {
      "individualUsage": {
        "plan": {
          "breakdown": { "included": 2000, "bonus": 57810, "total": 59810 }
        },
        "onDemand": { "enabled": true, "used": 22886, "limit": null }
      },
      "teamUsage": {
        "onDemand": { "enabled": true, "used": 1207692, "limit": 5000000 }
      }
    }
    """)

    #expect(spend?.onDemandCents == 22886)
    #expect(spend?.includedCents == 59810)
}

@Test func cycleSpendFallsBackToTeamOnDemand() {
    let spend = parseCycleSpend("""
    {
      "teamUsage": { "onDemand": { "enabled": true, "used": 1500 } }
    }
    """)

    #expect(spend?.onDemandCents == 1500)
    #expect(spend?.includedCents == 0)
}

@Test func cycleSpendIgnoresPayloadsWithNoMoney() {
    #expect(parseCycleSpend("{}") == nil)
}

private func parseCycleSpend(_ json: String) -> CycleSpend? {
    let data = Data(json.utf8)
    let object = try? JSONSerialization.jsonObject(with: data)
    return (object as? [String: Any]).flatMap(CycleSpend.parse(json:))
}

@Test func spendSplitSharesTheTotalBetweenIncludedAndOnDemand() {
    let split = SpendSplit(includedCents: 63489, onDemandCents: 24174)

    #expect(split.totalCents == 87663)
    #expect(abs(split.includedFraction - 0.7242) < 0.001)
    #expect(abs(split.onDemandFraction - 0.2758) < 0.001)
    #expect(abs(split.includedFraction + split.onDemandFraction - 1) < 0.0001)
}

@Test func spendSplitIsEmptyWithoutSpend() {
    let split = SpendSplit(includedCents: 0, onDemandCents: 0)

    #expect(split.includedFraction == 0)
    #expect(split.onDemandFraction == 0)
}

@Test func spendSplitFillsTheBarWhenOnlyOneSideHasSpend() {
    let included = SpendSplit(includedCents: 500, onDemandCents: 0)
    let onDemand = SpendSplit(includedCents: 0, onDemandCents: 500)

    #expect(included.includedFraction == 1)
    #expect(included.onDemandFraction == 0)
    #expect(onDemand.includedFraction == 0)
    #expect(onDemand.onDemandFraction == 1)
}

@Test func monthlySummaryCountsNamedModelsInsideTheSharedAllowance() {
    // apiPercentUsed stays 0 on this plan, but totalPercentUsed is used/limit
    // and includes named-model spend. Other models is the part of that total
    // that is not the Cursor models pool.
    let pools = parseUsageSummary("""
    {
      "billingCycleStart": "2026-11-01T00:00:00.000Z",
      "billingCycleEnd": "2026-12-01T00:00:00.000Z",
      "membershipType": "enterprise",
      "individualUsage": {
        "plan": {
          "enabled": true,
          "used": 26016,
          "limit": 55395,
          "autoPercentUsed": 10.726599873634804,
          "apiPercentUsed": 0,
          "totalPercentUsed": 46.96452748443
        }
      }
    }
    """)

    #expect(pools?.cursorModelsPercent == 10.726599873634804)
    #expect(pools?.otherModelsPercent == 46.96452748443 - 10.726599873634804)
    #expect(pools?.hasOtherModelsBucket == true)
    #expect(IncludedPools.displayPercent(pools?.cursorModelsPercent ?? -1) == 11)
    #expect(IncludedPools.displayPercent(pools?.otherModelsPercent ?? -1) == 36)
}

@Test func otherModelsKeepsARealApiQuota() {
    #expect(IncludedPools.otherModelsPercent(auto: 98.109, api: 100, total: 98.5128) == 100)
    #expect(IncludedPools.otherModelsPercent(auto: 10, api: 0, total: 10.4) == 0)
}

@Test func includedPoolsIgnoresALimitMessageWithoutAPercent() {
    #expect(IncludedPools.percent(in: "You've hit your usage limit") == nil)
    #expect(parseUsageSummary("{}") == nil)
}

private func parseGrokBot(_ json: String) -> GrokBotUsage? {
    let data = Data(json.utf8)
    let object = try? JSONSerialization.jsonObject(with: data)
    return (object as? [String: Any]).flatMap(GrokBotUsage.parse(json:))
}

@Test func grokBotReadsWeeklyPercentAndReset() {
    let usage = parseGrokBot("""
    {
      "usagePercent": 10.205850487540628,
      "hasNonZeroIncludedLimit": true,
      "hasAvailableUsage": true,
      "includedLimitZero": false,
      "usesPooledEnterpriseAllowance": false,
      "nextResetTimestampUtc": "2026-10-22T10:27:36.178Z",
      "grokPlanLabel": "Grok Bot Plan"
    }
    """)

    #expect(usage?.percentUsed == 10.205850487540628)
    #expect(IncludedPools.displayPercent(10.205850487540628) == 10)
    let utc = TimeZone(secondsFromGMT: 0)!
    #expect(usage?.resetCaption(timeZone: utc) == "Oct 22")
    #expect(usage?.meterCaption(timeZone: utc) == "10% · resets Oct 22")
}

@Test func grokBotSubOnePercentDisplaysAsOne() {
    let usage = parseGrokBot("""
    {
      "usagePercent": 0.12995853703818305,
      "hasNonZeroIncludedLimit": true,
      "nextResetTimestampUtc": "2026-11-16T13:25:51.031Z"
    }
    """)

    #expect(usage?.percentUsed == 0.12995853703818305)
    let utc = TimeZone(secondsFromGMT: 0)!
    #expect(usage?.meterCaption(timeZone: utc) == "1% · resets Nov 16")
}

@Test func grokBotReadsMillisecondReset() {
    let usage = parseGrokBot("""
    {
      "usagePercent": 0,
      "hasNonZeroIncludedLimit": true,
      "nextResetTimestampUtc": 1792664856178
    }
    """)

    #expect(usage?.percentUsed == 0)
    #expect(usage?.meterCaption(timeZone: TimeZone(secondsFromGMT: 0)!) == "0% · resets Oct 22")
}

@Test func grokBotKeepsPercentWhenResetIsMissing() {
    let usage = parseGrokBot("""
    {
      "usagePercent": 42.2,
      "hasNonZeroIncludedLimit": true
    }
    """)

    #expect(usage?.percentUsed == 42.2)
    #expect(usage?.resetsAt == nil)
    #expect(usage?.meterCaption() == "42%")
}

@Test func grokBotHidesAccountsWithoutAnAllowance() {
    #expect(parseGrokBot(#"{"usagePercent": 0, "hasNonZeroIncludedLimit": false}"#) == nil)
    #expect(parseGrokBot(#"{"usagePercent": 12}"#) == nil)
    #expect(parseGrokBot(#"""
    {"usagePercent": 12, "hasNonZeroIncludedLimit": true, "includedLimitZero": true}
    """#) == nil)
    #expect(parseGrokBot(#"""
    {"usagePercent": 12, "hasNonZeroIncludedLimit": true, "usesPooledEnterpriseAllowance": true}
    """#) == nil)
    #expect(parseGrokBot(#"{"hasNonZeroIncludedLimit": true}"#) == nil)
}

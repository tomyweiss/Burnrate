import Foundation
import Testing
import TokensCore
@testable import Tokens

@Test func claudeLimitsParseFullPayload() throws {
    let json: [String: Any] = [
        "five_hour": [
            "utilization": 62.0,
            "resets_at": "2026-11-15T15:40:00Z",
        ],
        "seven_day": [
            "utilization": 34.0,
            "resets_at": "2026-11-20T08:00:00Z",
        ],
        "seven_day_sonnet": [
            "utilization": 99.0,
            "resets_at": "2026-11-20T08:00:00Z",
        ],
        "extra_usage": [
            "is_enabled": true,
            "utilization": 12.5,
        ],
    ]

    let limits = try #require(ClaudeLimits.parse(json: json))
    #expect(limits.fiveHour == ClaudeLimitWindow(
        percentUsed: 62,
        resetsAt: Date(timeIntervalSince1970: 1_794_757_200)
    ))
    #expect(limits.weekly == ClaudeLimitWindow(
        percentUsed: 34,
        resetsAt: Date(timeIntervalSince1970: 1_795_161_600)
    ))
    #expect(limits.weeklySonnet == ClaudeLimitWindow(
        percentUsed: 99,
        resetsAt: Date(timeIntervalSince1970: 1_795_161_600)
    ))
    #expect(limits.weeklyOpus == nil)
    #expect(limits.extraUsage == ClaudeExtraUsage(
        percentUsed: nil,
        usedDollars: nil,
        monthlyLimitDollars: nil
    ))
}

@Test func claudeLimitsParseMissingSevenDayStillParsesOpus() throws {
    let json: [String: Any] = [
        "five_hour": [
            "utilization": 10,
            "resets_at": "2026-11-15T15:40:00Z",
        ],
        "seven_day_opus": [
            "utilization": 80,
            "resets_at": "2026-11-20T08:00:00Z",
        ],
        "seven_day_sonnet": NSNull(),
    ]

    let limits = try #require(ClaudeLimits.parse(json: json))
    #expect(limits.fiveHour?.percentUsed == 10)
    #expect(limits.weekly == nil)
    #expect(limits.weeklySonnet == nil)
    #expect(limits.weeklyOpus == ClaudeLimitWindow(
        percentUsed: 80,
        resetsAt: Date(timeIntervalSince1970: 1_795_161_600)
    ))
}

@Test func claudeLimitsParseFallsBackToTheLimitsList() throws {
    let json: [String: Any] = [
        "five_hour": ["utilization": 3, "resets_at": "2026-11-24T22:59:59Z"],
        "seven_day": NSNull(),
        "limits": [
            ["kind": "session", "percent": 9, "resets_at": "2026-11-24T22:59:59Z"],
            ["kind": "weekly_all", "percent": 12, "resets_at": "2026-11-30T02:59:59Z"],
            ["kind": "weekly_scoped", "percent": 40, "resets_at": "2026-11-30T03:00:00Z"],
        ],
    ]

    let limits = try #require(ClaudeLimits.parse(json: json))
    #expect(limits.fiveHour?.percentUsed == 3)
    #expect(limits.weekly == ClaudeLimitWindow(
        percentUsed: 12,
        resetsAt: Date(timeIntervalSince1970: 1_796_007_599)
    ))
}

@Test func claudeLimitsParseAllBuckets() throws {
    let json: [String: Any] = [
        "five_hour": ["utilization": 62, "resets_at": "2026-11-15T15:40:00Z"],
        "seven_day": ["utilization": 34, "resets_at": "2026-11-20T08:00:00Z"],
        "seven_day_opus": ["utilization": 80, "resets_at": "2026-11-20T08:00:00Z"],
        "seven_day_sonnet": ["utilization": 21, "resets_at": "2026-11-20T08:00:00Z"],
        "seven_day_oauth_apps": ["utilization": 5, "resets_at": "2026-11-20T08:00:00Z"],
        "iguana_necktie": ["utilization": 1, "resets_at": "2026-11-20T08:00:00Z"],
        "extra_usage": [
            "is_enabled": true,
            "monthly_limit": 5000,
            "used_credits": 1240,
            "utilization": 24.8,
        ],
    ]

    let limits = try #require(ClaudeLimits.parse(json: json))
    #expect(limits.weeklyOpus?.percentUsed == 80)
    #expect(limits.weeklySonnet?.percentUsed == 21)
    #expect(limits.extraUsage == ClaudeExtraUsage(
        percentUsed: 24.8,
        usedDollars: 12.4,
        monthlyLimitDollars: 50
    ))
    #expect(limits.extraUsage?.amountDetail == "$12.40 of $50")
}

@Test func claudeLimitsParseExtraUsageDisabledIsNil() throws {
    let json: [String: Any] = [
        "five_hour": ["utilization": 10, "resets_at": NSNull()],
        "extra_usage": [
            "is_enabled": false,
            "monthly_limit": 5000,
            "used_credits": 1240,
            "utilization": 24.8,
        ],
    ]
    let limits = try #require(ClaudeLimits.parse(json: json))
    #expect(limits.extraUsage == nil)

    let onlyDisabled: [String: Any] = [
        "extra_usage": ["is_enabled": false, "monthly_limit": 5000, "used_credits": 1240],
    ]
    #expect(ClaudeLimits.parse(json: onlyDisabled) == nil)
}

@Test func claudeLimitsParseExtraUsageWithoutMonthlyLimitHasNilPercent() throws {
    let json: [String: Any] = [
        "extra_usage": [
            "is_enabled": true,
            "monthly_limit": NSNull(),
            "used_credits": 1240,
            "utilization": 24.8,
        ],
    ]
    let extra = try #require(ClaudeLimits.parse(json: json)?.extraUsage)
    #expect(extra.percentUsed == nil)
    #expect(extra.usedDollars == 12.4)
    #expect(extra.monthlyLimitDollars == nil)
    #expect(extra.amountDetail == nil)
}

@Test func claudeLimitsParseExtraUsageScalesByDecimalPlaces() throws {
    let cents: [String: Any] = [
        "extra_usage": [
            "is_enabled": true,
            "monthly_limit": 30000,
            "used_credits": 10587,
            "utilization": 35.29,
            "decimal_places": 2,
        ],
    ]
    let scaled = try #require(ClaudeLimits.parse(json: cents)?.extraUsage)
    #expect(scaled.percentUsed == 35.29)
    #expect(scaled.usedDollars == 105.87)
    #expect(scaled.monthlyLimitDollars == 300)
    #expect(scaled.amountDetail == "$105.87 of $300")

    let major: [String: Any] = [
        "extra_usage": [
            "is_enabled": true,
            "monthly_limit": 50,
            "used_credits": 12.4,
            "utilization": 24.8,
            "decimal_places": 0,
        ],
    ]
    let unscaled = try #require(ClaudeLimits.parse(json: major)?.extraUsage)
    #expect(unscaled.usedDollars == 12.4)
    #expect(unscaled.monthlyLimitDollars == 50)
}

@Test func claudeLimitsParseFractionalAndPlainResets() throws {
    let fractional: [String: Any] = [
        "five_hour": [
            "utilization": 33.0,
            "resets_at": "2026-04-11T07:00:00.528743+00:00",
        ],
    ]
    let plain: [String: Any] = [
        "seven_day": [
            "utilization": 13,
            "resets_at": "2026-04-17T00:59:59Z",
        ],
    ]

    let five = try #require(ClaudeLimits.parse(json: fractional)?.fiveHour)
    #expect(five.percentUsed == 33)
    #expect(five.resetsAt == Date(timeIntervalSince1970: 1_775_890_800.528743))

    let weekly = try #require(ClaudeLimits.parse(json: plain)?.weekly)
    #expect(weekly.percentUsed == 13)
    #expect(weekly.resetsAt == Date(timeIntervalSince1970: 1_776_387_599))
}

@Test func claudeLimitsParseKeepsOnePercent() throws {
    // utilization is already 0–100. 1.0 is 1%, not a 0–1 fraction.
    let json: [String: Any] = [
        "five_hour": [
            "utilization": 1.0,
            "resets_at": NSNull(),
        ],
    ]
    let five = try #require(ClaudeLimits.parse(json: json)?.fiveHour)
    #expect(five.percentUsed == 1)
    #expect(five.resetsAt == nil)
}

@Test func claudeLimitGaugesFollowBucketOrderAndHideAbsences() throws {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(secondsFromGMT: 0)!
    let now = Date(timeIntervalSince1970: 1_794_757_200)
    let five = ClaudeLimitWindow(percentUsed: 62, resetsAt: now)
    let weekly = ClaudeLimitWindow(percentUsed: 34, resetsAt: Date(timeIntervalSince1970: 1_795_161_600))
    let opus = ClaudeLimitWindow(percentUsed: 80, resetsAt: Date(timeIntervalSince1970: 1_795_161_600))
    let sonnet = ClaudeLimitWindow(percentUsed: 21, resetsAt: nil)
    let extra = ClaudeExtraUsage(percentUsed: 24.8, usedDollars: 12.4, monthlyLimitDollars: 50)

    let all = ClaudeLimitGauges.make(
        fiveHour: five,
        weekly: weekly,
        weeklyOpus: opus,
        weeklySonnet: sonnet,
        extraUsage: extra,
        now: now,
        calendar: calendar
    )
    #expect(all.map(\.title) == ["5h limit", "Weekly limit", "Opus weekly", "Sonnet weekly", "Extra usage"])
    #expect(all.map(\.percent) == [62, 34, 80, 21, 24.8])
    try #require(all.count == 5)
    #expect(all[0].detail == "resets 3:40pm")
    #expect(all[1].detail == "resets Fri")
    #expect(all[2].detail == "resets Fri")
    #expect(all[3].detail == nil)
    #expect(all[4].detail == "$12.40 of $50")

    let partial = ClaudeLimitGauges.make(
        fiveHour: five,
        weekly: nil,
        weeklyOpus: opus,
        weeklySonnet: nil,
        extraUsage: ClaudeExtraUsage(percentUsed: nil, usedDollars: 12.4, monthlyLimitDollars: nil),
        now: now,
        calendar: calendar
    )
    #expect(partial.map(\.title) == ["5h limit", "Weekly limit", "Opus weekly", "Extra usage"])
    try #require(partial.count == 4)
    #expect(partial[1].percent == nil)
    #expect(partial[1].detail == nil)
    #expect(partial[3].detail == nil)

    let extraOnly = ClaudeLimitGauges.make(
        fiveHour: nil,
        weekly: nil,
        weeklyOpus: nil,
        weeklySonnet: nil,
        extraUsage: extra,
        now: now,
        calendar: calendar
    )
    #expect(extraOnly.map(\.title) == ["Extra usage"])

    let none = ClaudeLimitGauges.make(
        fiveHour: nil,
        weekly: nil,
        weeklyOpus: nil,
        weeklySonnet: nil,
        extraUsage: nil,
        now: now,
        calendar: calendar
    )
    #expect(none.isEmpty)
}

@Test func claudeLimitsParseGarbageIsNil() {
    #expect(ClaudeLimits.parse(json: ["error": "nope"]) == nil)
    #expect(ClaudeLimits.parse(json: ["five_hour": "nope"]) == nil)
    #expect(ClaudeLimits.parse(json: [:]) == nil)
}

@Test func claudeOAuthTokenExtractsALiveToken() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let data = try claudeLimitsKeychain(token: "sk-ant-oat01-test", expiresAtMs: 1_800_000_000_000)
    #expect(ClaudeOAuthToken.extract(from: data, now: now) == .valid(accessToken: "sk-ant-oat01-test"))
}

@Test func claudeOAuthTokenRejectsAnExpiredToken() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let data = try claudeLimitsKeychain(token: "sk-ant-oat01-old", expiresAtMs: 1_700_000_000_000)
    #expect(ClaudeOAuthToken.extract(from: data, now: now) == .expired)
}

@Test func claudeOAuthTokenRejectsUnreadableData() {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    #expect(ClaudeOAuthToken.extract(from: Data("not-json".utf8), now: now) == .unreadable)
    #expect(ClaudeOAuthToken.extract(from: Data("{}".utf8), now: now) == .unreadable)
}

@Test func claudeOAuthTokenReadsABlankedLoginAsSignedOut() throws {
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let data = try JSONSerialization.data(withJSONObject: [
        "claudeAiOauth": ["accessToken": "", "refreshToken": "", "expiresAt": 0]
    ])
    #expect(ClaudeOAuthToken.extract(from: data, now: now) == .signedOut)
}

@Test @MainActor func claudeLimitsBlankedLoginAsksToSignIn() async throws {
    let harness = try LimitsHarness()
    defer { harness.cleanup() }
    harness.settings.claudeLimitsEnabled = true
    harness.probe.data = try JSONSerialization.data(withJSONObject: [
        "claudeAiOauth": ["accessToken": "", "refreshToken": "", "expiresAt": 0]
    ])

    await harness.store.refresh()

    #expect(harness.probe.fetches.isEmpty)
    #expect(harness.probe.renewals == 0)
    #expect(harness.store.limitsError == ClaudeLimitsClient.noLogin)
}

@Test func claudeLimitsRequestUsesTheOAuthUsageEndpoint() {
    let request = ClaudeLimitsClient.makeRequest(accessToken: "token-a", userAgent: "Burnrate/1.2.3")
    #expect(request.url?.absoluteString == "https://api.anthropic.com/api/oauth/usage")
    #expect(request.httpMethod == "GET")
    #expect(request.timeoutInterval == 10)
    #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-a")
    #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "oauth-2025-04-20")
    #expect(request.value(forHTTPHeaderField: "User-Agent") == "Burnrate/1.2.3")
}

@Test @MainActor func claudeLimitsDisabledDoesNotFetch() async throws {
    let harness = try LimitsHarness()
    defer { harness.cleanup() }

    await harness.store.refresh()

    #expect(harness.probe.keychainReads == 0)
    #expect(harness.probe.fetches.isEmpty)
    #expect(harness.store.limits == nil)
    #expect(harness.store.limitsError == nil)
}

@Test @MainActor func claudeLimitsExpiredTokenDoesNotFetch() async throws {
    let harness = try LimitsHarness()
    defer { harness.cleanup() }
    harness.settings.claudeLimitsEnabled = true
    harness.probe.data = try claudeLimitsKeychain(token: "token-old", expiresAtMs: 1_600_000_000_000)

    await harness.store.refresh()

    #expect(harness.probe.keychainReads == 1)
    #expect(harness.probe.fetches.isEmpty)
    #expect(harness.store.limits == nil)
    #expect(harness.store.limitsError == ClaudeLimitsClient.loginExpired)
}

@Test @MainActor func claudeLimitsRejectedTokenReadsAsExpired() async throws {
    let harness = try LimitsHarness()
    defer { harness.cleanup() }
    harness.settings.claudeLimitsEnabled = true
    harness.probe.data = try claudeLimitsKeychain(token: "token-a", expiresAtMs: 1_800_000_000_000)
    harness.probe.fetchError = ClaudeLimitsClientError.httpStatus(401)

    await harness.store.refresh()

    #expect(harness.store.limitsError == ClaudeLimitsClient.loginExpired)
}

@Test @MainActor func claudeLimitsExpiredLoginIsRenewedThenFetched() async throws {
    let harness = try LimitsHarness()
    defer { harness.cleanup() }
    harness.settings.claudeLimitsEnabled = true
    harness.probe.data = try claudeLimitsKeychain(token: "token-old", expiresAtMs: 1_600_000_000_000)
    harness.probe.renewed = try claudeLimitsKeychain(token: "token-new", expiresAtMs: 1_800_000_000_000)

    await harness.store.refresh()

    #expect(harness.probe.renewals == 1)
    #expect(harness.probe.fetches == ["token-new"])
    #expect(harness.store.limitsError == nil)
}

@Test @MainActor func claudeLimitsRejectedTokenIsRenewedOnceThenRetried() async throws {
    let harness = try LimitsHarness()
    defer { harness.cleanup() }
    harness.settings.claudeLimitsEnabled = true
    harness.probe.data = try claudeLimitsKeychain(token: "token-a", expiresAtMs: 1_800_000_000_000)
    harness.probe.rejectedTokens = ["token-a"]
    harness.probe.renewed = try claudeLimitsKeychain(token: "token-b", expiresAtMs: 1_800_000_000_000)

    await harness.store.refresh()

    #expect(harness.probe.renewals == 1)
    #expect(harness.probe.fetches == ["token-a", "token-b"])
    #expect(harness.store.limitsError == nil)
}

@Test @MainActor func claudeLimitsFailedRenewalWaitsBeforeTryingAgain() async throws {
    let harness = try LimitsHarness()
    defer { harness.cleanup() }
    harness.settings.claudeLimitsEnabled = true
    harness.probe.data = try claudeLimitsKeychain(token: "token-old", expiresAtMs: 1_600_000_000_000)

    await harness.store.refresh()
    harness.probe.now = harness.probe.now.addingTimeInterval(120)
    await harness.store.refresh()
    #expect(harness.probe.renewals == 1)
    #expect(harness.store.limitsError == ClaudeLimitsClient.loginExpired)

    harness.probe.now = harness.probe.now.addingTimeInterval(ClaudeLimitsClient.renewInterval)
    await harness.store.refresh()
    #expect(harness.probe.renewals == 2)
}

@Test func claudeOAuthRefreshBodyCarriesRefreshTokenAndScopes() throws {
    let data = try JSONSerialization.data(withJSONObject: [
        "claudeAiOauth": ["accessToken": "a", "refreshToken": "r1", "expiresAt": 1, "scopes": ["user:profile", "user:inference"]],
    ])
    let body = try #require(ClaudeOAuthRefresh.requestBody(from: data))
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: String])
    #expect(json["grant_type"] == "refresh_token")
    #expect(json["refresh_token"] == "r1")
    #expect(json["client_id"] == ClaudeOAuthRefresh.clientID)
    #expect(json["scope"] == "user:profile user:inference")
}

@Test func claudeOAuthRefreshMergeKeepsOtherFields() throws {
    let data = try JSONSerialization.data(withJSONObject: [
        "mcpOAuth": ["server": ["token": "keep"]],
        "claudeAiOauth": ["accessToken": "a", "refreshToken": "r1", "expiresAt": 1, "subscriptionType": "team"],
    ])
    let reply = try JSONSerialization.data(withJSONObject: [
        "access_token": "a2", "expires_in": 28800, "refresh_token_expires_in": 100,
    ])
    let now = Date(timeIntervalSince1970: 1_700_000_000)
    let merged = try #require(ClaudeOAuthRefresh.merge(response: reply, into: data, now: now))
    let json = try #require(try JSONSerialization.jsonObject(with: merged) as? [String: Any])
    let oauth = try #require(json["claudeAiOauth"] as? [String: Any])
    #expect(oauth["accessToken"] as? String == "a2")
    #expect(oauth["refreshToken"] as? String == "r1")
    #expect((oauth["expiresAt"] as? NSNumber)?.int64Value == 1_700_028_800_000)
    #expect((oauth["refreshTokenExpiresAt"] as? NSNumber)?.int64Value == 1_700_000_100_000)
    #expect(oauth["subscriptionType"] as? String == "team")
    #expect((json["mcpOAuth"] as? [String: Any]) != nil)
    #expect(ClaudeOAuthToken.extract(from: merged, now: now) == .valid(accessToken: "a2"))
}

@Test @MainActor func claudeLimitsSuccessSetsWindows() async throws {
    let harness = try LimitsHarness()
    defer { harness.cleanup() }
    harness.settings.claudeLimitsEnabled = true
    harness.probe.data = try claudeLimitsKeychain(token: "token-a", expiresAtMs: 1_800_000_000_000)
    let expected = ClaudeLimits(
        fiveHour: ClaudeLimitWindow(percentUsed: 62, resetsAt: claudeLimitsDate("2026-11-15T15:40:00Z")),
        weekly: ClaudeLimitWindow(percentUsed: 34, resetsAt: claudeLimitsDate("2026-11-20T08:00:00Z"))
    )
    harness.probe.limits = expected

    await harness.store.refresh()

    #expect(harness.probe.fetches == ["token-a"])
    #expect(harness.store.limits == expected)
    #expect(harness.store.limitsError == nil)
}

@Test @MainActor func claudeLimitsFailureKeepsPreviousWindows() async throws {
    let harness = try LimitsHarness()
    defer { harness.cleanup() }
    harness.settings.claudeLimitsEnabled = true
    harness.probe.data = try claudeLimitsKeychain(token: "token-a", expiresAtMs: 1_800_000_000_000)
    let expected = ClaudeLimits(
        fiveHour: ClaudeLimitWindow(percentUsed: 62, resetsAt: nil),
        weekly: ClaudeLimitWindow(percentUsed: 34, resetsAt: nil)
    )
    harness.probe.limits = expected
    await harness.store.refresh()

    harness.probe.fetchError = URLError(.timedOut)
    harness.probe.now = harness.probe.now.addingTimeInterval(60)
    await harness.store.refresh()

    #expect(harness.probe.fetches.count == 2)
    #expect(harness.store.limits == expected)
    #expect(harness.store.limitsError == "Limits unavailable")
}

@Test @MainActor func claudeLimitsFetchWaitsSixtySeconds() async throws {
    let harness = try LimitsHarness()
    defer { harness.cleanup() }
    harness.settings.claudeLimitsEnabled = true
    harness.probe.data = try claudeLimitsKeychain(token: "token-a", expiresAtMs: 1_800_000_000_000)

    await harness.store.refresh()
    harness.probe.now = harness.probe.now.addingTimeInterval(59)
    await harness.store.refresh()
    #expect(harness.probe.fetches.count == 1)

    harness.probe.now = harness.probe.now.addingTimeInterval(1)
    await harness.store.refresh()
    #expect(harness.probe.fetches.count == 2)
}

@Test @MainActor func claudeLimitsToggleOffClearsWindows() async throws {
    let harness = try LimitsHarness()
    defer { harness.cleanup() }
    harness.settings.claudeLimitsEnabled = true
    harness.probe.data = try claudeLimitsKeychain(token: "token-a", expiresAtMs: 1_800_000_000_000)
    await harness.store.refresh()
    #expect(harness.store.limits != nil)

    harness.settings.claudeLimitsEnabled = false
    await harness.store.refresh()

    #expect(harness.store.limits == nil)
    #expect(harness.store.limitsError == nil)
    #expect(harness.probe.fetches.count == 1)
}

private func claudeLimitsDate(_ string: String) -> Date? {
    let fractional = ISO8601DateFormatter()
    fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let date = fractional.date(from: string) { return date }
    let plain = ISO8601DateFormatter()
    plain.formatOptions = [.withInternetDateTime]
    return plain.date(from: string)
}

private func claudeLimitsKeychain(token: String, expiresAtMs: Double) throws -> Data {
    try JSONSerialization.data(withJSONObject: [
        "claudeAiOauth": [
            "accessToken": token,
            "expiresAt": expiresAtMs,
        ],
    ])
}

@MainActor
private final class LimitsProbe {
    var fetches: [String] = []
    var keychainReads = 0
    var data: Data?
    var fetchError: Error?
    var limits = ClaudeLimits(fiveHour: nil, weekly: nil)
    var now = Date(timeIntervalSince1970: 1_700_000_000)
    var renewals = 0
    var renewed: Data?
    var rejectedTokens: Set<String> = []

    func dependency() -> ClaudePlanLimits {
        ClaudePlanLimits(
            readKeychain: {
                self.keychainReads += 1
                return self.data
            },
            fetch: { token in
                self.fetches.append(token)
                if self.rejectedTokens.contains(token) { throw ClaudeLimitsClientError.httpStatus(401) }
                if let fetchError = self.fetchError { throw fetchError }
                return self.limits
            },
            renew: { _ in
                self.renewals += 1
                if let renewed = self.renewed { self.data = renewed }
                return self.renewed
            },
            now: { self.now }
        )
    }
}

@MainActor
private final class LimitsHarness {
    let probe = LimitsProbe()
    let settings: SettingsStore
    let store: ClaudeCodeStore
    private let base: URL
    private let suite: String
    private let defaults: UserDefaults

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent("claude-limits-\(UUID().uuidString)", isDirectory: true)
        let root = base.appendingPathComponent("projects", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        suite = "com.burnrate.tests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        settings = SettingsStore(defaults: defaults, persistMembershipSecretInKeychain: false)
        store = ClaudeCodeStore(
            settings: settings,
            anomalyMonitor: nil,
            projectsRoot: root,
            cacheURL: base.appendingPathComponent("claude-index.json"),
            planLimits: probe.dependency()
        )
    }

    func cleanup() {
        try? FileManager.default.removeItem(at: base)
        defaults.removePersistentDomain(forName: suite)
    }
}

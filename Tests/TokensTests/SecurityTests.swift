import Foundation
import Testing
@testable import Tokens

@Test func failureReporterRedactsJWT() {
    let jwt = "eyJhbGciOiJIUzI1NiJ9.eyJzdWIiOiIxMjM0NTY3ODkwIn0.dozjgNryP4J3jVmNHl0w5N_XgL0n3I9PlFUP0THsR8U"
    let input = "Auth failed: \(jwt)"
    let output = FailureReporter.redact(input)
    #expect(!output.contains(jwt))
    #expect(output.contains("[REDACTED_JWT]"))
}

@Test func failureReporterRedactsSessionCookie() {
    let input = "Cookie WorkosCursorSessionToken=user%3A%3Asecretvalue failed"
    let output = FailureReporter.redact(input)
    #expect(!output.contains("secretvalue"))
    #expect(output.contains("WorkosCursorSessionToken=[REDACTED]"))
}

@Test func failureReporterDisabledByDefault() async {
    FailureReporter.isEnabled = { false }
    defer { FailureReporter.isEnabled = { false } }

    // Should return immediately without network; no assertion on side effects.
    FailureReporter.report(source: .app, category: .unknown, message: "test")
    try? await Task.sleep(nanoseconds: 50_000_000)
}

@Test func settingsStoreMigratesLegacyMembershipSecret() {
    let suite = "com.burnrate.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)

    let legacySecret = String(repeating: "a", count: 43)
    defaults.set(legacySecret, forKey: "communityMembershipSecret")

    let store = SettingsStore(defaults: defaults)
    #expect(store.communityMembershipSecret == legacySecret)
    #expect(defaults.string(forKey: "communityMembershipSecret") == nil)

    defaults.removePersistentDomain(forName: suite)
}

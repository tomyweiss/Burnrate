import Foundation
import Testing
import TokensCore
@testable import Tokens

@MainActor
private final class StopCounter {
    var calls = 0
}

@MainActor
private struct GuardFixture {
    let suite = "spendcap.\(UUID().uuidString)"
    let defaults: UserDefaults
    let dir: URL
    let counter = StopCounter()

    init() throws {
        defaults = UserDefaults(suiteName: suite)!
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("spendcap-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    var flagURL: URL { dir.appendingPathComponent("spend-cap-tripped") }
    var settingsURL: URL { dir.appendingPathComponent(".claude/settings.json") }

    func make() -> SpendCapController {
        let counter = counter
        return SpendCapController(
            defaults: defaults,
            notifier: nil,
            flagURL: flagURL,
            claudeSettingsURL: settingsURL,
            stopProcesses: { _ in
                await MainActor.run { counter.calls += 1 }
                return 3
            }
        )
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suite)
        try? FileManager.default.removeItem(at: dir)
    }
}

@Test @MainActor func unarmedGuardNeverTrips() async throws {
    let fixture = try GuardFixture()
    defer { fixture.cleanup() }
    let controller = fixture.make()
    await controller.evaluate(spentCents: 999_999, limits: nil)
    #expect(!controller.isTripped)
    #expect(!FileManager.default.fileExists(atPath: fixture.flagURL.path))
}

@Test @MainActor func spendCapTripsWritesFlagAndStopsProcessesWithoutHook() async throws {
    let fixture = try GuardFixture()
    defer { fixture.cleanup() }
    let controller = fixture.make()
    controller.capDollars = 20
    controller.arm()

    await controller.evaluate(spentCents: 1000, limits: nil)
    #expect(!controller.isTripped)
    await controller.evaluate(spentCents: 2100, limits: nil)
    #expect(controller.isTripped)
    let message = try String(contentsOf: fixture.flagURL, encoding: .utf8)
    #expect(message.contains("spend cap reached"))

    // No hook installed: the hard stop runs without a grace period.
    for _ in 0..<50 where !controller.processesStopped {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(controller.processesStopped)
    #expect(fixture.counter.calls == 1)
    #expect(controller.tripDetail?.contains("stopped 3 claude code processes") == true)

    controller.arm()
    #expect(!controller.isTripped)
    #expect(!FileManager.default.fileExists(atPath: fixture.flagURL.path))
}

@Test @MainActor func planLimitTripsEvenWithCapOff() async throws {
    let fixture = try GuardFixture()
    defer { fixture.cleanup() }
    let controller = fixture.make()
    controller.capEnabled = false
    controller.planLimitEnabled = true
    controller.stopsProcesses = false
    controller.arm()

    let full = ClaudeLimits(fiveHour: ClaudeLimitWindow(percentUsed: 100, resetsAt: nil), weekly: nil)
    await controller.evaluate(spentCents: 50_000, limits: nil)
    #expect(!controller.isTripped)
    await controller.evaluate(spentCents: nil, limits: full)
    #expect(controller.isTripped)
    #expect(controller.tripDetail?.hasPrefix("5-hour limit used up") == true)
    #expect(fixture.counter.calls == 0)

    controller.disarm()
    #expect(!controller.isArmed)
    #expect(!FileManager.default.fileExists(atPath: fixture.flagURL.path))
}

@Test @MainActor func hookGivesAgentsAGracePeriodAndStateSurvivesRelaunch() async throws {
    let fixture = try GuardFixture()
    defer { fixture.cleanup() }
    let controller = fixture.make()
    controller.installHook()
    #expect(controller.hookInstalled)
    controller.arm()
    await controller.evaluate(spentCents: 5000, limits: nil)
    #expect(controller.isTripped)
    try await Task.sleep(for: .milliseconds(100))
    #expect(fixture.counter.calls == 0)

    let relaunched = fixture.make()
    #expect(relaunched.isTripped)
    #expect(relaunched.hookInstalled)
    controller.disarm()
}

@Test @MainActor func hookInstallKeepsExistingSettingsAndRefusesBadJSON() throws {
    let fixture = try GuardFixture()
    defer { fixture.cleanup() }
    try FileManager.default.createDirectory(
        at: fixture.settingsURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    try #"{"model":"opus","permissions":{"allow":["Bash(ls)"]}}"#
        .write(to: fixture.settingsURL, atomically: true, encoding: .utf8)
    let controller = fixture.make()
    controller.installHook()
    #expect(controller.hookInstalled)
    let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.settingsURL)) as? [String: Any]
    #expect(saved?["model"] as? String == "opus")
    #expect(FileManager.default.fileExists(atPath: fixture.settingsURL.path + ".burnrate-backup"))

    controller.removeHook()
    #expect(!controller.hookInstalled)
    let after = try JSONSerialization.jsonObject(with: Data(contentsOf: fixture.settingsURL)) as? [String: Any]
    #expect(after?["hooks"] == nil)
    #expect(after?["permissions"] != nil)

    try "{ not json".write(to: fixture.settingsURL, atomically: true, encoding: .utf8)
    controller.installHook()
    #expect(controller.hookError != nil)
    #expect(try String(contentsOf: fixture.settingsURL, encoding: .utf8) == "{ not json")
}

@Test @MainActor func quitWarningOnlyWhenSomethingWouldBeLost() async throws {
    let fixture = try GuardFixture()
    defer { fixture.cleanup() }
    let controller = fixture.make()
    #expect(controller.quitWarning == nil)

    controller.arm()
    #expect(controller.quitWarning?.title == "The Claude Code stop is armed")

    controller.installHook()
    await controller.evaluate(spentCents: 99_999, limits: nil)
    #expect(controller.isTripped)
    #expect(controller.quitWarning?.title == "Claude Code processes haven't been stopped yet")

    controller.stopProcessesNow()
    for _ in 0..<50 where !controller.processesStopped {
        try await Task.sleep(for: .milliseconds(20))
    }
    #expect(controller.quitWarning == nil)

    controller.disarm()
    controller.stopsProcesses = false
    controller.arm()
    await controller.evaluate(spentCents: 99_999, limits: nil)
    #expect(controller.isTripped)
    #expect(controller.quitWarning == nil)
}

@Test func spendGuardTitleSaysWhatItIsSetTo() {
    #expect(SpendGuardTitle.make(isArmed: false, isTripped: false, capEnabled: true, capDollars: 20, spentCents: nil, planLimitEnabled: false) == "Stop agents")
    #expect(SpendGuardTitle.make(isArmed: true, isTripped: false, capEnabled: false, capDollars: 20, spentCents: nil, planLimitEnabled: true) == "Stop at plan limit")
    #expect(SpendGuardTitle.make(isArmed: true, isTripped: true, capEnabled: true, capDollars: 20, spentCents: 2500, planLimitEnabled: false) == "Agents stopped")
    let capped = SpendGuardTitle.make(isArmed: true, isTripped: false, capEnabled: true, capDollars: 20, spentCents: 320, planLimitEnabled: true)
    #expect(capped == "Stop at $20 · ~$3.20")
}

import Foundation
import Testing
@testable import Tokens

@Test func awakeButtonStateFollowsTheTrip() {
    #expect(AwakeButtonState.make(holdsAwake: false, remaining: nil) == .idle)
    #expect(AwakeButtonState.make(holdsAwake: true, remaining: nil) == .starting)
    #expect(AwakeButtonState.make(holdsAwake: true, remaining: "28m") == .running(remaining: "28m"))
}

@Test func awakeButtonNamesWhatItDoesWhenIdle() {
    let idle = AwakeButtonState.idle

    #expect(idle.title == "Keep awake")
    #expect(idle.compactTitle == nil)
    #expect(idle.symbolName == "cup.and.saucer")
    #expect(idle.isActive == false)
    #expect(idle.help == "Keep this Mac awake with the lid closed")
}

@Test func awakeButtonShowsTimeLeftWhileRunning() {
    let running = AwakeButtonState.running(remaining: "28m")

    #expect(running.title == "Awake · 28m")
    #expect(running.compactTitle == "28m")
    #expect(running.symbolName == "cup.and.saucer.fill")
    #expect(running.isActive)
    #expect(running.help == "Awake with the lid closed, 28m left. Click to stop.")
    #expect(running.menuHeading == "Awake with the lid closed · 28m left")
}

@Test func awakeButtonSaysItIsWaitingForThePassword() {
    let starting = AwakeButtonState.starting

    #expect(starting.title == "Starting…")
    #expect(starting.compactTitle == nil)
    #expect(starting.isActive)
    #expect(starting.help == "Waiting for your password")
}

@Test func awakeIntroShowsUntilDismissedAndYieldsToTheClaudeCodeHint() {
    #expect(AwakeIntroCard.shouldShow(dismissed: false, claudeCodeHintShowing: false))
    #expect(!AwakeIntroCard.shouldShow(dismissed: true, claudeCodeHintShowing: false))
    #expect(!AwakeIntroCard.shouldShow(dismissed: false, claudeCodeHintShowing: true))
    #expect(!AwakeIntroCard.shouldShow(dismissed: true, claudeCodeHintShowing: true))
}

@Test @MainActor func awakeIntroExplainsTheCupWithoutAskingToStart() {
    #expect(AwakeIntroCard.title == "New: Keep awake")
    #expect(
        AwakeIntroCard.message
            == "The cup in the top row keeps this Mac awake with the lid closed for 30, 45, or 90 minutes, so agents keep running in your bag. Sleep returns when the timer ends, or if the Mac gets hot or the battery runs low."
    )
    #expect(!AwakeIntroCard.title.contains("!"))
    #expect(!AwakeIntroCard.message.contains("!"))
}

@Test func awakeIntroDismissalPersists() {
    let suite = "com.burnrate.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    defer { defaults.removePersistentDomain(forName: suite) }

    let settings = SettingsStore(defaults: defaults, persistMembershipSecretInKeychain: false)
    #expect(settings.awakeIntroDismissed == false)

    settings.dismissAwakeIntro()
    #expect(settings.awakeIntroDismissed)
    #expect(defaults.bool(forKey: "awakeIntroDismissed"))

    let reloaded = SettingsStore(defaults: defaults, persistMembershipSecretInKeychain: false)
    #expect(reloaded.awakeIntroDismissed)
}

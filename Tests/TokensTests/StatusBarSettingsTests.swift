import Foundation
import Observation
import Testing
@testable import Tokens

private final class ObservationFlag: @unchecked Sendable {
    var value = false
}

private func makeSettings(_ defaults: UserDefaults) -> SettingsStore {
    SettingsStore(defaults: defaults, persistMembershipSecretInKeychain: false)
}

private func isolatedDefaults() -> (suite: String, defaults: UserDefaults) {
    let suite = "com.burnrate.tests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suite)!
    defaults.removePersistentDomain(forName: suite)
    return (suite, defaults)
}

@Test func statusBarDefaultsToWindowSpend() {
    let (suite, defaults) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = makeSettings(defaults)
    #expect(store.statusBarShowsWindowSpend == true)
    #expect(store.statusBarShowsCursorModels == false)
    #expect(store.statusBarShowsOtherModels == false)
    #expect(store.statusBarShowsGrokBot == false)
    #expect(defaults.object(forKey: "statusBarShowsWindowSpend") != nil)
    #expect(defaults.object(forKey: "statusBarShowsCursorModels") != nil)
    #expect(defaults.object(forKey: "statusBarShowsOtherModels") != nil)
    #expect(store.hideAmountInMenuBar() == false)
    #expect(store.communityClientConfig().hideAmountInMenuBar == false)
}

@Test func statusBarHiddenAmountMigratesToAllOff() {
    let (suite, defaults) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "hideAmountInMenuBar")

    let store = makeSettings(defaults)
    #expect(store.statusBarShowsWindowSpend == false)
    #expect(store.statusBarShowsCursorModels == false)
    #expect(store.statusBarShowsOtherModels == false)
    #expect(store.hideAmountInMenuBar() == true)
    #expect(store.communityClientConfig().hideAmountInMenuBar == true)
}

@Test func statusBarExistingKeysAreLeftStored() {
    let (suite, defaults) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }
    defaults.set(true, forKey: "hideAmountInMenuBar")
    defaults.set(false, forKey: "statusBarShowsWindowSpend")
    defaults.set(true, forKey: "statusBarShowsCursorModels")
    defaults.set(true, forKey: "statusBarShowsOtherModels")

    let store = makeSettings(defaults)
    #expect(store.statusBarShowsWindowSpend == false)
    #expect(store.statusBarShowsCursorModels == true)
    #expect(store.statusBarShowsOtherModels == true)
    #expect(store.communityClientConfig().hideAmountInMenuBar == false)
}

@Test func statusBarTogglePersists() {
    let (suite, defaults) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = makeSettings(defaults)
    store.statusBarShowsCursorModels = true
    store.statusBarShowsWindowSpend = false
    store.statusBarShowsGrokBot = true

    let reloaded = makeSettings(defaults)
    #expect(reloaded.statusBarShowsWindowSpend == false)
    #expect(reloaded.statusBarShowsCursorModels == true)
    #expect(reloaded.statusBarShowsOtherModels == false)
    #expect(reloaded.statusBarShowsGrokBot == true)
    #expect(reloaded.communityClientConfig().hideAmountInMenuBar == false)
}

@Test func statusBarGrokBotAloneCountsAsShown() {
    let (suite, defaults) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = makeSettings(defaults)
    store.statusBarShowsWindowSpend = false
    store.statusBarShowsGrokBot = true

    #expect(store.hideAmountInMenuBar() == false)
}

@Test func claudeStatusBarDefaultsOffWithoutWritingSpendKey() {
    let (suite, defaults) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = makeSettings(defaults)
    #expect(store.statusBarShowsClaudeSpend == false)
    #expect(store.statusBarShowsClaudeFiveHour == false)
    #expect(store.statusBarShowsClaudeWeekly == false)
    #expect(store.claudeLimitsEnabled == false)
    #expect(store.claudeCodeHintDismissed == false)
    #expect(defaults.object(forKey: "statusBarShowsClaudeSpend") == nil)
    #expect(defaults.object(forKey: "claudeLimitsEnabled") == nil)
    #expect(store.showsClaudeSpend(cursorAvailable: true, claudeInstalled: true) == false)
    #expect(store.showsClaudeSpend(cursorAvailable: false, claudeInstalled: false) == false)
    #expect(store.showsClaudeSpend(cursorAvailable: false, claudeInstalled: true) == true)
}

@Test func claudeStatusBarSpendPersistsAndOverridesImplicitDefault() {
    let (suite, defaults) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = makeSettings(defaults)
    store.statusBarShowsClaudeSpend = false
    #expect(defaults.object(forKey: "statusBarShowsClaudeSpend") != nil)

    let storedOff = makeSettings(defaults)
    #expect(storedOff.statusBarShowsClaudeSpend == false)
    #expect(storedOff.showsClaudeSpend(cursorAvailable: false, claudeInstalled: true) == false)

    store.statusBarShowsClaudeSpend = true
    let storedOn = makeSettings(defaults)
    #expect(storedOn.showsClaudeSpend(cursorAvailable: true, claudeInstalled: false) == true)
}

@Test func claudeStatusBarLimitTogglesAndHintPersist() {
    let (suite, defaults) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = makeSettings(defaults)
    store.statusBarShowsClaudeFiveHour = true
    store.statusBarShowsClaudeWeekly = true
    store.claudeLimitsEnabled = true
    store.dismissClaudeCodeHint()

    let reloaded = makeSettings(defaults)
    #expect(reloaded.statusBarShowsClaudeFiveHour == true)
    #expect(reloaded.statusBarShowsClaudeWeekly == true)
    #expect(reloaded.claudeLimitsEnabled == true)
    #expect(reloaded.claudeCodeHintDismissed == true)
}

@Test func showClaudeCodeInMenuBarTurnsSpendOnAndDismissesHint() {
    let (suite, defaults) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = makeSettings(defaults)
    store.showClaudeCodeInMenuBar()

    let reloaded = makeSettings(defaults)
    #expect(reloaded.statusBarShowsClaudeSpend == true)
    #expect(reloaded.claudeCodeHintDismissed == true)
    #expect(reloaded.showsClaudeSpend(cursorAvailable: true, claudeInstalled: true) == true)
}

@Test func claudeSpendAloneCountsAsShown() {
    let (suite, defaults) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = makeSettings(defaults)
    store.statusBarShowsWindowSpend = false
    store.statusBarShowsClaudeSpend = true

    #expect(store.hideAmountInMenuBar(cursorAvailable: true, claudeInstalled: true) == false)
}

@Test func claudeLimitTogglesDoNotCountUntilLimitsAreEnabled() {
    let (suite, defaults) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let store = makeSettings(defaults)
    store.statusBarShowsWindowSpend = false
    store.statusBarShowsClaudeFiveHour = true
    store.statusBarShowsClaudeWeekly = true
    #expect(store.hideAmountInMenuBar(cursorAvailable: true, claudeInstalled: true) == true)

    store.claudeLimitsEnabled = true
    #expect(store.hideAmountInMenuBar(cursorAvailable: true, claudeInstalled: true) == false)
}

@Test func hideAmountFollowsFiguresActuallyShown() {
    let (suite, defaults) = isolatedDefaults()
    defer { defaults.removePersistentDomain(forName: suite) }

    let implicit = makeSettings(defaults)
    #expect(implicit.hideAmountInMenuBar(cursorAvailable: false, claudeInstalled: true) == false)
    #expect(
        implicit.communityClientConfig(cursorAvailable: false, claudeInstalled: true).hideAmountInMenuBar
            == false
    )

    implicit.statusBarShowsClaudeSpend = false
    #expect(implicit.hideAmountInMenuBar(cursorAvailable: false, claudeInstalled: true) == true)

    let cursorOff = makeSettings(defaults)
    cursorOff.cursorEnabled = false
    cursorOff.claudeCodeEnabled = false
    #expect(cursorOff.hideAmountInMenuBar(cursorAvailable: true, claudeInstalled: true) == true)

    cursorOff.claudeCodeEnabled = true
    cursorOff.statusBarShowsClaudeSpend = true
    #expect(cursorOff.hideAmountInMenuBar(cursorAvailable: true, claudeInstalled: true) == false)
}

@Test func claudeSpendPreferenceNotifiesWhenTheUnwrittenDefaultChanges() {
    let (onSuite, onDefaults) = isolatedDefaults()
    defer { onDefaults.removePersistentDomain(forName: onSuite) }
    let turnedOn = makeSettings(onDefaults)
    let onFlag = ObservationFlag()
    withObservationTracking {
        _ = turnedOn.showsClaudeSpend(cursorAvailable: true, claudeInstalled: true)
    } onChange: {
        onFlag.value = true
    }
    turnedOn.showClaudeCodeInMenuBar()
    #expect(onFlag.value)
    #expect(turnedOn.showsClaudeSpend(cursorAvailable: true, claudeInstalled: true))

    let (offSuite, offDefaults) = isolatedDefaults()
    defer { offDefaults.removePersistentDomain(forName: offSuite) }
    let turnedOff = makeSettings(offDefaults)
    #expect(turnedOff.showsClaudeSpend(cursorAvailable: false, claudeInstalled: true))
    let offFlag = ObservationFlag()
    withObservationTracking {
        _ = turnedOff.showsClaudeSpend(cursorAvailable: false, claudeInstalled: true)
    } onChange: {
        offFlag.value = true
    }
    turnedOff.statusBarShowsClaudeSpend = false
    #expect(offFlag.value)
    #expect(turnedOff.showsClaudeSpend(cursorAvailable: false, claudeInstalled: true) == false)
    #expect(offDefaults.object(forKey: "statusBarShowsClaudeSpend") != nil)
}

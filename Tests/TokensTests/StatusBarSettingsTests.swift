import Foundation
import Testing
@testable import Tokens

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
    #expect(store.hideAmountInMenuBar == false)
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
    #expect(store.hideAmountInMenuBar == true)
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

    #expect(store.hideAmountInMenuBar == false)
}

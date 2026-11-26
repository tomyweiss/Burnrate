import Foundation
import Testing
@testable import Tokens

@Test func sparklePublicKeyIsPlaceholderUntilTomCommits() {
    #expect(SparkleConfig.placeholderPublicEDKey == "REPLACE_WITH_TOMS_SPARKLE_PUBLIC_KEY")
    #expect(SparkleConfig.isPlaceholderPublicKey)
    #expect(SparkleConfig.feedURL.absoluteString.contains("tomyweiss/Burnrate"))
    #expect(SparkleConfig.feedURL.lastPathComponent == "appcast.xml")
    #expect(SparkleConfig.scheduledCheckInterval == 86_400)
}

@Test @MainActor func sparkleStaysOffWhilePublicKeyIsPlaceholder() {
    let sparkle = SparkleUpdateController(startUpdater: true)
    #expect(!sparkle.isAvailable)
}

@Test func backgroundUpdateIsKeptUntilTheUserAttendsToIt() {
    let available = UpdateManager.pendingUpdate(after: .available(version: "0.60.15"), current: nil)
    #expect(available == .available(version: "0.60.15"))
    #expect(UpdateManager.pendingUpdate(after: .attended, current: available) == nil)
}

@Test func downloadedUpdateStaysReadyUntilRelaunch() {
    let ready = UpdateManager.pendingUpdate(after: .readyToInstall(version: "0.60.15"), current: nil)
    #expect(ready == .readyToInstall(version: "0.60.15"))
    #expect(UpdateManager.pendingUpdate(after: .attended, current: ready) == ready)
    #expect(UpdateManager.pendingUpdate(after: .available(version: "0.60.15"), current: ready) == ready)
}

@Test func pendingUpdateCopy() {
    #expect(UpdateManager.PendingUpdate.available(version: "1.2").title == "Burnrate 1.2 is available")
    #expect(UpdateManager.PendingUpdate.readyToInstall(version: "1.2").actionTitle == "Restart to Update")
}

@Test func freshFeedURLChangesEachCheckSoNoSavedCopyIsReused() {
    let first = SparkleConfig.freshFeedURLString(now: Date(timeIntervalSince1970: 1_800_000_000))
    let second = SparkleConfig.freshFeedURLString(now: Date(timeIntervalSince1970: 1_800_000_060))
    #expect(first == "https://raw.githubusercontent.com/tomyweiss/Burnrate/main/appcast.xml?check=1800000000")
    #expect(first != second)
}

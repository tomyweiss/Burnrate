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

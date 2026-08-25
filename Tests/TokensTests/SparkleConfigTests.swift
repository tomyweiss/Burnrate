import Testing
@testable import Tokens

@Test func sparklePublicKeyIsPlaceholderUntilTomCommits() {
    #expect(SparkleConfig.placeholderPublicEDKey == "REPLACE_WITH_TOMS_SPARKLE_PUBLIC_KEY")
    #expect(SparkleConfig.isPlaceholderPublicKey)
    #expect(SparkleConfig.feedURL.absoluteString.contains("tomyweiss/Burnrate"))
    #expect(SparkleConfig.feedURL.lastPathComponent == "appcast.xml")
}

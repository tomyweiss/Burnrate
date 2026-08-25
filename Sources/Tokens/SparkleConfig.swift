import Foundation

/// Sparkle feed + EdDSA public key used when packaging `Burnrate.app`.
///
/// The public key is a placeholder until Tom generates a Sparkle key pair and
/// commits the real `SUPublicEDKey`. Do not substitute a contributor-generated key.
enum SparkleConfig {
    static let feedURL = URL(
        string: "https://raw.githubusercontent.com/tomyweiss/Burnrate/main/appcast.xml"
    )!

    /// Invalid on purpose. Tom replaces this with the output of Sparkle `generate_keys`.
    static let placeholderPublicEDKey = "REPLACE_WITH_TOMS_SPARKLE_PUBLIC_KEY"

    static var publicEDKey: String {
        let trimmed = Bundle.main.object(forInfoDictionaryKey: "SUPublicEDKey") as? String
            ?? placeholderPublicEDKey
        let value = trimmed.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? placeholderPublicEDKey : value
    }

    static var isPlaceholderPublicKey: Bool {
        publicEDKey == placeholderPublicEDKey
    }
}

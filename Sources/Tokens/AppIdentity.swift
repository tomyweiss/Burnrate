import Foundation
import Security

enum AppIdentity {
    static let productionBundleIdentifier = "com.tomyweiss.burnrate"

    /// Side-by-side contributor builds use bundle id `….burnrate.dev`.
    static var isDevBuild: Bool {
        bundleIdentifier.hasSuffix(".dev")
    }

    /// True when the running binary is ad-hoc signed (e.g. `swift run`, unsigned package installs).
    static var isAdHocSigned: Bool {
        var staticCode: SecStaticCode?
        guard SecStaticCodeCreateWithPath(
            Bundle.main.bundleURL as CFURL,
            [],
            &staticCode
        ) == errSecSuccess,
            let staticCode
        else {
            return true
        }

        var info: CFDictionary?
        guard SecCodeCopySigningInformation(
            staticCode,
            SecCSFlags(rawValue: kSecCSSigningInformation),
            &info
        ) == errSecSuccess,
            let dictionary = info as? [String: Any]
        else {
            return true
        }

        guard let team = dictionary[kSecCodeInfoTeamIdentifier as String] as? String else {
            return true
        }
        return team.isEmpty
    }

    /// Production release builds keep the membership secret in Keychain. Local/ad-hoc
    /// builds store it in UserDefaults so rebuilds do not break community API auth.
    static var persistMembershipSecretInKeychain: Bool {
        #if DEBUG
        return false
        #else
        return !isDevBuild && !isAdHocSigned && bundleIdentifier == productionBundleIdentifier
        #endif
    }

    static var displayName: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String
            ?? Bundle.main.object(forInfoDictionaryKey: "CFBundleName") as? String
            ?? "Burnrate"
    }

    static var shortVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    static var versionLabel: String {
        isDevBuild ? "\(shortVersion)-dev" : shortVersion
    }

    private static var bundleIdentifier: String {
        Bundle.main.bundleIdentifier ?? productionBundleIdentifier
    }
}

import Foundation

enum AppIdentity {
    /// Side-by-side contributor builds use bundle id `….burnrate.dev`.
    static var isDevBuild: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
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
}

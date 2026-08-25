import Foundation

@MainActor
@Observable
final class UpdateManager {
    private(set) var statusMessage: String?
    private(set) var lastError: String?

    private let settings: SettingsStore
    private let sparkle: SparkleUpdateController

    init(settings: SettingsStore) {
        self.settings = settings
        self.sparkle = SparkleUpdateController(startUpdater: true)
        if sparkle.isAvailable {
            sparkle.updateCheckInterval = SparkleConfig.scheduledCheckInterval
            sparkle.automaticallyChecksForUpdates = settings.autoCheckForUpdates
        }
    }

    /// True when Sparkle is the live in-app updater (production + real key).
    var usesSparkle: Bool { sparkle.isAvailable }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Side-by-side contributor builds use bundle id `….burnrate.dev`.
    var isDevBuild: Bool { AppIdentity.isDevBuild }

    func autoCheckIfNeeded() {
        guard sparkle.isAvailable else { return }
        sparkle.automaticallyChecksForUpdates = settings.autoCheckForUpdates
    }

    func checkForUpdates(userInitiated: Bool) async {
        lastError = nil
        if isDevBuild {
            if userInitiated {
                statusMessage = "Updates are disabled in Burnrate-dev"
            }
            return
        }
        guard sparkle.isAvailable else {
            if userInitiated {
                statusMessage = "Updates aren’t available in this build"
            }
            return
        }
        statusMessage = nil
        if userInitiated {
            sparkle.checkForUpdates()
        }
    }
}

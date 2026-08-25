import Foundation
import Sparkle

/// Thin Sparkle wrapper. Starts only for production builds that have Tom's
/// real `SUPublicEDKey` in Info.plist — never for Burnrate-dev, never for the
/// placeholder key.
@MainActor
final class SparkleUpdateController {
    private let updaterController: SPUStandardUpdaterController?

    /// - Parameter startUpdater: Production enablement. Still false for
    ///   Burnrate-dev and while `SUPublicEDKey` is the placeholder.
    init(startUpdater: Bool) {
        let shouldStart = startUpdater
            && !AppIdentity.isDevBuild
            && !SparkleConfig.isPlaceholderPublicKey
        if shouldStart {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            updaterController = nil
        }
    }

    var isAvailable: Bool { updaterController != nil }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? false }
        set { updaterController?.updater.automaticallyChecksForUpdates = newValue }
    }

    var updateCheckInterval: TimeInterval {
        get { updaterController?.updater.updateCheckInterval ?? SparkleConfig.scheduledCheckInterval }
        set { updaterController?.updater.updateCheckInterval = newValue }
    }

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}

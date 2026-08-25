import Foundation
import Sparkle

/// Thin Sparkle wrapper. PR 1 does not start the updater; minisign stays live.
@MainActor
final class SparkleUpdateController {
    private let updaterController: SPUStandardUpdaterController?

    /// - Parameter startUpdater: Production enablement (PR 2). Always false for
    ///   Burnrate-dev and while `SUPublicEDKey` is still the placeholder.
    init(startUpdater: Bool = false) {
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

    func checkForUpdates() {
        updaterController?.checkForUpdates(nil)
    }
}

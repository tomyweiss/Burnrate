import AppKit
import Foundation
import Sparkle

/// Hides floating menu bar panels before Sparkle shows its modal alerts.
private final class SparkleUserDriverDelegate: NSObject, SPUStandardUserDriverDelegate {
    func standardUserDriverWillShowModalAlert() {
        runOnMain {
            NSApp.activate(ignoringOtherApps: true)
            MenuBarPanelKeeper.hidePanelsForModalAlert()
        }
    }

    func standardUserDriverDidShowModalAlert() {
        runOnMain {
            MenuBarPanelKeeper.restorePanelsAfterModalAlert()
        }
    }

    private func runOnMain(_ work: @MainActor () -> Void) {
        if Thread.isMainThread {
            MainActor.assumeIsolated(work)
        } else {
            DispatchQueue.main.sync {
                MainActor.assumeIsolated(work)
            }
        }
    }
}

/// Thin Sparkle wrapper. Starts only for production builds that have Tom's
/// real `SUPublicEDKey` in Info.plist — never for Burnrate-dev, never for the
/// placeholder key.
@MainActor
final class SparkleUpdateController {
    private let updaterController: SPUStandardUpdaterController?
    private let userDriverDelegate = SparkleUserDriverDelegate()

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
                userDriverDelegate: userDriverDelegate
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
        NSApp.activate(ignoringOtherApps: true)
        updaterController?.checkForUpdates(nil)
    }
}

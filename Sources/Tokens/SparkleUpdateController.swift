import AppKit
import Foundation
import Sparkle

/// What a background update check found, reported to `UpdateManager`.
enum SparkleUpdateEvent: Equatable {
    /// A scheduled check found an update and left showing it to the app.
    case available(version: String)
    /// Sparkle downloaded the update silently and would install it on quit.
    case readyToInstall(version: String)
    /// The user brought the update alert into focus, or the session ended.
    case attended
}

/// Hides floating menu bar panels before Sparkle shows its modal alerts, and
/// hands scheduled updates to the app. Burnrate is a menu bar app, so Sparkle
/// would otherwise put scheduled alerts behind other apps, and an update it
/// downloads silently would only install when the app quits.
///
/// Sparkle calls both delegates on the main thread.
@MainActor
private final class SparkleDelegate: NSObject, SPUUpdaterDelegate, @preconcurrency SPUStandardUserDriverDelegate {
    var onEvent: ((SparkleUpdateEvent) -> Void)?
    var installOnQuitHandler: (() -> Void)?

    // MARK: SPUStandardUserDriverDelegate

    func standardUserDriverWillShowModalAlert() {
        NSApp.activate(ignoringOtherApps: true)
        MenuBarPanelKeeper.hidePanelsForModalAlert()
    }

    func standardUserDriverDidShowModalAlert() {
        MenuBarPanelKeeper.restorePanelsAfterModalAlert()
    }

    var supportsGentleScheduledUpdateReminders: Bool { true }

    func standardUserDriverShouldHandleShowingScheduledUpdate(
        _ update: SUAppcastItem,
        andInImmediateFocus immediateFocus: Bool
    ) -> Bool {
        immediateFocus
    }

    func standardUserDriverWillHandleShowingUpdate(
        _ handleShowingUpdate: Bool,
        forUpdate update: SUAppcastItem,
        state: SPUUserUpdateState
    ) {
        guard !handleShowingUpdate else { return }
        onEvent?(.available(version: update.displayVersionString))
    }

    func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
        onEvent?(.attended)
    }

    func standardUserDriverWillFinishUpdateSession() {
        onEvent?(.attended)
    }

    // MARK: SPUUpdaterDelegate

    func updater(
        _ updater: SPUUpdater,
        willInstallUpdateOnQuit item: SUAppcastItem,
        immediateInstallationBlock immediateInstallHandler: @escaping () -> Void
    ) -> Bool {
        installOnQuitHandler = immediateInstallHandler
        onEvent?(.readyToInstall(version: item.displayVersionString))
        return true
    }
}

/// Thin Sparkle wrapper. Starts only for production builds that have Tom's
/// real `SUPublicEDKey` in Info.plist — never for Burnrate-dev, never for the
/// placeholder key.
@MainActor
final class SparkleUpdateController {
    private let updaterController: SPUStandardUpdaterController?
    private let delegate = SparkleDelegate()

    /// - Parameter startUpdater: Production enablement. Still false for
    ///   Burnrate-dev and while `SUPublicEDKey` is the placeholder.
    init(startUpdater: Bool) {
        let shouldStart = startUpdater
            && !AppIdentity.isDevBuild
            && !SparkleConfig.isPlaceholderPublicKey
        if shouldStart {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: true,
                updaterDelegate: delegate,
                userDriverDelegate: delegate
            )
        } else {
            updaterController = nil
        }
    }

    var isAvailable: Bool { updaterController != nil }

    var onEvent: ((SparkleUpdateEvent) -> Void)? {
        get { delegate.onEvent }
        set { delegate.onEvent = newValue }
    }

    var automaticallyChecksForUpdates: Bool {
        get { updaterController?.updater.automaticallyChecksForUpdates ?? false }
        set { updaterController?.updater.automaticallyChecksForUpdates = newValue }
    }

    var updateCheckInterval: TimeInterval {
        get { updaterController?.updater.updateCheckInterval ?? SparkleConfig.scheduledCheckInterval }
        set { updaterController?.updater.updateCheckInterval = newValue }
    }

    /// Also brings a scheduled update that is waiting in the background into focus.
    func checkForUpdates() {
        NSApp.activate(ignoringOtherApps: true)
        updaterController?.checkForUpdates(nil)
    }

    /// Installs an update Sparkle already downloaded, then relaunches.
    /// Returns false when no downloaded update is waiting.
    @discardableResult
    func installDownloadedUpdate() -> Bool {
        guard let handler = delegate.installOnQuitHandler else { return false }
        handler()
        return true
    }
}

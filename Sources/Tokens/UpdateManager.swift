import Foundation
import UserNotifications

@MainActor
@Observable
final class UpdateManager {
    /// An update a background check found, waiting for the user.
    enum PendingUpdate: Hashable {
        case available(version: String)
        case readyToInstall(version: String)

        var version: String {
            switch self {
            case .available(let version), .readyToInstall(let version): version
            }
        }

        var title: String {
            switch self {
            case .available(let version): "Burnrate \(version) is available"
            case .readyToInstall(let version): "Burnrate \(version) is ready to install"
            }
        }

        var actionTitle: String {
            switch self {
            case .available: "Update…"
            case .readyToInstall: "Restart to Update"
            }
        }

        var notificationBody: String {
            switch self {
            case .available: "Click to see what’s new and update."
            case .readyToInstall: "Click to restart Burnrate and finish updating."
            }
        }
    }

    nonisolated static let notificationIdentifierPrefix = "burnrate.update."

    private(set) var statusMessage: String?
    private(set) var lastError: String?
    private(set) var pendingUpdate: PendingUpdate?

    private let settings: SettingsStore
    private let sparkle: SparkleUpdateController
    private var notifiedUpdates: Set<PendingUpdate> = []

    init(settings: SettingsStore) {
        self.settings = settings
        self.sparkle = SparkleUpdateController(startUpdater: true)
        if sparkle.isAvailable {
            sparkle.updateCheckInterval = SparkleConfig.scheduledCheckInterval
            sparkle.automaticallyChecksForUpdates = settings.autoCheckForUpdates
            sparkle.onEvent = { [weak self] event in
                self?.handle(event)
            }
            NotificationPresenter.shared.install()
            NotificationPresenter.shared.onOpenUpdate = { [weak self] in
                self?.openPendingUpdate()
            }
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
            if case .readyToInstall = pendingUpdate, sparkle.installDownloadedUpdate() {
                return
            }
            sparkle.checkForUpdates()
        }
    }

    /// Banner and notification action: restart into a downloaded update, or
    /// bring the waiting update alert to the front.
    func openPendingUpdate() {
        guard let pendingUpdate else { return }
        clearNotifications()
        switch pendingUpdate {
        case .readyToInstall:
            if !sparkle.installDownloadedUpdate() {
                sparkle.checkForUpdates()
            }
        case .available:
            sparkle.checkForUpdates()
        }
    }

    /// A downloaded update stays ready until the app relaunches, so only an
    /// update that is merely available clears once the user attends to it.
    nonisolated static func pendingUpdate(
        after event: SparkleUpdateEvent,
        current: PendingUpdate?
    ) -> PendingUpdate? {
        switch event {
        case .available(let version):
            if case .readyToInstall = current { return current }
            return .available(version: version)
        case .readyToInstall(let version):
            return .readyToInstall(version: version)
        case .attended:
            if case .available = current { return nil }
            return current
        }
    }

    private func handle(_ event: SparkleUpdateEvent) {
        let next = Self.pendingUpdate(after: event, current: pendingUpdate)
        guard next != pendingUpdate else { return }
        if next == nil {
            clearNotifications()
        }
        pendingUpdate = next
        if let next, notifiedUpdates.insert(next).inserted {
            Task { await postNotification(for: next) }
        }
    }

    private func postNotification(for update: PendingUpdate) async {
        let center = UNUserNotificationCenter.current()
        switch await center.notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            break
        default:
            return
        }
        let content = UNMutableNotificationContent()
        content.title = update.title
        content.body = update.notificationBody
        let request = UNNotificationRequest(
            identifier: Self.notificationIdentifierPrefix + update.version,
            content: content,
            trigger: nil
        )
        try? await center.add(request)
    }

    private func clearNotifications() {
        guard let pendingUpdate else { return }
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: [Self.notificationIdentifierPrefix + pendingUpdate.version]
        )
    }
}

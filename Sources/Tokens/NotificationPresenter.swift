import Foundation
import UserNotifications

/// Ensures banners show even while the menu bar panel is open (app is "foreground").
@MainActor
final class NotificationPresenter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationPresenter()

    /// Called when the user clicks an update notification.
    var onOpenUpdate: (() -> Void)?

    func install() {
        UNUserNotificationCenter.current().delegate = self
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let identifier = response.notification.request.identifier
        guard identifier.hasPrefix(UpdateManager.notificationIdentifierPrefix) else { return }
        await openUpdate()
    }

    private func openUpdate() {
        onOpenUpdate?()
    }
}

import Foundation
import UserNotifications

@MainActor
final class AnomalyMonitor {
    private var lastNotificationAt: Date?
    private var center: UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }

    init() {
        NotificationPresenter.shared.install()
    }

    func requestAuthorizationIfNeeded() async {
        do {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try await center.requestAuthorization(options: [.alert, .sound, .badge])
        } catch {
            // Permission denied is fine; alerts simply won't fire.
        }
    }

    func evaluate(snapshot: UsageSnapshot, settings: SettingsStore) async {
        let thresholdCents = settings.anomalyThresholdDollars * 100
        guard snapshot.recentCostCents >= thresholdCents else { return }

        let cooldown = TimeInterval(settings.anomalyCooldownMinutes * 60)
        if let last = lastNotificationAt, Date().timeIntervalSince(last) < cooldown {
            return
        }

        let allowed = await ensureAuthorized()
        guard allowed else { return }

        do {
            try await postNotification(
                title: "Burnrate spike",
                body: String(
                    format: "%@ in the last %d minutes",
                    MoneyFormat.dollars(snapshot.recentDollars),
                    settings.anomalyWindowMinutes
                )
            )
            lastNotificationAt = Date()
        } catch {
            // Ignore delivery failures for automatic alerts.
        }
    }

    /// Returns a short status string for the Settings UI.
    func sendTestNotification(settings: SettingsStore) async -> String {
        NotificationPresenter.shared.install()

        let allowed = await ensureAuthorized()
        guard allowed else {
            return "Notifications are off. Enable Burnrate in System Settings → Notifications."
        }

        do {
            try await postNotification(
                title: "Burnrate test",
                body: String(
                    format: "Sample alert: ≥ %@ in %d minutes.",
                    MoneyFormat.dollars(settings.anomalyThresholdDollars),
                    settings.anomalyWindowMinutes
                )
            )
            return "Test notification sent."
        } catch {
            return "Could not send notification: \(error.localizedDescription)"
        }
    }

    private func ensureAuthorized() async -> Bool {
        var settings = await center.notificationSettings()
        if settings.authorizationStatus == .notDetermined {
            do {
                let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
                if !granted { return false }
                settings = await center.notificationSettings()
            } catch {
                return false
            }
        }

        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .denied, .notDetermined:
            return false
        @unknown default:
            return false
        }
    }

    private func postNotification(title: String, body: String) async throws {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        // Slight delay so delivery is reliable when the panel is focused.
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 0.5, repeats: false)
        let request = UNNotificationRequest(
            identifier: "burnrate.anomaly.\(UUID().uuidString)",
            content: content,
            trigger: trigger
        )
        try await center.add(request)
    }
}

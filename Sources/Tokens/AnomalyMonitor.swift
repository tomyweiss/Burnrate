import Foundation
import UserNotifications

@MainActor
final class AnomalyMonitor {
    private var lastNotificationAt: Date?
    private var center: UNUserNotificationCenter {
        UNUserNotificationCenter.current()
    }

    func requestAuthorizationIfNeeded() async {
        do {
            let settings = await center.notificationSettings()
            guard settings.authorizationStatus == .notDetermined else { return }
            _ = try await center.requestAuthorization(options: [.alert, .sound])
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

        await requestAuthorizationIfNeeded()
        await postNotification(
            title: "Burnrate spike",
            body: String(
                format: "%@ in the last %d minutes",
                MoneyFormat.dollars(snapshot.recentDollars),
                settings.anomalyWindowMinutes
            )
        )
        lastNotificationAt = Date()
    }

    func sendTestNotification(settings: SettingsStore) async {
        await requestAuthorizationIfNeeded()
        await postNotification(
            title: "Burnrate test",
            body: String(
                format: "Sample alert: ≥ %@ in %d minutes.",
                MoneyFormat.dollars(settings.anomalyThresholdDollars),
                settings.anomalyWindowMinutes
            )
        )
    }

    private func postNotification(title: String, body: String) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "burnrate.anomaly.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
        } catch {
            // Ignore delivery failures.
        }
    }
}

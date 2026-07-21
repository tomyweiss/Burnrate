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

        let dollars = snapshot.recentDollars
        let window = settings.anomalyWindowMinutes
        let content = UNMutableNotificationContent()
        content.title = "Cursor spend spike"
        content.body = String(
            format: "$%.2f in the last %d minutes",
            dollars,
            window
        )
        content.sound = .default

        let request = UNNotificationRequest(
            identifier: "tokens.anomaly.\(UUID().uuidString)",
            content: content,
            trigger: nil
        )

        do {
            try await center.add(request)
            lastNotificationAt = Date()
        } catch {
            // Ignore delivery failures.
        }
    }
}

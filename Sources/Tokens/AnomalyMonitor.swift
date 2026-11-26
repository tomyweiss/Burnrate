import Foundation
import UserNotifications

@MainActor
final class AnomalyMonitor {
    private var lastNotificationAt: [UsageSource: Date] = [:]
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

    nonisolated static func shouldNotify(
        source: UsageSource,
        recentCostCents: Double,
        thresholdCents: Double,
        lastNotificationAt: [UsageSource: Date],
        now: Date,
        cooldown: TimeInterval
    ) -> Bool {
        guard recentCostCents >= thresholdCents else { return false }
        if let last = lastNotificationAt[source], now.timeIntervalSince(last) < cooldown {
            return false
        }
        return true
    }

    nonisolated static func notificationContent(
        source: UsageSource,
        recentDollars: Double,
        windowMinutes: Int
    ) -> (title: String, body: String) {
        switch source {
        case .cursor:
            return (
                "Burnrate spike",
                String(
                    format: "%@ in the last %d minutes",
                    MoneyFormat.dollars(recentDollars),
                    windowMinutes
                )
            )
        case .claudeCode:
            return (
                "Burnrate spike · Claude Code",
                String(
                    format: "%@ estimated in the last %d minutes",
                    MoneyFormat.estimated(recentDollars),
                    windowMinutes
                )
            )
        }
    }

    func evaluate(
        snapshot: UsageSnapshot,
        settings: SettingsStore,
        source: UsageSource = .cursor
    ) async {
        let now = Date()
        guard Self.shouldNotify(
            source: source,
            recentCostCents: snapshot.recentCostCents,
            thresholdCents: settings.anomalyThresholdDollars * 100,
            lastNotificationAt: lastNotificationAt,
            now: now,
            cooldown: TimeInterval(settings.anomalyCooldownMinutes * 60)
        ) else { return }

        let allowed = await ensureAuthorized()
        guard allowed else { return }

        let content = Self.notificationContent(
            source: source,
            recentDollars: snapshot.recentDollars,
            windowMinutes: settings.anomalyWindowMinutes
        )
        do {
            try await postNotification(title: content.title, body: content.body)
            lastNotificationAt[source] = Date()
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

    /// Posts an alert when notifications are allowed. Delivery failures are ignored.
    func notify(title: String, body: String) async {
        guard await ensureAuthorized() else { return }
        try? await postNotification(title: title, body: body)
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

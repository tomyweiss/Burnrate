import Foundation
import AppKit

@MainActor
@Observable
final class UpdateManager {
    /// Used only when Sparkle has not started (placeholder key / Info.plist
    /// missing `SUPublicEDKey`). Production Sparkle checks daily.
    private static let minisignFallbackInterval: TimeInterval = 60 * 60
    private static let lastCheckKey = "lastUpdateCheckAt"

    private(set) var availableUpdate: AvailableUpdate?
    private(set) var isChecking = false
    private(set) var isInstalling = false
    private(set) var statusMessage: String?
    private(set) var lastError: String?

    private let settings: SettingsStore
    private let sparkle: SparkleUpdateController
    private var autoCheckTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
        self.sparkle = SparkleUpdateController(startUpdater: true)
        if sparkle.isAvailable {
            sparkle.updateCheckInterval = SparkleConfig.scheduledCheckInterval
            sparkle.automaticallyChecksForUpdates = settings.autoCheckForUpdates
        }
    }

    /// True when Sparkle is the live in-app updater (production + real key).
    var usesSparkle: Bool { sparkle.isAvailable }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Side-by-side contributor builds use bundle id `….burnrate.dev`.
    var isDevBuild: Bool { AppIdentity.isDevBuild }

    var hasUpdate: Bool { availableUpdate != nil }

    func autoCheckIfNeeded() {
        guard !isDevBuild else { return }
        if sparkle.isAvailable {
            sparkle.automaticallyChecksForUpdates = settings.autoCheckForUpdates
            autoCheckTask?.cancel()
            autoCheckTask = nil
            return
        }
        guard settings.autoCheckForUpdates else {
            autoCheckTask?.cancel()
            autoCheckTask = nil
            return
        }
        guard autoCheckTask == nil else { return }

        autoCheckTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                guard self.settings.autoCheckForUpdates else { return }

                let elapsed = Date().timeIntervalSince(self.lastCheckDate())
                if elapsed >= Self.minisignFallbackInterval {
                    await self.checkForUpdates(userInitiated: false)
                }

                let remaining = max(
                    60,
                    Self.minisignFallbackInterval - Date().timeIntervalSince(self.lastCheckDate())
                )
                try? await Task.sleep(for: .seconds(remaining))
            }
        }
    }

    func checkForUpdates(userInitiated: Bool) async {
        if isDevBuild {
            if userInitiated {
                statusMessage = "Updates are disabled in Burnrate-dev"
            }
            return
        }
        if sparkle.isAvailable {
            lastError = nil
            statusMessage = nil
            if userInitiated {
                sparkle.checkForUpdates()
            }
            return
        }
        guard !isChecking, !isInstalling else { return }
        isChecking = true
        lastError = nil
        if userInitiated {
            statusMessage = "Checking for updates…"
        }
        defer { isChecking = false }

        do {
            let update = try await UpdateChecker.shared.fetchLatestUpdate(currentVersion: currentVersion)
            availableUpdate = update
            if let update {
                statusMessage = "Update \(update.version) available"
            } else if userInitiated {
                statusMessage = "You’re up to date (\(currentVersion))"
            } else {
                statusMessage = nil
            }
        } catch {
            availableUpdate = nil
            lastError = error.localizedDescription
            FailureReporter.report(error: error, source: .updates)
            if userInitiated {
                statusMessage = error.localizedDescription
            }
        }
        // Rate-limit auto checks even when the request fails.
        markChecked()
    }

    func installAvailableUpdate() async {
        guard let update = availableUpdate, !isInstalling else { return }
        isInstalling = true
        lastError = nil
        statusMessage = "Downloading \(update.version)…"
        defer { isInstalling = false }

        do {
            let newApp = try await UpdateChecker.shared.downloadAndPrepareInstall(update)
            statusMessage = "Installing…"
            let dest = Bundle.main.bundleURL
            try await UpdateChecker.shared.launchHelperReplacing(currentApp: dest, with: newApp)
            statusMessage = "Restarting…"
            NSApplication.shared.terminate(nil)
        } catch {
            lastError = error.localizedDescription
            statusMessage = error.localizedDescription
            FailureReporter.report(error: error, source: .updates)
        }
    }

    private func lastCheckDate() -> Date {
        Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Self.lastCheckKey))
    }

    private func markChecked() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
    }
}

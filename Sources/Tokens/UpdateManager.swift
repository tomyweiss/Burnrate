import Foundation
import AppKit

@MainActor
@Observable
final class UpdateManager {
    private static let autoCheckInterval: TimeInterval = 60 * 60 // 1 hour
    private static let lastCheckKey = "lastUpdateCheckAt"

    private(set) var availableUpdate: AvailableUpdate?
    private(set) var isChecking = false
    private(set) var isInstalling = false
    private(set) var statusMessage: String?
    private(set) var lastError: String?

    private let settings: SettingsStore
    private var autoCheckTask: Task<Void, Never>?

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    /// Side-by-side contributor builds use bundle id `….burnrate.dev`.
    var isDevBuild: Bool {
        Bundle.main.bundleIdentifier?.hasSuffix(".dev") == true
    }

    var hasUpdate: Bool { availableUpdate != nil }

    func autoCheckIfNeeded() {
        guard !isDevBuild else { return }
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
                if elapsed >= Self.autoCheckInterval {
                    await self.checkForUpdates(userInitiated: false)
                }

                let remaining = max(
                    60,
                    Self.autoCheckInterval - Date().timeIntervalSince(self.lastCheckDate())
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
        }
    }

    private func lastCheckDate() -> Date {
        Date(timeIntervalSince1970: UserDefaults.standard.double(forKey: Self.lastCheckKey))
    }

    private func markChecked() {
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Self.lastCheckKey)
    }
}

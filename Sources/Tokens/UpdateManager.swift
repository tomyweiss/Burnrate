import Foundation
import AppKit

@MainActor
@Observable
final class UpdateManager {
    private(set) var availableUpdate: AvailableUpdate?
    private(set) var isChecking = false
    private(set) var isInstalling = false
    private(set) var statusMessage: String?
    private(set) var lastError: String?

    private let settings: SettingsStore
    private var didAutoCheck = false

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    }

    var hasUpdate: Bool { availableUpdate != nil }

    func autoCheckIfNeeded() {
        guard settings.autoCheckForUpdates, !didAutoCheck else { return }
        didAutoCheck = true
        Task { await checkForUpdates(userInitiated: false) }
    }

    func checkForUpdates(userInitiated: Bool) async {
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
}

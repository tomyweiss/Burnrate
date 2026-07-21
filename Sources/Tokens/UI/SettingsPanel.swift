import SwiftUI

struct SettingsPanel: View {
    @Bindable var settings: SettingsStore
    @Bindable var updates: UpdateManager
    @Bindable var store: UsageStore
    var glassNamespace: Namespace.ID
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    onBack()
                    MenuBarPanelKeeper.keepOpen()
                } label: {
                    Label("Usage", systemImage: "chevron.left")
                }
                .buttonStyle(.borderless)
                .glassEffect(.regular.interactive())
                .glassEffectID("settings-gear", in: glassNamespace)

                Spacer()

                Text("Settings")
                    .font(.headline)

                Spacer()

                Color.clear.frame(width: 72, height: 1)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            Form {
                Section("Refresh") {
                    Picker("Poll every", selection: $settings.refreshIntervalSeconds) {
                        ForEach(SettingsStore.refreshIntervalOptions, id: \.self) { seconds in
                            Text(SettingsStore.intervalLabel(seconds)).tag(seconds)
                        }
                    }
                    .onChange(of: settings.refreshIntervalSeconds) { _, _ in
                        MenuBarPanelKeeper.keepOpen()
                    }
                }

                Section("Spike alert") {
                    Stepper(value: $settings.anomalyThresholdDollars, in: 1...100, step: 1) {
                        Text("Threshold \(MoneyFormat.dollars(settings.anomalyThresholdDollars))")
                    }
                    .onChange(of: settings.anomalyThresholdDollars) { _, _ in
                        MenuBarPanelKeeper.keepOpen()
                    }

                    Stepper(value: $settings.anomalyWindowMinutes, in: 1...60, step: 1) {
                        Text("Window \(settings.anomalyWindowMinutes) min")
                    }
                    .onChange(of: settings.anomalyWindowMinutes) { _, _ in
                        MenuBarPanelKeeper.keepOpen()
                    }

                    Stepper(value: $settings.anomalyCooldownMinutes, in: 1...120, step: 1) {
                        Text("Cooldown \(settings.anomalyCooldownMinutes) min")
                    }
                    .onChange(of: settings.anomalyCooldownMinutes) { _, _ in
                        MenuBarPanelKeeper.keepOpen()
                    }

                    Text(
                        String(
                            format: "Alert when ≥ %@ is spent in %d minutes.",
                            MoneyFormat.dollars(settings.anomalyThresholdDollars),
                            settings.anomalyWindowMinutes
                        )
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)

                    Button("Test notification") {
                        Task { await store.sendTestNotification() }
                        MenuBarPanelKeeper.keepOpen()
                    }

                    if let feedback = store.notificationFeedback {
                        Text(feedback)
                            .font(.caption)
                            .foregroundStyle(
                                feedback.hasPrefix("Test notification")
                                    ? Color.secondary
                                    : Color.orange
                            )
                    }
                }

                Section("Updates") {
                    Toggle("Check for updates automatically", isOn: $settings.autoCheckForUpdates)
                        .onChange(of: settings.autoCheckForUpdates) { _, _ in
                            updates.autoCheckIfNeeded()
                            MenuBarPanelKeeper.keepOpen()
                        }

                    Button(updates.isChecking ? "Checking…" : "Check for Updates…") {
                        Task { await updates.checkForUpdates(userInitiated: true) }
                        MenuBarPanelKeeper.keepOpen()
                    }
                    .disabled(updates.isChecking || updates.isInstalling)

                    if let update = updates.availableUpdate {
                        Text("Version \(update.version) is available.")
                            .font(.caption)
                        Button(updates.isInstalling ? "Installing…" : "Download & Install") {
                            Task { await updates.installAvailableUpdate() }
                            MenuBarPanelKeeper.keepOpen()
                        }
                        .disabled(updates.isInstalling)
                    }

                    if let status = updates.statusMessage {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(updates.lastError == nil ? Color.secondary : Color.red)
                    }

                    Text("Automatic checks run about once an hour. Updates download from GitHub Releases, verify a minisign signature, then replace this app. Builds are not Apple-notarized.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Section("General") {
                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        .onChange(of: settings.launchAtLogin) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                    Toggle("Hide amount in menu bar", isOn: $settings.hideAmountInMenuBar)
                        .onChange(of: settings.hideAmountInMenuBar) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                }

                Section("About") {
                    LabeledContent("App", value: "Burnrate")
                    LabeledContent("Version", value: appVersion)
                    Text("Uses your local Cursor sign-in. Data may differ slightly from the official dashboard.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Link("Open Cursor Dashboard", destination: URL(string: "https://cursor.com/dashboard")!)
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .onAppear { MenuBarPanelKeeper.keepOpen() }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.7"
    }
}

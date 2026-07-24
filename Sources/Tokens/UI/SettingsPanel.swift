import SwiftUI

struct SettingsPanel: View {
    @Bindable var settings: SettingsStore
    @Bindable var updates: UpdateManager
    @Bindable var store: UsageStore
    var glassNamespace: Namespace.ID
    var onBack: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Text("Settings")
                    .font(.headline)

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

                    Text(appVersion)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)

            Divider()

            Form {
                Section("General") {
                    Picker("Poll every", selection: $settings.refreshIntervalSeconds) {
                        ForEach(SettingsStore.refreshIntervalOptions, id: \.self) { seconds in
                            Text(SettingsStore.intervalLabel(seconds)).tag(seconds)
                        }
                    }
                    .onChange(of: settings.refreshIntervalSeconds) { _, _ in
                        MenuBarPanelKeeper.keepOpen()
                    }

                    timezonePicker

                    Toggle("Launch at login", isOn: $settings.launchAtLogin)
                        .onChange(of: settings.launchAtLogin) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                    Toggle("Hide amount in menu bar", isOn: $settings.hideAmountInMenuBar)
                        .onChange(of: settings.hideAmountInMenuBar) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                    Toggle("Blur session & prompt titles", isOn: $settings.blurSensitiveContent)
                        .onChange(of: settings.blurSensitiveContent) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                    Text("Soft-blurs chat titles and prompt text for screen recordings. Costs and models stay visible.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Show location subtitle", isOn: $settings.showLocationSubtitle)
                        .onChange(of: settings.showLocationSubtitle) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                    Text("Extra row under each session: workspace, or repo · branch for cloud agents.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Toggle("Hide archived sessions", isOn: $settings.hideArchivedSessions)
                        .onChange(of: settings.hideArchivedSessions) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                    Text("Hide sessions Cursor has archived. Spend totals are unchanged.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
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
                    if updates.isDevBuild {
                        Text("Self-updates are disabled in Burnrate-dev. Reinstall with scripts/package.sh --dev.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
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
                            if ReleaseNotesView.hasContent(update.notes) {
                                ReleaseNotesView(notes: update.notes)
                            }
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

                        Text("Checks hourly from GitHub.")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                if settings.usageTimelinePreset == .thisBilling {
                    Section("Timeline") {
                        Stepper(value: $settings.billingDayOfMonth, in: 1...31) {
                            Text("Billing day \(settings.billingDayOfMonth)")
                        }
                        .onChange(of: settings.billingDayOfMonth) { _, _ in
                            Task { await store.refresh() }
                            MenuBarPanelKeeper.keepOpen()
                        }

                        Text("Spend is counted from this day of each month.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
        }
        .onAppear { MenuBarPanelKeeper.keepOpen() }
    }

    private var appVersion: String {
        AppIdentity.versionLabel
    }

    private var timezonePicker: some View {
        Picker("Timezone", selection: timezoneSelection) {
            Text("System (Local)").tag("")
            ForEach(SettingsStore.knownTimeZones, id: \.id) { zone in
                Text(zone.label).tag(zone.id)
            }
        }
        .onChange(of: settings.usageTimezoneIdentifier) { _, _ in
            Task { await store.refresh() }
            MenuBarPanelKeeper.keepOpen()
        }
    }

    private var timezoneSelection: Binding<String> {
        Binding(
            get: { settings.usageTimezoneIdentifier ?? "" },
            set: { newValue in
                settings.usageTimezoneIdentifier = newValue.isEmpty ? nil : newValue
            }
        )
    }
}

import SwiftUI

struct SettingsPanel: View {
    @Bindable var settings: SettingsStore
    @Bindable var updates: UpdateManager
    @Bindable var store: UsageStore
    var onBack: () -> Void
    var onOpenChangeLog: () -> Void

    var body: some View {
        settingsForm
    }

    private var settingsForm: some View {
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
                    .buttonStyle(.plain)

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
                }

                Section("Status bar") {
                    Toggle("Window spend", isOn: $settings.statusBarShowsWindowSpend)
                        .onChange(of: settings.statusBarShowsWindowSpend) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                    Toggle("Cursor models", isOn: $settings.statusBarShowsCursorModels)
                        .onChange(of: settings.statusBarShowsCursorModels) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                    Toggle("Other models", isOn: $settings.statusBarShowsOtherModels)
                        .onChange(of: settings.statusBarShowsOtherModels) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                    Toggle("Grok Bot", isOn: $settings.statusBarShowsGrokBot)
                        .onChange(of: settings.statusBarShowsGrokBot) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                    Text("Choose what appears next to the flame. The panel header shows those figures. Turning all of them off leaves the flame alone while the panel still shows window spend.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Privacy") {
                    Toggle("Blur session & prompt titles", isOn: $settings.blurSensitiveContent)
                        .onChange(of: settings.blurSensitiveContent) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                    Toggle("Show location subtitle", isOn: $settings.showLocationSubtitle)
                        .onChange(of: settings.showLocationSubtitle) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                    Toggle("Hide archived sessions", isOn: $settings.hideArchivedSessions)
                        .onChange(of: settings.hideArchivedSessions) { _, _ in
                            MenuBarPanelKeeper.keepOpen()
                        }
                }

                Section("Usage panel") {
                    ForEach(UsageTab.allCases) { tab in
                        Toggle(tab.title, isOn: usageTabVisibilityBinding(tab))
                            .disabled(
                                settings.isUsageTabVisible(tab)
                                    && settings.visibleUsageTabs.count == 1
                            )
                    }
                    Text("Choose which tabs appear in the main panel. At least one tab must stay visible.")
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
                        Text("Updates are disabled in Burnrate-dev. Reinstall with scripts/package.sh --dev.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Toggle("Check for updates automatically", isOn: $settings.autoCheckForUpdates)
                            .onChange(of: settings.autoCheckForUpdates) { _, _ in
                                updates.autoCheckIfNeeded()
                                MenuBarPanelKeeper.keepOpen()
                            }

                        Button("Check for Updates…") {
                            Task { await updates.checkForUpdates(userInitiated: true) }
                        }

                        if updates.usesSparkle {
                            Text("Checks once a day. You’ll confirm before installing.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        if let status = updates.statusMessage {
                            Text(status)
                                .font(.caption)
                                .foregroundStyle(updates.lastError == nil ? Color.secondary : Color.red)
                        }
                    }

                    Button {
                        onOpenChangeLog()
                        MenuBarPanelKeeper.keepOpen()
                    } label: {
                        HStack {
                            Text("Change log")
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .buttonStyle(.plain)
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
                    }
                }

                if settings.usageTimelinePreset == .custom {
                    Section("Timeline") {
                        DatePicker(
                            "Start date",
                            selection: $settings.customRangeStart,
                            in: Date.distantPast...Date(),
                            displayedComponents: [.date]
                        )
                        .onChange(of: settings.customRangeStart) { _, _ in
                            Task { await store.refresh() }
                            MenuBarPanelKeeper.keepOpen()
                        }

                        DatePicker(
                            "End date",
                            selection: $settings.customRangeEnd,
                            in: settings.customRangeStart...Date(),
                            displayedComponents: [.date]
                        )
                        .onChange(of: settings.customRangeEnd) { _, _ in
                            Task { await store.refresh() }
                            MenuBarPanelKeeper.keepOpen()
                        }

                        Text("Both dates are included. Future dates can't be selected.")
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

    private func usageTabVisibilityBinding(_ tab: UsageTab) -> Binding<Bool> {
        Binding(
            get: { settings.isUsageTabVisible(tab) },
            set: { visible in
                settings.setUsageTabVisible(tab, visible: visible)
                MenuBarPanelKeeper.keepOpen()
            }
        )
    }
}

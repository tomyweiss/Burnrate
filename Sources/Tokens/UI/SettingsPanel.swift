import SwiftUI

struct SettingsPanel: View {
    @Bindable var settings: SettingsStore
    var glassNamespace: Namespace.ID
    var onBack: () -> Void
    var onTestNotification: () -> Void

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
                        onTestNotification()
                        MenuBarPanelKeeper.keepOpen()
                    }
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
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0.0"
    }
}

import SwiftUI
import AppKit

@main
struct TokensApp: App {
    @State private var settings: SettingsStore
    @State private var store: UsageStore
    @State private var showingSettings = false

    init() {
        if CommandLine.arguments.contains("--status") {
            Self.runStatusAndExit()
        }

        let settings = SettingsStore()
        _settings = State(initialValue: settings)
        _store = State(initialValue: UsageStore(settings: settings))
    }

    private static func runStatusAndExit() -> Never {
        final class Box: @unchecked Sendable {
            var code: Int32 = 1
            var message = "ERROR Timed out fetching usage"
        }
        let box = Box()
        let group = DispatchGroup()
        group.enter()

        Task.detached {
            defer { group.leave() }
            do {
                let credentials = try TokenProvider.loadSessionCredentials()
                let api = CursorAPI()
                let now = Date()
                let midnight = Calendar.current.startOfDay(for: now)
                let startMs = Int64(midnight.timeIntervalSince1970 * 1000)
                let endMs = Int64(now.timeIntervalSince1970 * 1000)
                let events = try await api.fetchUsageEvents(
                    credentials: credentials,
                    startMs: startMs,
                    endMs: endMs
                )
                let snapshot = Aggregator.snapshot(
                    events: events,
                    now: now,
                    recentWindowMinutes: 10
                )
                box.message = String(
                    format: "OK $%.2f today (%d events)",
                    snapshot.todayDollars,
                    snapshot.eventCount
                )
                box.code = 0
            } catch {
                box.message = "ERROR \(error.localizedDescription)"
                box.code = 1
            }
        }

        _ = group.wait(timeout: .now() + 30)
        print(box.message)
        exit(box.code)
    }

    var body: some Scene {
        MenuBarExtra {
            DropdownView(
                store: store,
                settings: settings,
                showingSettings: $showingSettings
            )
            .onAppear {
                store.start()
            }
        } label: {
            Text(store.menuTitle)
                .monospacedDigit()
        }
        .menuBarExtraStyle(.window)

        Settings {
            SettingsView(settings: settings)
        }
    }
}

struct DropdownView: View {
    @Bindable var store: UsageStore
    @Bindable var settings: SettingsStore
    @Binding var showingSettings: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            Divider()
            if let error = store.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            modelList
            Divider()
            footer
        }
        .padding(12)
        .frame(width: 320)
        .sheet(isPresented: $showingSettings) {
            SettingsView(settings: settings)
                .frame(width: 360, height: 320)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Today")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline) {
                Text(String(format: "$%.2f", store.snapshot.todayDollars))
                    .font(.title2.monospacedDigit().weight(.semibold))
                Spacer()
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }
            Text(refreshSubtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }

    private var refreshSubtitle: String {
        if store.snapshot.fetchedAt == .distantPast {
            return "Not refreshed yet"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        let relative = formatter.localizedString(for: store.snapshot.fetchedAt, relativeTo: Date())
        return "Updated \(relative) · \(store.snapshot.eventCount) events"
    }

    private var modelList: some View {
        Group {
            if store.snapshot.models.isEmpty {
                Text("No usage since midnight")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 8)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 8) {
                        ForEach(store.snapshot.models) { model in
                            ModelRow(model: model)
                        }
                    }
                }
                .frame(maxHeight: 280)
            }
        }
    }

    private var footer: some View {
        HStack {
            Button("Refresh") {
                Task { await store.refresh() }
            }
            .disabled(store.isLoading)
            .keyboardShortcut("r")

            Button("Settings…") {
                showingSettings = true
            }

            Spacer()

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .keyboardShortcut("q")
        }
        .buttonStyle(.borderless)
    }
}

struct ModelRow: View {
    let model: ModelUsage

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Text(model.model)
                    .font(.callout.weight(.medium))
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(String(format: "$%.2f", model.costDollars))
                    .font(.callout.monospacedDigit())
            }
            Text(tokenSummary)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private var tokenSummary: String {
        var parts = [
            "in \(formatTokens(model.inputTokens))",
            "out \(formatTokens(model.outputTokens))"
        ]
        if model.cacheReadTokens > 0 {
            parts.append("cache \(formatTokens(model.cacheReadTokens))")
        }
        return parts.joined(separator: " · ")
    }

    private func formatTokens(_ value: Int) -> String {
        if value >= 1_000_000 {
            return String(format: "%.1fM", Double(value) / 1_000_000)
        }
        if value >= 1_000 {
            return String(format: "%.1fK", Double(value) / 1_000)
        }
        return "\(value)"
    }
}

struct SettingsView: View {
    @Bindable var settings: SettingsStore
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section("Refresh") {
                HStack {
                    Text("Interval")
                    Spacer()
                    TextField(
                        "",
                        value: $settings.refreshIntervalSeconds,
                        format: .number.precision(.fractionLength(0))
                    )
                    .frame(width: 60)
                    Text("sec")
                        .foregroundStyle(.secondary)
                }
            }

            Section("Anomaly alert") {
                HStack {
                    Text("Threshold")
                    Spacer()
                    Text("$")
                        .foregroundStyle(.secondary)
                    TextField(
                        "",
                        value: $settings.anomalyThresholdDollars,
                        format: .number.precision(.fractionLength(2))
                    )
                    .frame(width: 70)
                }
                HStack {
                    Text("Window")
                    Spacer()
                    TextField(
                        "",
                        value: $settings.anomalyWindowMinutes,
                        format: .number
                    )
                    .frame(width: 60)
                    Text("min")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Text("Cooldown")
                    Spacer()
                    TextField(
                        "",
                        value: $settings.anomalyCooldownMinutes,
                        format: .number
                    )
                    .frame(width: 60)
                    Text("min")
                        .foregroundStyle(.secondary)
                }
            }

            Section("General") {
                Toggle("Launch at login", isOn: $settings.launchAtLogin)
            }
        }
        .formStyle(.grouped)
        .padding()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
    }
}

import SwiftUI
import AppKit

enum UsageTab: String, CaseIterable, Identifiable {
    case models
    case sessions

    var id: String { rawValue }

    var title: String {
        switch self {
        case .models: "Models"
        case .sessions: "Sessions"
        }
    }
}

struct UsagePanel: View {
    @Bindable var store: UsageStore
    @Bindable var settings: SettingsStore
    @Bindable var updates: UpdateManager
    var glassNamespace: Namespace.ID
    var onOpenSettings: () -> Void

    @AppStorage("panelTab") private var panelTabRaw = UsageTab.models.rawValue
    @State private var expandedModels: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var panelTab: Binding<UsageTab> {
        Binding(
            get: { UsageTab(rawValue: panelTabRaw) ?? .models },
            set: { panelTabRaw = $0.rawValue }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            if !store.hasCompletedFetch, store.isLoading {
                UsageSkeletonView()
            } else {
                header
                    .padding(.horizontal, 16)
                    .padding(.top, 14)
                    .padding(.bottom, 10)

                if let update = updates.availableUpdate {
                    updateBanner(update)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 8)
                }

                content
                    .frame(maxWidth: .infinity, maxHeight: .infinity)

                footer
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(MoneyFormat.dollars(store.snapshot.todayDollars))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .snappy, value: store.snapshot.todayCostCents)
                Spacer()
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if store.snapshot.recentDollars > 0 {
                burnPill
            }

            SparklineView(
                hourlyCostCents: store.snapshot.hourlyCostCents,
                now: Date()
            )

            Text(updatedCaption)
                .font(.caption)
                .foregroundStyle(store.isStale ? Color.orange : Color.secondary)
        }
    }

    private var burnPill: some View {
        let threshold = max(settings.anomalyThresholdDollars, 0.01)
        let ratio = store.snapshot.recentDollars / threshold
        let tint: Color = {
            if ratio >= 1 { return .red }
            if ratio >= 0.25 { return .orange }
            return .secondary
        }()

        return Text(
            "▲ \(MoneyFormat.dollars(store.snapshot.recentDollars)) · \(settings.anomalyWindowMinutes)m"
        )
        .font(.caption.weight(.semibold).monospacedDigit())
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .glassEffect(.regular.tint(tint))
        .clipShape(Capsule())
        .help("Spend in the last \(settings.anomalyWindowMinutes) minutes (your spike window)")
    }

    private var updatedCaption: String {
        if store.snapshot.fetchedAt == .distantPast {
            return "Not refreshed yet"
        }
        if store.isStale {
            return "Data from \(RelativeTimeFormat.clockTime(store.snapshot.fetchedAt)) (stale)"
        }
        let relative = RelativeTimeFormat.string(from: store.snapshot.fetchedAt)
        return "Updated \(relative) · \(store.snapshot.eventCount) events"
    }

    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            if let error = store.lastError {
                ErrorBanner(message: error) {
                    Task { await store.refresh() }
                    MenuBarPanelKeeper.keepOpen()
                }
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
            }

            if store.hasCompletedFetch,
               store.snapshot.todayCostCents == 0,
               store.snapshot.models.isEmpty,
               store.lastError == nil {
                EmptySpendView()
            } else {
                Picker("Scope", selection: panelTab) {
                    ForEach(UsageTab.allCases) { tab in
                        Text(tab.title).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .padding(.horizontal, 12)
                .padding(.bottom, 8)
                .onChange(of: panelTabRaw) { _, _ in
                    MenuBarPanelKeeper.keepOpen()
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        switch panelTab.wrappedValue {
                        case .models:
                            ForEach(store.snapshot.models) { model in
                                ModelRowView(
                                    model: model,
                                    todayCostCents: store.snapshot.todayCostCents,
                                    isExpanded: expandedModels.contains(model.id),
                                    reduceMotion: reduceMotion,
                                    onToggle: { toggleExpanded(model.id) }
                                )
                                Divider().opacity(0.35)
                            }
                        case .sessions:
                            ForEach(store.snapshot.sessionsAcrossModels) { session in
                                SessionRowView(
                                    session: session,
                                    todayCostCents: store.snapshot.todayCostCents,
                                    showModelChips: true,
                                    showShareBar: true
                                )
                                Divider().opacity(0.35)
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    private func toggleExpanded(_ modelID: String) {
        if reduceMotion {
            if expandedModels.contains(modelID) {
                expandedModels.remove(modelID)
            } else {
                expandedModels.insert(modelID)
            }
        } else {
            withAnimation(.snappy) {
                if expandedModels.contains(modelID) {
                    expandedModels.remove(modelID)
                } else {
                    expandedModels.insert(modelID)
                }
            }
        }
        MenuBarPanelKeeper.keepOpen()
    }

    private var footer: some View {
        GlassEffectContainer {
            HStack {
                Button {
                    onOpenSettings()
                    MenuBarPanelKeeper.keepOpen()
                } label: {
                    footerIcon("gearshape")
                }
                .buttonStyle(.borderless)
                .help("Settings")
                .glassEffect(.regular.interactive())
                .glassEffectID("settings-gear", in: glassNamespace)

                Spacer()

                HStack(spacing: 8) {
                    Button {
                        Task { await store.refresh() }
                        MenuBarPanelKeeper.keepOpen()
                    } label: {
                        footerIcon("arrow.clockwise")
                    }
                    .buttonStyle(.borderless)
                    .disabled(store.isLoading)
                    .keyboardShortcut("r")
                    .help("Refresh")
                    .glassEffect(.regular.interactive())

                    Menu {
                        Button("Check for Updates…") {
                            Task { await updates.checkForUpdates(userInitiated: true) }
                            MenuBarPanelKeeper.keepOpen()
                        }
                        if let update = updates.availableUpdate {
                            Button("Install \(update.version)…") {
                                Task { await updates.installAvailableUpdate() }
                            }
                            .disabled(updates.isInstalling)
                        }
                        Button("Open Cursor Dashboard") {
                            if let url = URL(string: "https://cursor.com/dashboard") {
                                NSWorkspace.shared.open(url)
                            }
                            MenuBarPanelKeeper.keepOpen()
                        }
                        Divider()
                        Button("Quit") {
                            NSApplication.shared.terminate(nil)
                        }
                        .keyboardShortcut("q")
                    } label: {
                        footerIcon("ellipsis")
                    }
                    .buttonStyle(.borderless)
                    .help("More")
                    .glassEffect(.regular.interactive())
                }
            }
        }
        .foregroundStyle(.primary.opacity(0.9))
    }

    private func updateBanner(_ update: AvailableUpdate) -> some View {
        HStack(alignment: .center, spacing: 10) {
            Image(systemName: "arrow.down.circle.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Update \(update.version) available")
                    .font(.caption.weight(.semibold))
                Text("Not notarized — replaces this app, then relaunches.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            Button(updates.isInstalling ? "Installing…" : "Install") {
                Task { await updates.installAvailableUpdate() }
                MenuBarPanelKeeper.keepOpen()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(updates.isInstalling)
        }
        .padding(10)
        .background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func footerIcon(_ systemName: String) -> some View {
        Image(systemName: systemName)
            .font(.body.weight(.medium))
            .imageScale(.medium)
            .frame(width: 30, height: 30, alignment: .center)
            .contentShape(Rectangle())
    }
}

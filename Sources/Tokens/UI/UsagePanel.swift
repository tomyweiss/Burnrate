import SwiftUI
import AppKit

enum UsageTab: String, CaseIterable, Identifiable {
    case models
    case sessions
    case skills
    case feed

    var id: String { rawValue }

    var title: String {
        switch self {
        case .models: "Models"
        case .sessions: "Sessions"
        case .skills: "Skills"
        case .feed: "Feed"
        }
    }
}

/// Which cost figure drives sorting and the row preview on Models/Skills tabs.
enum CostMetric: String, CaseIterable, Identifiable {
    case total
    case average

    var id: String { rawValue }

    var title: String {
        switch self {
        case .total: "Total $"
        case .average: "Avg $"
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
    @State private var selectedSession: SessionUsage?
    @State private var selectedSkill: SkillUsage?
    @AppStorage("modelsCostMetric") private var modelsMetricRaw = CostMetric.total.rawValue
    @AppStorage("skillsCostMetric") private var skillsMetricRaw = CostMetric.total.rawValue
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
        .onDisappear {
            selectedSession = nil
            selectedSkill = nil
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(MoneyFormat.dollars(store.snapshot.windowDollars))
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(reduceMotion ? .identity : .numericText())
                    .animation(reduceMotion ? nil : .snappy, value: store.snapshot.windowCostCents)

                Spacer(minLength: 8)

                if AppIdentity.isDevBuild {
                    Text("DEV")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Capsule().fill(Color.orange))
                        .accessibilityLabel("Development build")
                }

                timelinePicker

                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }
            }

            if settings.usageTimelinePreset == .thisBilling {
                Text("Since \(store.snapshot.window.sparklineStartLabel())")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if store.snapshot.recentDollars > 0 {
                burnPill
            }

            SparklineView(
                sparklineCostCents: store.snapshot.sparklineCostCents,
                window: store.snapshot.window,
                now: Date()
            )

            Text(updatedCaption)
                .font(.caption)
                .foregroundStyle(store.isStale ? Color.orange : Color.secondary)
        }
    }

    private var timelinePicker: some View {
        Picker("Timeline", selection: $settings.usageTimelinePreset) {
            ForEach(UsageTimelinePreset.allCases) { preset in
                Text(preset.displayName).tag(preset)
            }
        }
        .pickerStyle(.menu)
        .labelsHidden()
        .font(.subheadline.weight(.medium))
        .foregroundStyle(.secondary)
        .fixedSize()
        .onChange(of: settings.usageTimelinePreset) { _, _ in
            Task { await store.refresh() }
            MenuBarPanelKeeper.keepOpen()
        }
    }

    private var burnPill: some View {
        let tint = store.burnLevel.swiftUIColor

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
               store.snapshot.windowCostCents == 0,
               store.snapshot.models.isEmpty,
               store.lastError == nil {
                EmptySpendView(message: store.snapshot.window.emptyStateMessage)
            } else if let skill = selectedSkill {
                SkillDetailView(
                    // Prefer the freshest snapshot copy; fall back to the tapped one.
                    skill: store.snapshot.skills
                        .first { $0.skill == skill.skill } ?? skill,
                    prompts: store.snapshot.prompts
                        .filter { $0.skills.contains(skill.skill) },
                    onBack: {
                        selectedSkill = nil
                        MenuBarPanelKeeper.keepOpen()
                    }
                )
            } else if let selected = selectedSession {
                SessionDetailView(
                    // Prefer the freshest snapshot copy; fall back to the tapped one.
                    session: store.snapshot.sessionsAcrossModels
                        .first { $0.conversationId == selected.conversationId } ?? selected,
                    prompts: store.snapshot.prompts
                        .filter { $0.conversationId == selected.conversationId },
                    onBack: {
                        selectedSession = nil
                        MenuBarPanelKeeper.keepOpen()
                    }
                )
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

                if panelTab.wrappedValue == .models {
                    metricPicker($modelsMetricRaw)
                } else if panelTab.wrappedValue == .skills, !store.snapshot.skills.isEmpty {
                    metricPicker($skillsMetricRaw)
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        switch panelTab.wrappedValue {
                        case .models:
                            ForEach(displayedModels) { model in
                                ModelRowView(
                                    model: model,
                                    windowCostCents: store.snapshot.windowCostCents,
                                    isExpanded: expandedModels.contains(model.id),
                                    reduceMotion: reduceMotion,
                                    showLocationSubtitle: settings.showLocationSubtitle,
                                    hideArchivedSessions: settings.hideArchivedSessions,
                                    metric: modelsMetric,
                                    maxAverageDollars: maxModelAverageDollars,
                                    onToggle: { toggleExpanded(model.id) }
                                )
                                Divider().opacity(0.35)
                            }
                        case .sessions:
                            ForEach(visibleSessions) { session in
                                SessionRowView(
                                    session: session,
                                    windowCostCents: store.snapshot.windowCostCents,
                                    showModelChips: true,
                                    showShareBar: true,
                                    showLocationSubtitle: settings.showLocationSubtitle,
                                    onOpen: {
                                        selectedSession = session
                                        MenuBarPanelKeeper.keepOpen()
                                    }
                                )
                                Divider().opacity(0.35)
                            }
                        case .skills:
                            if store.snapshot.skills.isEmpty {
                                tabEmptyText("No skill invocations in this window")
                            } else {
                                ForEach(displayedSkills) { skill in
                                    SkillRowView(
                                        skill: skill,
                                        windowCostCents: store.snapshot.windowCostCents,
                                        metric: skillsMetric,
                                        maxAverageDollars: maxSkillAverageDollars,
                                        onOpen: {
                                            selectedSkill = skill
                                            MenuBarPanelKeeper.keepOpen()
                                        }
                                    )
                                    Divider().opacity(0.35)
                                }
                            }
                        case .feed:
                            if store.snapshot.prompts.isEmpty {
                                tabEmptyText("No prompts found for this window")
                            } else {
                                ForEach(store.snapshot.prompts) { prompt in
                                    PromptRowView(prompt: prompt)
                                    Divider().opacity(0.35)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 8)
                    .padding(.bottom, 8)
                }
            }
        }
    }

    // MARK: - Cost metric (Total vs Avg)

    private var modelsMetric: CostMetric {
        CostMetric(rawValue: modelsMetricRaw) ?? .total
    }

    private var skillsMetric: CostMetric {
        CostMetric(rawValue: skillsMetricRaw) ?? .total
    }

    private var displayedModels: [ModelUsage] {
        let models = store.snapshot.models
        guard modelsMetric == .average else { return models }
        return models.sorted { $0.averageCostDollars > $1.averageCostDollars }
    }

    private var displayedSkills: [SkillUsage] {
        let skills = store.snapshot.skills
        guard skillsMetric == .average else { return skills }
        return skills.sorted {
            $0.averageCostDollars == $1.averageCostDollars
                ? $0.lastUsedMs > $1.lastUsedMs
                : $0.averageCostDollars > $1.averageCostDollars
        }
    }

    private var maxModelAverageDollars: Double {
        store.snapshot.models.map(\.averageCostDollars).max() ?? 0
    }

    private var maxSkillAverageDollars: Double {
        store.snapshot.skills.map(\.averageCostDollars).max() ?? 0
    }

    private func metricPicker(_ selection: Binding<String>) -> some View {
        HStack {
            Spacer()
            Picker("Cost metric", selection: selection) {
                ForEach(CostMetric.allCases) { metric in
                    Text(metric.title).tag(metric.rawValue)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            .fixedSize()
            .onChange(of: selection.wrappedValue) { _, _ in
                MenuBarPanelKeeper.keepOpen()
            }
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 8)
    }

    private func tabEmptyText(_ message: String) -> some View {
        Text(message)
            .font(.callout)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 24)
    }

    private var visibleSessions: [SessionUsage] {
        let sessions = store.snapshot.sessionsAcrossModels
        guard settings.hideArchivedSessions else { return sessions }
        return sessions.filter { !$0.isArchived }
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

                signature

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

    private var signature: some View {
        HStack(spacing: 3) {
            Text("Powered by")
                .font(.caption2)
                .foregroundStyle(.tertiary)
            Link(destination: URL(string: "https://getdrift.ai")!) {
                Text("Drift Security")
                    .font(.caption2.weight(.medium))
                    .underline()
                    .foregroundStyle(.secondary)
            }
            .help("getdrift.ai")
        }
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

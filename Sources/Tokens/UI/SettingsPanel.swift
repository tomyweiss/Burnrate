import SwiftUI
import TokensCore

/// A page opened from the Settings list.
enum SettingsPage: String, CaseIterable, Identifiable {
    case sources
    case menuBar
    case spikeAlert
    case stopClaude
    case panel
    case data
    case updates

    var id: String { rawValue }

    var title: String {
        switch self {
        case .sources: "Sources"
        case .menuBar: "Menu bar"
        case .spikeAlert: "Spike alert"
        case .stopClaude: "Stop Claude Code"
        case .panel: "Panel"
        case .data: "Data"
        case .updates: "Updates"
        }
    }
}

/// A short list of topics, each showing its current value. Selecting one opens its page.
struct SettingsPanel: View {
    @Bindable var settings: SettingsStore
    @Bindable var updates: UpdateManager
    @Bindable var store: UsageStore
    /// Nil shows the list. Held by the root so returning from the change log reopens Updates.
    @Binding var page: SettingsPage?
    var onBack: () -> Void
    var onOpenChangeLog: () -> Void
    @Environment(ClaudeCodeStore.self) private var claudeCode
    @Environment(SpendCapController.self) private var spendCap

    var body: some View {
        VStack(spacing: 0) {
            header
                .padding(.horizontal, 14)
                .padding(.vertical, 10)

            Divider()

            Form {
                switch page {
                case nil: listSections
                case .sources: sourcesSections
                case .menuBar: menuBarSections
                case .spikeAlert: spikeAlertSections
                case .stopClaude: stopClaudeSections
                case .panel: panelSections
                case .data: dataSections
                case .updates: updatesSections
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)

            if page == nil {
                signature
                    .padding(.bottom, 12)
            }
        }
        .onAppear { MenuBarPanelKeeper.keepOpen() }
    }

    private var header: some View {
        ZStack {
            Text(page?.title ?? "Settings")
                .font(.headline)

            HStack {
                Button {
                    if page == nil {
                        onBack()
                    } else {
                        page = nil
                    }
                    MenuBarPanelKeeper.keepOpen()
                } label: {
                    Label(page == nil ? "Usage" : "Settings", systemImage: "chevron.left")
                }
                .buttonStyle(.plain)

                Spacer()

                if page == nil {
                    Text(AppIdentity.versionLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
    }

    // MARK: - List

    @ViewBuilder
    private var listSections: some View {
        Section {
            ForEach(SettingsPage.allCases) { item in
                navigationRow(item.title, value: summary(for: item)) {
                    page = item
                }
            }
        }

        Section {
            keepOpenToggle("Launch at login", isOn: $settings.launchAtLogin)
            keepOpenToggle("Blur session & prompt titles", isOn: $settings.blurSensitiveContent)
        }
    }

    private func summary(for item: SettingsPage) -> String {
        switch item {
        case .sources:
            SettingsSummary.sources(
                cursorEnabled: settings.cursorEnabled,
                claudeEnabled: settings.claudeCodeEnabled
            )
        case .menuBar:
            SettingsSummary.menuBar(menuBar.input)
        case .spikeAlert:
            SettingsSummary.spikeAlert(
                thresholdDollars: settings.anomalyThresholdDollars,
                windowMinutes: settings.anomalyWindowMinutes
            )
        case .stopClaude:
            SettingsSummary.stopClaude(
                isArmed: spendCap.isArmed,
                isTripped: spendCap.isTripped
            )
        case .panel:
            SettingsSummary.panel(visibleTabCount: settings.visibleUsageTabs.count)
        case .data:
            SettingsSummary.data(
                refreshIntervalSeconds: settings.refreshIntervalSeconds,
                timezoneIdentifier: settings.usageTimezoneIdentifier
            )
        case .updates:
            SettingsSummary.updates(
                versionLabel: AppIdentity.versionLabel,
                pendingTitle: updates.isDevBuild ? nil : updates.pendingUpdate?.title
            )
        }
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

    // MARK: - Sources

    @ViewBuilder
    private var sourcesSections: some View {
        Section {
            Toggle(
                PanelSourceResolver.cursorSettingsLabel(signedIn: store.isCursorAvailable),
                isOn: $settings.cursorEnabled
            )
            .onChange(of: settings.cursorEnabled) { _, enabled in
                if enabled {
                    Task { await store.refresh() }
                }
                MenuBarPanelKeeper.keepOpen()
            }
        }

        Section {
            Toggle(
                PanelSourceResolver.claudeSettingsLabel(
                    installed: claudeCode.isInstalled,
                    sessionCount: claudeCode.sessionCount
                ),
                isOn: $settings.claudeCodeEnabled
            )
            .onChange(of: settings.claudeCodeEnabled) { _, _ in
                Task { await claudeCode.refresh() }
                MenuBarPanelKeeper.keepOpen()
            }

            if settings.claudeCodeEnabled {
                Toggle("Show plan limits", isOn: $settings.claudeLimitsEnabled)
                    .onChange(of: settings.claudeLimitsEnabled) { _, enabled in
                        if enabled {
                            Task { await claudeCode.refresh() }
                        } else {
                            claudeCode.clearPlanLimits()
                        }
                        MenuBarPanelKeeper.keepOpen()
                    }
                caption("Reads your Claude Code login from Keychain to fetch your 5-hour and weekly limits. macOS may ask for permission once.")
            }
        }
        .onAppear {
            Task { await claudeCode.refreshInstallStatus() }
        }
    }

    // MARK: - Menu bar

    private var menuBar: MenuBarState.Presentation {
        MenuBarState.presentation(settings: settings, store: store, claudeCode: claudeCode)
    }

    @ViewBuilder
    private var menuBarSections: some View {
        Section {
            LabeledContent("Preview") {
                menuBarPreview
            }
        }

        if settings.cursorEnabled {
            Section("Cursor") {
                keepOpenToggle("Window spend", isOn: $settings.statusBarShowsWindowSpend)
                keepOpenToggle("Cursor models", isOn: $settings.statusBarShowsCursorModels)
                keepOpenToggle("Other models", isOn: $settings.statusBarShowsOtherModels)
                keepOpenToggle("Grok Bot", isOn: $settings.statusBarShowsGrokBot)
            }
        }

        if settings.claudeCodeEnabled {
            Section("Claude Code") {
                Toggle("Spend (estimated)", isOn: claudeSpendBinding)
                    .onChange(of: settings.statusBarClaudeSpendPreference) { _, _ in
                        MenuBarPanelKeeper.keepOpen()
                    }
                if settings.claudeLimitsEnabled {
                    keepOpenToggle("Session limit (5h)", isOn: $settings.statusBarShowsClaudeFiveHour)
                    keepOpenToggle("Weekly limit", isOn: $settings.statusBarShowsClaudeWeekly)
                }
            }
        }
    }

    /// The menu bar item as it looks with the current choices. Only the flame when nothing is on.
    private var menuBarPreview: some View {
        let bar = menuBar
        return HStack(spacing: 5) {
            Image(systemName: bar.burnLevel.symbolName)
            if let text = bar.statusText {
                Text(text)
                    .monospacedDigit()
                    .lineLimit(1)
            }
        }
        .font(.callout.weight(.medium))
        .foregroundStyle(.white)
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.7), in: RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(bar.accessibilityText ?? "Flame only")
    }

    // MARK: - Spike alert

    @ViewBuilder
    private var spikeAlertSections: some View {
        Section {
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

            caption(
                String(
                    format: "Alert when ≥ %@ is spent in %d minutes.",
                    MoneyFormat.dollars(settings.anomalyThresholdDollars),
                    settings.anomalyWindowMinutes
                )
            )
        }

        Section {
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
    }

    // MARK: - Stop Claude Code

    @ViewBuilder
    private var stopClaudeSections: some View {
        @Bindable var spendCap = spendCap

        Section {
            keepOpenToggle("Estimated spend reaches a cap", isOn: $spendCap.capEnabled)
            if spendCap.capEnabled {
                Picker("Cap", selection: $spendCap.capDollars) {
                    ForEach(capChoices, id: \.self) { dollars in
                        Text(MoneyFormat.dollars(dollars)).tag(dollars)
                    }
                }
                .onChange(of: spendCap.capDollars) { _, _ in MenuBarPanelKeeper.keepOpen() }
            }
            keepOpenToggle("A plan limit is used up", isOn: planLimitBinding)
            caption(
                "Spend is Burnrate's estimate since you arm the stop. Plan limits are the 5-hour "
                    + "and weekly windows; past them, work may be billed as extra usage."
            )
        } header: {
            Text("Stop agents when")
        }

        Section {
            keepOpenToggle(
                "Stop processes after \(Int(SpendCap.graceInterval / 60)) min",
                isOn: $spendCap.stopsProcesses
            )
            caption(
                spendCap.hookInstalled
                    ? "Agents are first asked to stop by the stop hook. Processes still running after the grace period get SIGTERM, then SIGKILL."
                    : "Without the stop hook, Claude Code processes are stopped right away."
            )
        }

        Section {
            Text(stopStatus)
                .foregroundStyle(spendCap.isTripped ? Color.orange : Color.primary)
            if spendCap.isTripped {
                Button("Re-arm") { spendCap.arm(); MenuBarPanelKeeper.keepOpen() }
                if spendCap.stopsProcesses, !spendCap.processesStopped {
                    Button("Stop processes now") { spendCap.stopProcessesNow(); MenuBarPanelKeeper.keepOpen() }
                        .disabled(spendCap.isStoppingProcesses)
                }
                Button("Turn off") { spendCap.disarm(); MenuBarPanelKeeper.keepOpen() }
            } else if spendCap.isArmed {
                Button("Turn off") { spendCap.disarm(); MenuBarPanelKeeper.keepOpen() }
            } else {
                Button("Arm now") { spendCap.arm(); MenuBarPanelKeeper.keepOpen() }
                    .disabled(!settings.claudeCodeEnabled || !spendCap.hasTrigger)
            }
            if !settings.claudeCodeEnabled {
                caption("Turn on Claude Code in Sources to use the stop.")
            }
        }

        Section {
            keepOpenToggle("Launch Burnrate at login", isOn: $settings.launchAtLogin)
            caption(
                "The stop only watches while Burnrate is open. Launching at login keeps it "
                    + "going after a restart, and Burnrate asks before quitting while the stop is armed."
            )
        }

        Section {
            HStack {
                Text("Stop hook")
                Spacer()
                Text(spendCap.hookInstalled ? "Installed" : "Not installed")
                    .foregroundStyle(.secondary)
            }
            if spendCap.hookInstalled {
                Button("Remove stop hook") { spendCap.removeHook(); MenuBarPanelKeeper.keepOpen() }
            } else {
                Button("Install stop hook") { spendCap.installHook(); MenuBarPanelKeeper.keepOpen() }
            }
            caption(
                "Adds a PreToolUse hook to ~/.claude/settings.json (a backup is kept next to it). "
                    + "It does nothing until the stop trips, then blocks every tool call and tells "
                    + "Claude to stop and summarize. New Claude Code sessions pick it up; running ones may need a restart."
            )
            if let error = spendCap.hookError {
                Text(error).font(.caption).foregroundStyle(.orange)
            }
        }
        .onAppear { spendCap.refreshHookStatus() }
    }

    private var capChoices: [Double] {
        let choices = SpendCap.dollarChoices
        return choices.contains(spendCap.capDollars) ? choices : (choices + [spendCap.capDollars]).sorted()
    }

    private var planLimitBinding: Binding<Bool> {
        Binding(
            get: { spendCap.planLimitEnabled },
            set: { on in
                spendCap.planLimitEnabled = on
                if on { settings.claudeLimitsEnabled = true }
            }
        )
    }

    private var stopStatus: String {
        if spendCap.isTripped {
            return "Stopped: \(spendCap.tripDetail ?? "the stop tripped")"
        }
        if spendCap.isArmed {
            return SpendCapSummary.armed(
                capEnabled: spendCap.capEnabled,
                capDollars: spendCap.capDollars,
                spentCents: spendCap.spentCents,
                planLimitEnabled: spendCap.planLimitEnabled,
                armedAt: spendCap.armedAt
            )
        }
        return "Off"
    }

    // MARK: - Panel

    @ViewBuilder
    private var panelSections: some View {
        Section("Tabs") {
            ForEach(UsageTab.allCases) { tab in
                Toggle(tab.title, isOn: usageTabVisibilityBinding(tab))
                    .disabled(
                        settings.isUsageTabVisible(tab)
                            && settings.visibleUsageTabs.count == 1
                    )
            }
            caption("At least one tab must stay visible.")
        }

        Section("Sessions") {
            keepOpenToggle("Show location subtitle", isOn: $settings.showLocationSubtitle)
            keepOpenToggle("Hide archived sessions", isOn: $settings.hideArchivedSessions)
        }
    }

    // MARK: - Data

    /// Billing day sets the This billing window and where Claude Code's cycle spend starts.
    private var showsBillingDay: Bool {
        settings.usageTimelinePreset == .thisBilling || settings.claudeCodeEnabled
    }

    @ViewBuilder
    private var dataSections: some View {
        Section {
            Picker("Poll every", selection: $settings.refreshIntervalSeconds) {
                ForEach(SettingsStore.refreshIntervalOptions, id: \.self) { seconds in
                    Text(SettingsStore.intervalLabel(seconds)).tag(seconds)
                }
            }
            .onChange(of: settings.refreshIntervalSeconds) { _, _ in
                MenuBarPanelKeeper.keepOpen()
            }

            timezonePicker

            if showsBillingDay {
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
            Section("Custom range") {
                customRangePickers
            }
        }
    }

    @ViewBuilder
    private var customRangePickers: some View {
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

        caption("Both dates are included. Future dates can't be selected.")
    }

    // MARK: - Updates

    @ViewBuilder
    private var updatesSections: some View {
        Section {
            if updates.isDevBuild {
                caption("Updates are disabled in Burnrate-dev. Reinstall with scripts/package.sh --dev.")
            } else {
                if let pendingUpdate = updates.pendingUpdate {
                    HStack {
                        Text(pendingUpdate.title)
                        Spacer()
                        Button(pendingUpdate.actionTitle) {
                            updates.openPendingUpdate()
                        }
                        .buttonStyle(.borderedProminent)
                    }
                }

                Toggle("Check for updates automatically", isOn: $settings.autoCheckForUpdates)
                    .onChange(of: settings.autoCheckForUpdates) { _, _ in
                        updates.autoCheckIfNeeded()
                        MenuBarPanelKeeper.keepOpen()
                    }

                Button("Check for Updates…") {
                    Task { await updates.checkForUpdates(userInitiated: true) }
                }

                if updates.usesSparkle {
                    caption("Checks once a day and lets you know when an update is ready.")
                }

                if let status = updates.statusMessage {
                    Text(status)
                        .font(.caption)
                        .foregroundStyle(updates.lastError == nil ? Color.secondary : Color.red)
                }
            }
        }

        Section {
            navigationRow("Change log", value: nil) {
                onOpenChangeLog()
            }
        }
    }

    // MARK: - Helpers

    /// Reads the effective Claude spend default, and writes the key only when
    /// the user changes the toggle.
    private var claudeSpendBinding: Binding<Bool> {
        Binding(
            get: {
                settings.showsClaudeSpend(
                    cursorAvailable: store.isCursorAvailable,
                    claudeInstalled: claudeCode.isInstalled
                )
            },
            set: { settings.statusBarShowsClaudeSpend = $0 }
        )
    }

    private func keepOpenToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn)
            .onChange(of: isOn.wrappedValue) { _, _ in
                MenuBarPanelKeeper.keepOpen()
            }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
    }

    /// A row that opens another page, with the current value before the chevron.
    private func navigationRow(_ title: String, value: String?, action: @escaping () -> Void) -> some View {
        Button {
            action()
            MenuBarPanelKeeper.keepOpen()
        } label: {
            HStack(spacing: 6) {
                Text(title)
                Spacer(minLength: 8)
                if let value {
                    Text(value)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
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

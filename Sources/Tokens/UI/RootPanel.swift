import SwiftUI

enum ChangeLogOrigin: Hashable {
    case settings
    case usage
}

enum PanelRoute: Hashable {
    case usage
    case settings
    case community
    case changeLog(ChangeLogOrigin)

    var interactionKey: String {
        switch self {
        case .usage: "usage"
        case .settings: "settings"
        case .community: "community"
        case .changeLog: "changelog"
        }
    }
}

struct RootPanel: View {
    @Bindable var store: UsageStore
    @Bindable var settings: SettingsStore
    @Bindable var updates: UpdateManager
    @Bindable var community: CommunityStore
    var interactionTracker: InteractionTracker
    @State private var route: PanelRoute = .usage
    @State private var changeLogHighlightVersion: String?
    @State private var changeLogReleaseNotes: String?
    @Namespace private var glassNamespace
    @AppStorage("panelTab") private var panelTabRaw = UsageTab.models.rawValue
    @AppStorage("panelSource") private var panelSourceRaw = ""
    @Environment(ClaudeCodeStore.self) private var claudeCode

    private var panelCostStyle: CostStyle {
        let source = PanelSourceResolver.displayedSource(
            stored: UsageSource(rawValue: panelSourceRaw),
            cursorAvailable: store.isCursorAvailable,
            cursorEnabled: settings.cursorEnabled,
            claudeInstalled: claudeCode.isInstalled,
            claudeEnabled: settings.claudeCodeEnabled
        )
        return source?.costStyle ?? .billed
    }

    private let panelWidth: CGFloat = 540

    /// List tabs are 820pt. Bench keeps the taller scatter.
    private var panelHeight: CGFloat {
        route == .usage && panelTabRaw == UsageTab.bench.rawValue ? 860 : 820
    }

    var body: some View {
        Group {
            switch route {
            case .usage:
                UsagePanel(
                    store: store,
                    settings: settings,
                    glassNamespace: glassNamespace,
                    onOpenSettings: { route = .settings },
                    onOpenCommunity: { route = .community },
                    onOpenChangeLog: { version, notes in
                        changeLogHighlightVersion = version
                        changeLogReleaseNotes = notes
                        route = .changeLog(.usage)
                    },
                    onUsageTabChange: { tab in
                        interactionTracker.recordTabChange(tab.rawValue)
                    }
                )
            case .settings:
                SettingsPanel(
                    settings: settings,
                    updates: updates,
                    store: store,
                    onBack: { route = .usage },
                    onOpenChangeLog: {
                        changeLogHighlightVersion = nil
                        changeLogReleaseNotes = nil
                        route = .changeLog(.settings)
                    }
                )
            case .changeLog(let origin):
                ChangeLogView(
                    sections: ChangeLog.displaySections(
                        highlightVersion: changeLogHighlightVersion,
                        releaseNotes: changeLogReleaseNotes
                    ),
                    backTitle: origin == .settings ? "Settings" : "Usage",
                    onBack: {
                        changeLogHighlightVersion = nil
                        changeLogReleaseNotes = nil
                        route = origin == .settings ? .settings : .usage
                    }
                )
            case .community:
                CommunityPanel(
                    community: community,
                    glassNamespace: glassNamespace,
                    onBack: { route = .usage }
                )
            }
        }
        .frame(width: panelWidth, height: panelHeight)
        .panelSurfaceBackground()
        .environment(\.blurSensitiveContent, settings.blurSensitiveContent)
        .environment(\.costStyle, panelCostStyle)
        .animation(.snappy, value: panelTabRaw)
        .animation(.snappy, value: route)
        .onAppear {
            MenuBarPanelKeeper.panelDidShow()
            updates.autoCheckIfNeeded()
            interactionTracker.recordPanelOpen()
        }
        .onDisappear {
            MenuBarPanelKeeper.panelDidHide()
            route = .usage
        }
        .onChange(of: route) { oldRoute, newRoute in
            MenuBarPanelKeeper.keepOpen()
            guard oldRoute != newRoute else { return }
            interactionTracker.recordTabChange(newRoute.interactionKey)
        }
        .onChange(of: settings.billingDayOfMonth) { _, _ in
            Task { await store.refresh(reuseEventsIfPossible: true) }
            Task { await claudeCode.refresh() }
        }
        .onChange(of: settings.usageTimezoneIdentifier) { _, _ in
            Task { await store.refresh(reuseEventsIfPossible: true) }
            Task { await claudeCode.refresh() }
        }
        .onChange(of: settings.usageTimelinePreset) { _, _ in
            Task { await claudeCode.refresh() }
        }
        .onChange(of: settings.customRangeStart) { _, _ in
            Task { await claudeCode.refresh() }
        }
        .onChange(of: settings.customRangeEnd) { _, _ in
            Task { await claudeCode.refresh() }
        }
        .onChange(of: settings.cursorEnabled) { _, enabled in
            if enabled {
                Task { await store.refresh() }
            }
        }
        .onChange(of: settings.claudeCodeEnabled) { _, _ in
            Task { await claudeCode.refresh() }
        }
    }
}

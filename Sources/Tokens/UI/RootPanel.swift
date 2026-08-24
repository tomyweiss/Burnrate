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

    private let panelWidth: CGFloat = 460

    /// The Bench scatter needs more vertical room than the list tabs.
    private var panelHeight: CGFloat {
        route == .usage && panelTabRaw == UsageTab.bench.rawValue ? 720 : 580
    }

    var body: some View {
        Group {
            switch route {
            case .usage:
                UsagePanel(
                    store: store,
                    settings: settings,
                    updates: updates,
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
        .environment(\.blurSensitiveContent, settings.blurSensitiveContent)
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
        }
        .onChange(of: settings.usageTimezoneIdentifier) { _, _ in
            Task { await store.refresh(reuseEventsIfPossible: true) }
        }
    }
}

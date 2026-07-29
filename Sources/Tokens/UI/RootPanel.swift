import SwiftUI

enum PanelRoute: Hashable {
    case usage
    case settings
    case community

    var interactionKey: String {
        switch self {
        case .usage: "usage"
        case .settings: "settings"
        case .community: "community"
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
                    onUsageTabChange: { tab in
                        interactionTracker.recordTabChange(
                            tab.rawValue,
                            ifEnabled: settings.shareCommunityUsage
                        )
                    }
                )
            case .settings:
                SettingsPanel(
                    settings: settings,
                    updates: updates,
                    store: store,
                    glassNamespace: glassNamespace,
                    onBack: { route = .usage }
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
            interactionTracker.recordPanelOpen(ifEnabled: settings.shareCommunityUsage)
        }
        .onDisappear {
            MenuBarPanelKeeper.panelDidHide()
            route = .usage
        }
        .onChange(of: route) { oldRoute, newRoute in
            MenuBarPanelKeeper.keepOpen()
            guard oldRoute != newRoute else { return }
            interactionTracker.recordTabChange(
                newRoute.interactionKey,
                ifEnabled: settings.shareCommunityUsage
            )
        }
        .onChange(of: settings.billingDayOfMonth) { _, _ in
            Task { await store.refresh() }
        }
        .onChange(of: settings.usageTimezoneIdentifier) { _, _ in
            Task { await store.refresh() }
        }
    }
}

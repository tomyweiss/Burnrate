import SwiftUI

enum PanelRoute: Hashable {
    case usage
    case settings
}

struct RootPanel: View {
    @Bindable var store: UsageStore
    @Bindable var settings: SettingsStore
    @Bindable var updates: UpdateManager
    @State private var route: PanelRoute = .usage
    @Namespace private var glassNamespace
    @AppStorage("panelTab") private var panelTabRaw = UsageTab.models.rawValue

    private let panelWidth: CGFloat = 380

    /// The Bench scatter needs more vertical room than the list tabs.
    private var panelHeight: CGFloat {
        route == .usage && panelTabRaw == UsageTab.bench.rawValue ? 680 : 520
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
                    onOpenSettings: { route = .settings }
                )
            case .settings:
                SettingsPanel(
                    settings: settings,
                    updates: updates,
                    store: store,
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
        }
        .onDisappear {
            MenuBarPanelKeeper.panelDidHide()
            route = .usage
        }
        .onChange(of: route) { _, _ in
            MenuBarPanelKeeper.keepOpen()
        }
        .onChange(of: settings.billingDayOfMonth) { _, _ in
            Task { await store.refresh() }
        }
        .onChange(of: settings.usageTimezoneIdentifier) { _, _ in
            Task { await store.refresh() }
        }
    }
}

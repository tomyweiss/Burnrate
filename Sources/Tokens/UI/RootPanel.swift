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

    private let panelWidth: CGFloat = 380
    private let panelHeight: CGFloat = 520

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
        .onAppear {
            MenuBarPanelKeeper.keepOpen()
            updates.autoCheckIfNeeded()
        }
        .onDisappear {
            route = .usage
        }
        .onChange(of: route) { _, _ in
            MenuBarPanelKeeper.keepOpen()
        }
    }
}

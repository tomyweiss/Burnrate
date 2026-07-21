import SwiftUI

enum PanelRoute: Hashable {
    case usage
    case settings
}

struct RootPanel: View {
    @Bindable var store: UsageStore
    @Bindable var settings: SettingsStore
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
                    glassNamespace: glassNamespace,
                    onOpenSettings: { route = .settings }
                )
            case .settings:
                SettingsPanel(
                    settings: settings,
                    glassNamespace: glassNamespace,
                    onBack: { route = .usage },
                    onTestNotification: {
                        Task { await store.sendTestNotification() }
                    }
                )
            }
        }
        .frame(width: panelWidth, height: panelHeight)
        .onAppear { MenuBarPanelKeeper.keepOpen() }
        .onChange(of: route) { _, _ in
            MenuBarPanelKeeper.keepOpen()
        }
    }
}

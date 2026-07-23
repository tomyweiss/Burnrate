import SwiftUI

enum PanelRoute: Hashable {
    case usage
    case settings
    case session(String)
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
                    onOpenSettings: { route = .settings },
                    onOpenSession: { id in
                        route = .session(store.snapshot.rootId(for: id))
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
            case .session(let id):
                if let conversation = store.snapshot.conversation(id: id) {
                    SessionDetailPanel(
                        conversation: conversation,
                        glassNamespace: glassNamespace,
                        onBack: { route = .usage }
                    )
                } else {
                    VStack(spacing: 12) {
                        HStack {
                            Button {
                                route = .usage
                                MenuBarPanelKeeper.keepOpen()
                            } label: {
                                Label("Sessions", systemImage: "chevron.left")
                            }
                            .buttonStyle(.borderless)
                            Spacer()
                        }
                        .padding()
                        Text("Session not found in this window.")
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
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
        .onChange(of: settings.billingDayOfMonth) { _, _ in
            Task { await store.refresh() }
        }
        .onChange(of: settings.usageTimezoneIdentifier) { _, _ in
            Task { await store.refresh() }
        }
    }
}
